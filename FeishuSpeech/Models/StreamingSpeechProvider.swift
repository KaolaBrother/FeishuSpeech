import Foundation
import os.log

private nonisolated let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "StreamingSpeechProvider"
)

protocol SpeechStreamingSession: Sendable {
    func sendAudioPacket(_ pcm16: Data) async throws -> StreamingRecognitionEvent
    func finish() async throws -> StreamingRecognitionEvent
    func cancel() async
}

protocol SpeechStreamingSessionProviding: Sendable {
    func makeStreamingSession(
        appId: String,
        appSecret: String
    ) async throws -> any SpeechStreamingSession
}
