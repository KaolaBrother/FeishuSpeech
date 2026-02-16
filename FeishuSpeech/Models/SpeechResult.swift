import Foundation

nonisolated struct AuthResponse: Decodable, Sendable {
    let code: Int
    let msg: String
    let tenantAccessToken: String?
    
    enum CodingKeys: String, CodingKey {
        case code, msg
        case tenantAccessToken = "tenant_access_token"
    }
}

nonisolated struct SpeechRequest: Encodable, Sendable {
    let speech: SpeechData
    let config: SpeechConfig
}

nonisolated struct SpeechData: Encodable, Sendable {
    let speech: String
}

nonisolated struct SpeechConfig: Encodable, Sendable {
    let fileId: String
    let format: String = "pcm"
    let engineType: String = "16k_auto"
    
    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case format
        case engineType = "engine_type"
    }
}

nonisolated struct SpeechResponse: Decodable, Sendable {
    let code: Int
    let msg: String
    let data: RecognitionData?
}

nonisolated struct RecognitionData: Decodable, Sendable {
    let recognitionText: String
    
    enum CodingKeys: String, CodingKey {
        case recognitionText = "recognition_text"
    }
}
