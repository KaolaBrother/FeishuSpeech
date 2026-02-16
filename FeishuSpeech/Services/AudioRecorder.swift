import Foundation
import AVFoundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.feishuspeech.app", category: "Audio")

class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    
    private var audioEngine: AVAudioEngine?
    private var audioBuffer = Data()
    private let targetSampleRate: Double = 16000
    
    override init() {
        super.init()
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        audioBuffer.removeAll()
        audioEngine = AVAudioEngine()
        
        guard let audioEngine = audioEngine else { return }
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        logger.info("Input format: sampleRate=\(inputFormat.sampleRate), channels=\(inputFormat.channelCount)")
        
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: targetSampleRate, channels: 1, interleaved: true)!
        
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            logger.error("Failed to create converter")
            return
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            
            let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * self.targetSampleRate / inputFormat.sampleRate)
            guard frameCount > 0,
                  let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else {
                return
            }
            
            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
            
            if let error = error {
                logger.error("Conversion error: \(error.localizedDescription)")
                return
            }
            
            if let channelData = convertedBuffer.int16ChannelData {
                let bytesToCopy = Int(convertedBuffer.frameLength) * 2
                let data = Data(bytes: channelData[0], count: bytesToCopy)
                self.audioBuffer.append(data)
            }
        }
        
        do {
            try audioEngine.start()
            isRecording = true
            logger.info("Recording started")
        } catch {
            logger.error("Failed to start audio engine: \(error.localizedDescription)")
        }
    }
    
    func stopRecording() -> Data {
        logger.info("Stopping recording, buffer size: \(self.audioBuffer.count) bytes")
        
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        isRecording = false
        
        let data = audioBuffer
        logger.info("Returning \(data.count) bytes of audio data")
        return data
    }
}
