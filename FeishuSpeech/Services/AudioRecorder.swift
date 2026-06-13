import Foundation
import AVFoundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.feishuspeech.app", category: "Audio")

private let targetSampleRate: Double = 16000
private let maxRecordingSeconds: Double = 60.0
private let estimatedMaxBufferSize = Int(targetSampleRate * 2 * maxRecordingSeconds)

enum RecordingFailure: LocalizedError, Equatable {
    case runtime
    case interrupted
    case deviceLost
    case formatConversion

    var errorDescription: String? {
        switch self {
        case .runtime:
            return "录音失败：音频采集运行错误"
        case .interrupted:
            return "录音中断：音频采集被系统中断"
        case .deviceLost:
            return "录音失败：麦克风设备断开"
        case .formatConversion:
            return "录音失败：音频格式转换失败"
        }
    }
}

class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published private(set) var failure: RecordingFailure?
    
    private var captureSession: AVCaptureSession?
    private var audioDataOutput: AVCaptureAudioDataOutput?
    private var audioBuffer = Data(capacity: estimatedMaxBufferSize)
    private let audioQueue = DispatchQueue(label: "com.feishuspeech.audio.queue")
    private let bufferQueue = DispatchQueue(label: "com.feishuspeech.audio.buffer")
    // Issue #9: AVCaptureSession.startRunning()/stopRunning() block synchronously, so they
    // must never run on the main actor (which the CGEventTap formerly shared). Run them on a
    // dedicated serial queue and flip @Published isRecording back on the main thread.
    private let sessionQueue = DispatchQueue(label: "com.feishuspeech.audio.session")
    
    private var audioConverter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var outputFormat: AVAudioFormat?
    private var conversionErrorCount = 0
    private let maxConversionErrors = 10
    private var notificationObservers: [NSObjectProtocol] = []
    
    override init() {
        super.init()
        logger.info("AudioRecorder initialized, buffer capacity: \(estimatedMaxBufferSize) bytes")
    }
    
    static var hasInputDevice: Bool {
        AVCaptureDevice.default(for: .audio) != nil
    }
    
    /// Starts a recording session.
    ///
    /// The synchronous `Bool` return reports the result of the config-check phase
    /// (device discovery + input/output wiring). The blocking `AVCaptureSession.startRunning()`
    /// is dispatched onto `sessionQueue` (issue #9 — it must not block the main actor that the
    /// CGEventTap formerly shared). The async started-confirmation is delivered via `completion`
    /// on the main queue, and `@Published var isRecording` is flipped to mirror it. Callers that
    /// only observe `isRecording` keep working unchanged via the default no-op closure.
    @discardableResult
    func startRecording(completion: @escaping (_ started: Bool) -> Void = { _ in }) -> Bool {
        // Always run forceCleanup() first so a stale isRecording flag (e.g. left over from a
        // cancelled or errored recording that forgot to reset state) never permanently prevents
        // a new session from starting.  forceCleanup() stops any running session and resets
        // isRecording to false, so every call to startRecording() starts from a clean slate.
        forceCleanup()

        audioBuffer.reserveCapacity(estimatedMaxBufferSize)
        audioConverter = nil
        inputFormat = nil
        outputFormat = nil
        conversionErrorCount = 0
        failure = nil
        
        logger.info("Starting fresh recording session")
        
        guard let microphone = AVCaptureDevice.default(for: .audio) else {
            logger.error("No microphone device available")
            completion(false)
            return false
        }

        do {
            let input = try AVCaptureDeviceInput(device: microphone)

            let session = AVCaptureSession()

            guard session.canAddInput(input) else {
                logger.error("Cannot add audio input to session")
                completion(false)
                return false
            }
            session.addInput(input)

            let output = AVCaptureAudioDataOutput()
            output.setSampleBufferDelegate(self, queue: audioQueue)

            guard session.canAddOutput(output) else {
                logger.error("Cannot add audio output to session")
                completion(false)
                return false
            }
            session.addOutput(output)

            captureSession = session
            audioDataOutput = output
            registerSessionNotifications(for: session, device: microphone)

            // Issue #9: startRunning() blocks — never on the main actor. Dispatch onto
            // sessionQueue, then flip @Published isRecording + deliver completion on main.
            // Set isRecording optimistically before the dispatch so quick-release (Fn up
            // arriving before startRunning() returns) sees the recording state in time.
            isRecording = true
            sessionQueue.async { [weak self] in
                session.startRunning()
                let started = session.isRunning
                DispatchQueue.main.async {
                    if !started {
                        self?.isRecording = false
                        logger.error("AVCaptureSession failed to start running")
                    } else {
                        logger.info("Recording started successfully")
                    }
                    completion(started)
                }
            }
            // Synchronous config-check phase succeeded.
            return true

        } catch {
            logger.error("Failed to create audio input: \(error.localizedDescription)")
            forceCleanup()
            completion(false)
            return false
        }
    }
    
    func stopRecording() -> Data {
        logger.info("Stopping recording")
        
        let data = bufferQueue.sync {
            logger.info("Buffer size: \(self.audioBuffer.count) bytes")
            return audioBuffer
        }
        
        forceCleanup()
        
        return data
    }
    
    func forceCleanup() {
        logger.info("Force cleanup - releasing all audio resources")
        removeSessionNotifications()

        // Issue #9: session.stopRunning() blocks — tear the session down on sessionQueue,
        // never on the main actor. Hand off the captured session before nil'ing references.
        if let session = captureSession {
            sessionQueue.async {
                if session.isRunning {
                    session.stopRunning()
                }
                for input in session.inputs {
                    session.removeInput(input)
                }
                for output in session.outputs {
                    session.removeOutput(output)
                }
            }
        }

        captureSession = nil
        audioDataOutput = nil
        audioConverter = nil
        inputFormat = nil
        outputFormat = nil

        bufferQueue.sync {
            audioBuffer.removeAll(keepingCapacity: true)
        }

        isRecording = false
        logger.info("Audio resources fully released")
    }

    private func registerSessionNotifications(for session: AVCaptureSession, device: AVCaptureDevice) {
        removeSessionNotifications()
        let center = NotificationCenter.default
        notificationObservers = [
            center.addObserver(
                forName: AVCaptureSession.runtimeErrorNotification,
                object: session,
                queue: nil
            ) { [weak self] _ in
                self?.abortRecording(with: .runtime)
            },
            center.addObserver(
                forName: AVCaptureSession.wasInterruptedNotification,
                object: session,
                queue: nil
            ) { [weak self] _ in
                self?.abortRecording(with: .interrupted)
            },
            center.addObserver(
                forName: AVCaptureDevice.wasDisconnectedNotification,
                object: device,
                queue: nil
            ) { [weak self] _ in
                self?.abortRecording(with: .deviceLost)
            }
        ]
    }

    private func removeSessionNotifications() {
        let center = NotificationCenter.default
        for observer in notificationObservers {
            center.removeObserver(observer)
        }
        notificationObservers.removeAll()
    }

    private func abortRecording(with failure: RecordingFailure) {
        logger.error("Recording failed: \(failure.localizedDescription)")
        if Thread.isMainThread {
            finishAbortingRecording(with: failure)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.finishAbortingRecording(with: failure)
            }
        }
    }

    private func finishAbortingRecording(with failure: RecordingFailure) {
        forceCleanup()
        self.failure = failure
    }

    private func incrementConversionErrorAndAbortIfNeeded() {
        conversionErrorCount += 1
        if conversionErrorCount >= maxConversionErrors {
            abortRecording(with: .formatConversion)
        }
    }
}

extension AudioRecorder: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard conversionErrorCount < maxConversionErrors else {
            abortRecording(with: .formatConversion)
            return
        }
        
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer),
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            logger.error("Invalid sample buffer")
            incrementConversionErrorAndAbortIfNeeded()
            return
        }
        
        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        let inputSampleRate = asbd?.pointee.mSampleRate ?? 48000
        let inputChannels = Int(asbd?.pointee.mChannelsPerFrame ?? 1)
        let bitsPerChannel = Int(asbd?.pointee.mBitsPerChannel ?? 32)
        
        guard inputSampleRate > 0, inputChannels > 0, bitsPerChannel > 0 else {
            logger.error("Invalid audio format: rate=\(inputSampleRate), channels=\(inputChannels), bits=\(bitsPerChannel)")
            incrementConversionErrorAndAbortIfNeeded()
            return
        }
        
        if audioConverter == nil {
            let commonFormat: AVAudioCommonFormat = (bitsPerChannel == 32) ? .pcmFormatFloat32 : .pcmFormatInt16
            inputFormat = AVAudioFormat(commonFormat: commonFormat, sampleRate: inputSampleRate, channels: AVAudioChannelCount(inputChannels), interleaved: false)
            outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: targetSampleRate, channels: 1, interleaved: true)
            
            guard let inputFmt = inputFormat, let outputFmt = outputFormat else {
                logger.error("Failed to create audio formats")
                incrementConversionErrorAndAbortIfNeeded()
                return
            }
            
            audioConverter = AVAudioConverter(from: inputFmt, to: outputFmt)
            
            if audioConverter != nil {
                logger.info("Converter created: \(inputSampleRate)Hz/\(bitsPerChannel)bit/\(inputChannels)ch -> \(targetSampleRate)Hz/16bit/1ch")
            } else {
                logger.error("Failed to create audio converter")
                incrementConversionErrorAndAbortIfNeeded()
                return
            }
        }
        
        let bytesPerSample = bitsPerChannel / 8
        let inputFrameCount = CMBlockBufferGetDataLength(blockBuffer) / Int(inputChannels) / bytesPerSample
        
        guard inputFrameCount > 0,
              let inputFmt = inputFormat,
              let outputFmt = outputFormat,
              let converter = audioConverter,
              let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFmt, frameCapacity: AVAudioFrameCount(inputFrameCount)) else {
            logger.error("Failed to create input buffer")
            incrementConversionErrorAndAbortIfNeeded()
            return
        }
        
        inputBuffer.frameLength = AVAudioFrameCount(inputFrameCount)
        
        let dataLength = CMBlockBufferGetDataLength(blockBuffer)
        
        if bitsPerChannel == 32 {
            var rawData = Data(count: dataLength)
            rawData.withUnsafeMutableBytes { rawBufferPointer in
                guard let baseAddress = rawBufferPointer.baseAddress else { return }
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: dataLength, destination: baseAddress)
            }
            
            if let floatData = inputBuffer.floatChannelData?[0] {
                rawData.withUnsafeBytes { rawBufferPointer in
                    if let baseAddress = rawBufferPointer.baseAddress?.assumingMemoryBound(to: Float.self) {
                        floatData.initialize(from: baseAddress, count: dataLength / 4)
                    }
                }
            }
        } else {
            guard let channelData = inputBuffer.int16ChannelData?[0] else {
                incrementConversionErrorAndAbortIfNeeded()
                return
            }
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: dataLength, destination: channelData)
        }
        
        let outputFrameCount = AVAudioFrameCount(Double(inputFrameCount) * targetSampleRate / inputSampleRate)
        guard outputFrameCount > 0,
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFmt, frameCapacity: outputFrameCount) else {
            logger.error("Failed to create output buffer")
            incrementConversionErrorAndAbortIfNeeded()
            return
        }
        
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }
        
        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        if let error = error {
            logger.error("Conversion error: \(error.localizedDescription)")
            incrementConversionErrorAndAbortIfNeeded()
            return
        }
        
        if let channelData = outputBuffer.int16ChannelData {
            let bytesToCopy = Int(outputBuffer.frameLength) * 2
            guard bytesToCopy > 0 else { return }
            
            let data = Data(bytes: channelData[0], count: bytesToCopy)
            
            bufferQueue.sync {
                guard self.audioBuffer.count + data.count <= estimatedMaxBufferSize else {
                    logger.warning("Buffer overflow prevented")
                    return
                }
                self.audioBuffer.append(data)
            }
        }
    }
}

#if DEBUG
extension AudioRecorder {
    func forceSetRecordingForTesting(_ value: Bool) {
        isRecording = value
    }

    func simulateRuntimeErrorForTesting() {
        abortRecording(with: .runtime)
    }

    func simulateDeviceLossForTesting() {
        abortRecording(with: .deviceLost)
    }

    func simulateConversionErrorExhaustionForTesting() {
        conversionErrorCount = maxConversionErrors - 1
        incrementConversionErrorAndAbortIfNeeded()
    }
}
#endif
