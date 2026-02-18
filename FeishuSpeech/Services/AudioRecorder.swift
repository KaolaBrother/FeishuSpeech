import Foundation
import AVFoundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.feishuspeech.app", category: "Audio")

private let targetSampleRate: Double = 16000
private let maxRecordingSeconds: Double = 60.0
private let estimatedMaxBufferSize = Int(targetSampleRate * 2 * maxRecordingSeconds)

class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    
    private var captureSession: AVCaptureSession?
    private var audioDataOutput: AVCaptureAudioDataOutput?
    private var audioBuffer = Data(capacity: estimatedMaxBufferSize)
    private let audioQueue = DispatchQueue(label: "com.feishuspeech.audio.queue")
    private let bufferQueue = DispatchQueue(label: "com.feishuspeech.audio.buffer")
    
    private var audioConverter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var outputFormat: AVAudioFormat?
    private var conversionErrorCount = 0
    private let maxConversionErrors = 10
    
    override init() {
        super.init()
        logger.info("AudioRecorder initialized, buffer capacity: \(estimatedMaxBufferSize) bytes")
    }
    
    static var hasInputDevice: Bool {
        AVCaptureDevice.default(for: .audio) != nil
    }
    
    @discardableResult
    func startRecording() -> Bool {
        guard !isRecording else {
            logger.warning("Already recording, skipping start")
            return false
        }
        
        forceCleanup()
        
        audioBuffer.reserveCapacity(estimatedMaxBufferSize)
        audioConverter = nil
        inputFormat = nil
        outputFormat = nil
        conversionErrorCount = 0
        
        logger.info("Starting fresh recording session")
        
        guard let microphone = AVCaptureDevice.default(for: .audio) else {
            logger.error("No microphone device available")
            return false
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: microphone)
            
            let session = AVCaptureSession()
            
            guard session.canAddInput(input) else {
                logger.error("Cannot add audio input to session")
                return false
            }
            session.addInput(input)
            
            let output = AVCaptureAudioDataOutput()
            output.setSampleBufferDelegate(self, queue: audioQueue)
            
            guard session.canAddOutput(output) else {
                logger.error("Cannot add audio output to session")
                return false
            }
            session.addOutput(output)
            
            captureSession = session
            audioDataOutput = output
            
            session.startRunning()
            isRecording = true
            logger.info("Recording started successfully")
            return true
            
        } catch {
            logger.error("Failed to create audio input: \(error.localizedDescription)")
            forceCleanup()
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
        
        if let session = captureSession {
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
}

extension AudioRecorder: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard conversionErrorCount < maxConversionErrors else {
            return
        }
        
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer),
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            logger.error("Invalid sample buffer")
            conversionErrorCount += 1
            return
        }
        
        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        let inputSampleRate = asbd?.pointee.mSampleRate ?? 48000
        let inputChannels = Int(asbd?.pointee.mChannelsPerFrame ?? 1)
        let bitsPerChannel = Int(asbd?.pointee.mBitsPerChannel ?? 32)
        
        guard inputSampleRate > 0, inputChannels > 0, bitsPerChannel > 0 else {
            logger.error("Invalid audio format: rate=\(inputSampleRate), channels=\(inputChannels), bits=\(bitsPerChannel)")
            conversionErrorCount += 1
            return
        }
        
        if audioConverter == nil {
            let commonFormat: AVAudioCommonFormat = (bitsPerChannel == 32) ? .pcmFormatFloat32 : .pcmFormatInt16
            inputFormat = AVAudioFormat(commonFormat: commonFormat, sampleRate: inputSampleRate, channels: AVAudioChannelCount(inputChannels), interleaved: false)
            outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: targetSampleRate, channels: 1, interleaved: true)
            
            guard let inputFmt = inputFormat, let outputFmt = outputFormat else {
                logger.error("Failed to create audio formats")
                conversionErrorCount += 1
                return
            }
            
            audioConverter = AVAudioConverter(from: inputFmt, to: outputFmt)
            
            if audioConverter != nil {
                logger.info("Converter created: \(inputSampleRate)Hz/\(bitsPerChannel)bit/\(inputChannels)ch -> \(targetSampleRate)Hz/16bit/1ch")
            } else {
                logger.error("Failed to create audio converter")
                conversionErrorCount += 1
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
            conversionErrorCount += 1
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
                conversionErrorCount += 1
                return
            }
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: dataLength, destination: channelData)
        }
        
        let outputFrameCount = AVAudioFrameCount(Double(inputFrameCount) * targetSampleRate / inputSampleRate)
        guard outputFrameCount > 0,
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFmt, frameCapacity: outputFrameCount) else {
            logger.error("Failed to create output buffer")
            conversionErrorCount += 1
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
            conversionErrorCount += 1
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
