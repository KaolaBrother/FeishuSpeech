import Foundation
import Network
import os.log

private nonisolated(unsafe) let logger = Logger(subsystem: "com.feishuspeech.app", category: "API")

private let requestTimeout: TimeInterval = 30
private let maxRetries = 3
private let retryDelay: TimeInterval = 1.0

actor FeishuAPIService {
    static let shared = FeishuAPIService()
    
    private var cachedToken: String?
    private var tokenExpiry: Date?
    private var lastNetworkError: Error?
    private var networkMonitor: NWPathMonitor?
    private var isNetworkAvailable = true
    
    private let authURL = URL(string: "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal")!
    private let speechURL = URL(string: "https://open.feishu.cn/open-apis/speech_to_text/v1/speech/file_recognize")!
    
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    
    private var urlSession: URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = requestTimeout * 2
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }
    
    private init() {
        startNetworkMonitoring()
    }
    
    private func startNetworkMonitoring() {
        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            Task {
                await self?.handleNetworkChange(path: path)
            }
        }
        networkMonitor?.start(queue: DispatchQueue(label: "com.feishuspeech.network"))
    }
    
    private func handleNetworkChange(path: NWPath) {
        let wasAvailable = isNetworkAvailable
        isNetworkAvailable = path.status == .satisfied
        
        if !wasAvailable && isNetworkAvailable {
            logger.info("Network recovered, clearing token cache")
            cachedToken = nil
            tokenExpiry = nil
        }
        
        if !isNetworkAvailable {
            logger.warning("Network unavailable")
        }
    }
    
    private func generateFileId() -> String {
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<16).map { _ in chars.randomElement()! })
    }
    
    func recognizeSpeech(audioData: Data, appId: String, appSecret: String) async throws -> String {
        logger.info("Recognizing speech, audio size: \(audioData.count) bytes")
        
        if audioData.isEmpty {
            throw APIError.recognitionFailed("没有录到音频数据，请检查麦克风权限")
        }
        
        if !isNetworkAvailable {
            throw APIError.networkUnavailable
        }
        
        return try await withRetry {
            let token = try await self.getAccessToken(appId: appId, appSecret: appSecret)
            logger.info("Got access token")
            return try await self.sendSpeechRequest(audioData: audioData, token: token)
        }
    }
    
    private func withRetry<T>(maxAttempts: Int = maxRetries, operation: () async throws -> T) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...maxAttempts {
            if !isNetworkAvailable {
                throw APIError.networkUnavailable
            }
            
            do {
                return try await operation()
            } catch let error as APIError {
                lastError = error
                logger.warning("Attempt \(attempt)/\(maxAttempts) failed: \(error.localizedDescription)")
                
                switch error {
                case .networkUnavailable, .authFailed:
                    throw error
                default:
                    break
                }
                
                if attempt < maxAttempts {
                    let delay = retryDelay * Double(attempt)
                    logger.info("Retrying in \(delay)s...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            } catch {
                lastError = error
                logger.warning("Attempt \(attempt)/\(maxAttempts) failed: \(error.localizedDescription)")
                
                if attempt < maxAttempts {
                    let delay = retryDelay * Double(attempt)
                    logger.info("Retrying in \(delay)s...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? APIError.unknown
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
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch let error as URLError {
            throw mapURLError(error)
        }
        
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
        
        logger.info("Sending speech request with fileId: \(fileId)")
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch let error as URLError {
            throw mapURLError(error)
        }
        
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
    
    private func mapURLError(_ error: URLError) -> APIError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return .networkUnavailable
        case .timedOut:
            return .timeout
        case .cannotConnectToHost, .dnsLookupFailed, .cannotFindHost:
            return .connectionFailed
        default:
            return .networkError(error.localizedDescription)
        }
    }
    
    enum APIError: LocalizedError {
        case invalidResponse
        case httpError(Int)
        case authFailed(String)
        case recognitionFailed(String)
        case timeout
        case networkUnavailable
        case connectionFailed
        case networkError(String)
        case unknown
        
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
            case .timeout:
                return "请求超时，请检查网络"
            case .networkUnavailable:
                return "网络不可用，请检查网络连接"
            case .connectionFailed:
                return "无法连接到服务器"
            case .networkError(let msg):
                return "网络错误: \(msg)"
            case .unknown:
                return "未知错误"
            }
        }
    }
}
