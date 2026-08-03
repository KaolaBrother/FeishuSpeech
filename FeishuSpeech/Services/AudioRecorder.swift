import AVFoundation
import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "com.feishuspeech.app", category: "Audio")

private let targetSampleRate: Double = 16000
private let maxRecordingSeconds: Double = 60.0
private let estimatedMaxBufferSize = Int(targetSampleRate * 2 * maxRecordingSeconds)

private struct CapturedAudioSample {
    let blockBuffer: CMBlockBuffer
    let sampleRate: Double
    let channelCount: Int
    let bitsPerChannel: Int

    var dataLength: Int {
        CMBlockBufferGetDataLength(blockBuffer)
    }

    var inputFrameCount: Int {
        dataLength / channelCount / (bitsPerChannel / 8)
    }
}

private struct AudioConversionInput {
    let buffer: AVAudioPCMBuffer
    let outputFormat: AVAudioFormat
    let converter: AVAudioConverter
}

enum RecordingFailure: LocalizedError, Equatable {
    case runtime
    case interrupted
    case deviceLost
    case formatConversion
    case ingressOverflow

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
        case .ingressOverflow:
            return "录音失败：音频处理速度不足"
        }
    }
}

class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published private(set) var failure: RecordingFailure?
    
    private var captureSession: AVCaptureSession?
    private var audioDataOutput: AVCaptureAudioDataOutput?
    private var audioBuffer = Data(capacity: estimatedMaxBufferSize)
    private var activeStreamingIngress: ByteBoundedAudioIngress?
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
        startCapture(streamingIngress: nil, completion: completion)
    }

    @discardableResult
    func startStreamingRecording(
        ingress: ByteBoundedAudioIngress,
        completion: @escaping (_ started: Bool) -> Void
    ) -> Bool {
        startCapture(streamingIngress: ingress, completion: completion)
    }

    private func startCapture(
        streamingIngress: ByteBoundedAudioIngress?,
        completion: @escaping (_ started: Bool) -> Void
    ) -> Bool {
        // Always run forceCleanup() first so a stale isRecording flag (e.g. left over from a
        // cancelled or errored recording that forgot to reset state) never permanently prevents
        // a new session from starting.  forceCleanup() stops any running session and resets
        // isRecording to false, so every call to startRecording() starts from a clean slate.
        forceCleanup()

        bufferQueue.sync {
            activeStreamingIngress = streamingIngress
            audioBuffer.reserveCapacity(estimatedMaxBufferSize)
        }
        audioConverter = nil
        inputFormat = nil
        outputFormat = nil
        conversionErrorCount = 0
        failure = nil
        
        logger.info("Starting fresh recording session")
        
        guard let microphone = AVCaptureDevice.default(for: .audio) else {
            logger.error("No microphone device available")
            failStreamingCaptureSetupIfNeeded()
            completion(false)
            return false
        }

        do {
            let input = try AVCaptureDeviceInput(device: microphone)

            let session = AVCaptureSession()

            guard session.canAddInput(input) else {
                logger.error("Cannot add audio input to session")
                failStreamingCaptureSetupIfNeeded()
                completion(false)
                return false
            }
            session.addInput(input)

            let output = AVCaptureAudioDataOutput()
            output.setSampleBufferDelegate(self, queue: audioQueue)

            guard session.canAddOutput(output) else {
                logger.error("Cannot add audio output to session")
                failStreamingCaptureSetupIfNeeded()
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
                        logger.error("AVCaptureSession failed to start running")
                        self?.finishAbortingRecording(with: .runtime)
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
            terminateActiveIngress(with: .captureFailed)
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

    func stopStreamingRecording(streamEstablished: Bool) async {
        logger.info("Stopping streaming recording")
        removeSessionNotifications()

        let session = captureSession
        let output = audioDataOutput
        isRecording = false

        await withCheckedContinuation { continuation in
            sessionQueue.async {
                Self.tearDown(session)
                continuation.resume()
            }
        }

        await withCheckedContinuation { continuation in
            audioQueue.async { [weak self] in
                // stopRunning() has returned, so no new callbacks for this output can be
                // scheduled. Reaching this block proves every callback already queued on the
                // real delegate queue has finished while the output identity was still valid.
                if self?.audioDataOutput === output {
                    self?.audioDataOutput = nil
                }
                continuation.resume()
            }
        }

        if captureSession === session {
            captureSession = nil
        }

        bufferQueue.sync {
            let ingress = activeStreamingIngress
            activeStreamingIngress = nil
            let establishedAfterBarrier = streamEstablished
                || ingress?.hasEmittedFullPacket == true
            ingress?.finish(streamEstablished: establishedAfterBarrier)
        }

        audioConverter = nil
        inputFormat = nil
        outputFormat = nil
        logger.info("Streaming audio resources released")
    }
    
    func forceCleanup() {
        logger.info("Force cleanup - releasing all audio resources")
        terminateActiveIngress(with: .cancelled)
        removeSessionNotifications()

        // Issue #9: session.stopRunning() blocks — tear the session down on sessionQueue,
        // never on the main actor. Hand off the captured session before nil'ing references.
        if let session = captureSession {
            sessionQueue.async {
                Self.tearDown(session)
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
        terminateActiveIngress(with: .captureFailed)
        forceCleanup()
        self.failure = failure
    }

    private func failStreamingCaptureSetupIfNeeded() {
        terminateActiveIngress(with: .captureFailed)
        captureSession = nil
        audioDataOutput = nil
        isRecording = false
    }

    private func terminateActiveIngress(with error: AudioIngressError) {
        bufferQueue.sync {
            let ingress = activeStreamingIngress
            activeStreamingIngress = nil
            ingress?.fail(error)
        }
    }

    private static func tearDown(_ session: AVCaptureSession?) {
        guard let session else { return }
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

    private func incrementConversionErrorAndAbortIfNeeded() {
        conversionErrorCount += 1
        if conversionErrorCount >= maxConversionErrors {
            abortRecording(with: .formatConversion)
        }
    }
}

extension AudioRecorder: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard output === audioDataOutput else { return }
        guard conversionErrorCount < maxConversionErrors else {
            abortRecording(with: .formatConversion)
            return
        }

        guard let sample = capturedAudioSample(from: sampleBuffer),
              configureConverterIfNeeded(for: sample),
              let input = makeConversionInput(for: sample),
              let outputBuffer = convert(sample: sample, input: input),
              let data = convertedData(from: outputBuffer) else { return }

        publishConvertedAudio(data)
    }

    private func capturedAudioSample(from sampleBuffer: CMSampleBuffer) -> CapturedAudioSample? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer),
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            logger.error("Invalid sample buffer")
            incrementConversionErrorAndAbortIfNeeded()
            return nil
        }

        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        let sampleRate = asbd?.pointee.mSampleRate ?? 48000
        let channelCount = Int(asbd?.pointee.mChannelsPerFrame ?? 1)
        let bitsPerChannel = Int(asbd?.pointee.mBitsPerChannel ?? 32)

        guard sampleRate > 0, channelCount > 0, bitsPerChannel > 0 else {
            logger.error("Invalid audio format: rate=\(sampleRate), channels=\(channelCount), bits=\(bitsPerChannel)")
            incrementConversionErrorAndAbortIfNeeded()
            return nil
        }

        return CapturedAudioSample(
            blockBuffer: blockBuffer,
            sampleRate: sampleRate,
            channelCount: channelCount,
            bitsPerChannel: bitsPerChannel
        )
    }

    private func configureConverterIfNeeded(for sample: CapturedAudioSample) -> Bool {
        guard audioConverter == nil else { return true }

        let commonFormat: AVAudioCommonFormat = sample.bitsPerChannel == 32
            ? .pcmFormatFloat32
            : .pcmFormatInt16
        inputFormat = AVAudioFormat(
            commonFormat: commonFormat,
            sampleRate: sample.sampleRate,
            channels: AVAudioChannelCount(sample.channelCount),
            interleaved: false
        )
        outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        )

        guard let inputFormat, let outputFormat else {
            logger.error("Failed to create audio formats")
            incrementConversionErrorAndAbortIfNeeded()
            return false
        }

        audioConverter = AVAudioConverter(from: inputFormat, to: outputFormat)

        guard audioConverter != nil else {
            logger.error("Failed to create audio converter")
            incrementConversionErrorAndAbortIfNeeded()
            return false
        }

        logger.info("Converter created: \(sample.sampleRate)Hz/\(sample.bitsPerChannel)bit/\(sample.channelCount)ch -> \(targetSampleRate)Hz/16bit/1ch")
        return true
    }

    private func makeConversionInput(for sample: CapturedAudioSample) -> AudioConversionInput? {
        guard sample.inputFrameCount > 0,
              let inputFormat,
              let outputFormat,
              let converter = audioConverter,
              let inputBuffer = AVAudioPCMBuffer(
                  pcmFormat: inputFormat,
                  frameCapacity: AVAudioFrameCount(sample.inputFrameCount)
              ) else {
            logger.error("Failed to create input buffer")
            incrementConversionErrorAndAbortIfNeeded()
            return nil
        }

        inputBuffer.frameLength = AVAudioFrameCount(sample.inputFrameCount)
        guard populate(inputBuffer, from: sample) else {
            incrementConversionErrorAndAbortIfNeeded()
            return nil
        }

        return AudioConversionInput(
            buffer: inputBuffer,
            outputFormat: outputFormat,
            converter: converter
        )
    }

    private func populate(_ inputBuffer: AVAudioPCMBuffer, from sample: CapturedAudioSample) -> Bool {
        if sample.bitsPerChannel == 32 {
            var rawData = Data(count: sample.dataLength)
            rawData.withUnsafeMutableBytes { rawBufferPointer in
                guard let baseAddress = rawBufferPointer.baseAddress else { return }
                CMBlockBufferCopyDataBytes(
                    sample.blockBuffer,
                    atOffset: 0,
                    dataLength: sample.dataLength,
                    destination: baseAddress
                )
            }

            if let floatData = inputBuffer.floatChannelData?[0] {
                rawData.withUnsafeBytes { rawBufferPointer in
                    if let baseAddress = rawBufferPointer.baseAddress?.assumingMemoryBound(to: Float.self) {
                        floatData.initialize(from: baseAddress, count: sample.dataLength / 4)
                    }
                }
            }
            return true
        }

        guard let channelData = inputBuffer.int16ChannelData?[0] else { return false }
        CMBlockBufferCopyDataBytes(
            sample.blockBuffer,
            atOffset: 0,
            dataLength: sample.dataLength,
            destination: channelData
        )
        return true
    }

    private func convert(
        sample: CapturedAudioSample,
        input: AudioConversionInput
    ) -> AVAudioPCMBuffer? {
        let outputFrameCount = AVAudioFrameCount(
            Double(sample.inputFrameCount) * targetSampleRate / sample.sampleRate
        )
        guard outputFrameCount > 0,
              let outputBuffer = AVAudioPCMBuffer(
                  pcmFormat: input.outputFormat,
                  frameCapacity: outputFrameCount
              ) else {
            logger.error("Failed to create output buffer")
            incrementConversionErrorAndAbortIfNeeded()
            return nil
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return input.buffer
        }

        input.converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if let error {
            logger.error("Conversion error: \(error.localizedDescription)")
            incrementConversionErrorAndAbortIfNeeded()
            return nil
        }

        return outputBuffer
    }

    private func convertedData(from outputBuffer: AVAudioPCMBuffer) -> Data? {
        guard let channelData = outputBuffer.int16ChannelData else { return nil }
        let bytesToCopy = Int(outputBuffer.frameLength) * 2
        guard bytesToCopy > 0 else { return nil }
        return Data(bytes: channelData[0], count: bytesToCopy)
    }

    private func publishConvertedAudio(_ data: Data) {
        let streamingError = bufferQueue.sync { () -> AudioIngressError? in
            if let activeStreamingIngress {
                return activeStreamingIngress.append(data)
            }

            guard audioBuffer.count + data.count <= estimatedMaxBufferSize else {
                logger.warning("Buffer overflow prevented")
                return nil
            }
            audioBuffer.append(data)
            return nil
        }

        if streamingError == .ingressOverflow {
            abortRecording(with: .ingressOverflow)
        }
    }
}

#if DEBUG
extension AudioRecorder {
    func attachStreamingIngressForTesting(_ ingress: ByteBoundedAudioIngress) {
        forceCleanup()
        bufferQueue.sync {
            activeStreamingIngress = ingress
        }
        isRecording = true
    }

    func publishConvertedAudioForTesting(_ data: Data) {
        publishConvertedAudio(data)
    }

    func enqueueConvertedAudioCallbackForTesting(
        _ data: Data,
        started: @escaping () -> Void,
        release: @escaping () -> Void
    ) {
        audioQueue.async { [weak self] in
            started()
            release()
            self?.publishConvertedAudio(data)
        }
    }

    func sealStreamingForTesting(streamEstablished: Bool) async {
        await stopStreamingRecording(streamEstablished: streamEstablished)
    }

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
