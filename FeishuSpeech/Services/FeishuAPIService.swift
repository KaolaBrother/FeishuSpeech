import Foundation
import os.log

private nonisolated(unsafe) let logger = Logger(subsystem: "com.feishuspeech.app", category: "API")

actor FeishuAPIService {
    static let shared = FeishuAPIService()
    
    private var cachedToken: String?
    private var tokenExpiry: Date?
    
    private let authURL = URL(string: "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal")!
    private let speechURL = URL(string: "https://open.feishu.cn/open-apis/speech_to_text/v1/speech/file_recognize")!
    
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    
    private func generateFileId() -> String {
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<16).map { _ in chars.randomElement()! })
    }
    
    func recognizeSpeech(audioData: Data, appId: String, appSecret: String) async throws -> String {
        logger.info("Recognizing speech, audio size: \(audioData.count) bytes")
        
        if audioData.isEmpty {
            throw APIError.recognitionFailed("没有录到音频数据，请检查麦克风权限")
        }
        
        let token = try await getAccessToken(appId: appId, appSecret: appSecret)
        logger.info("Got access token")
        return try await sendSpeechRequest(audioData: audioData, token: token)
    }
    
    private func getAccessToken(appId: String, appSecret: String) async throws -> String {
        if let cached = cachedToken, let expiry = tokenExpiry, Date() < expiry {
            logger.info("Using cached token")
            return cached
        }
        
        logger.info("Requesting new access token")
        
        var request = URLRequest(url: authURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = [
            "app_id": appId,
            "app_secret": appSecret
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        logger.info("Auth response status: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        let authResponse = try decoder.decode(AuthResponse.self, from: data)
        
        guard authResponse.code == 0, let token = authResponse.tenantAccessToken else {
            logger.error("Auth failed: \(authResponse.msg)")
            throw APIError.authFailed(authResponse.msg)
        }
        
        cachedToken = token
        tokenExpiry = Date().addingTimeInterval(7000)
        
        logger.info("Access token obtained successfully")
        return token
    }
    
    private func sendSpeechRequest(audioData: Data, token: String) async throws -> String {
        var request = URLRequest(url: speechURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let fileId = generateFileId()
        let speechRequest = SpeechRequest(
            speech: SpeechData(speech: audioData.base64EncodedString()),
            config: SpeechConfig(fileId: fileId)
        )
        request.httpBody = try encoder.encode(speechRequest)
        
        logger.info("Sending speech request to \(self.speechURL.absoluteString) with fileId: \(fileId)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        logger.info("Speech API response status: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let responseString = String(data: data, encoding: .utf8) ?? "No response body"
            logger.error("Speech API error response: \(responseString)")
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        let speechResponse = try decoder.decode(SpeechResponse.self, from: data)
        
        guard speechResponse.code == 0, let result = speechResponse.data else {
            logger.error("Recognition failed: \(speechResponse.msg)")
            throw APIError.recognitionFailed(speechResponse.msg)
        }
        
        logger.info("Recognition successful: \(result.recognitionText)")
        return result.recognitionText
    }
    
    enum APIError: LocalizedError {
        case invalidResponse
        case httpError(Int)
        case authFailed(String)
        case recognitionFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "无效响应"
            case .httpError(let code):
                return "HTTP 错误: \(code)"
            case .authFailed(let msg):
                return "认证失败: \(msg)"
            case .recognitionFailed(let msg):
                return "识别失败: \(msg)"
            }
        }
    }
}
