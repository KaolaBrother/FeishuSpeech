import Foundation
import Network
import Security
import os.log

private nonisolated(unsafe) let logger = Logger(subsystem: "com.feishuspeech.app", category: "API")

private nonisolated let requestTimeout: TimeInterval = 30
private nonisolated let maxRetries = 3
private nonisolated let retryDelay: TimeInterval = 1.0
private nonisolated let feishuAPIHost = "open.feishu.cn"
private nonisolated let authPath = "/open-apis/auth/v3/tenant_access_token/internal"
private nonisolated let speechPath = "/open-apis/speech_to_text/v1/speech/file_recognize"
private nonisolated let feishuDirectIPs = [
    "101.73.101.8",
    "60.9.0.98",
    "221.195.244.15",
    "119.249.53.155",
    "116.136.165.49"
]

private nonisolated struct DirectHTTPResponse {
    let statusCode: Int
    let body: Data
}

private final class CancelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var connection: NWConnection?
    private var abort: (() -> Void)?
    private var cancelled = false

    func store(connection: NWConnection, abort: @escaping () -> Void) {
        lock.lock()
        if cancelled {
            lock.unlock()
            connection.forceCancel()
            abort()
            return
        }
        self.connection = connection
        self.abort = abort
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let connection = self.connection
        let abort = self.abort
        self.connection = nil
        self.abort = nil
        lock.unlock()

        connection?.forceCancel()
        abort?()
    }
}

private nonisolated final class DirectFeishuHTTPClient {
    private let host: String
    private let ipAddress: String
    private let path: String
    private let headers: [String: String]
    private let body: Data
    private let timeout: TimeInterval

    init(host: String, ipAddress: String, path: String, headers: [String: String], body: Data, timeout: TimeInterval) {
        self.host = host
        self.ipAddress = ipAddress
        self.path = path
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }

    func send() async throws -> DirectHTTPResponse {
        let cancelBox = CancelBox()
        return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "com.feishuspeech.direct-http")
            let tlsOptions = NWProtocolTLS.Options()
            sec_protocol_options_set_tls_server_name(tlsOptions.securityProtocolOptions, host)

            let parameters = NWParameters(tls: tlsOptions)
            let connection = NWConnection(host: NWEndpoint.Host(ipAddress), port: 443, using: parameters)
            let lock = NSLock()
            var isFinished = false
            var responseData = Data()

            func finish(_ result: Result<DirectHTTPResponse, Error>) {
                lock.lock()
                guard !isFinished else {
                    lock.unlock()
                    return
                }
                isFinished = true
                lock.unlock()

                connection.cancel()
                continuation.resume(with: result)
            }

            func receiveLoop() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                    if let data, !data.isEmpty {
                        responseData.append(data)
                    }

                    if let error {
                        finish(.failure(error))
                        return
                    }

                    if isComplete {
                        do {
                            finish(.success(try Self.parseResponse(responseData)))
                        } catch {
                            finish(.failure(error))
                        }
                        return
                    }

                    receiveLoop()
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    var requestHeaders = [
                        "Host": self.host,
                        "Accept": "application/json",
                        "Content-Length": "\(self.body.count)",
                        "Connection": "close"
                    ]
                    self.headers.forEach { requestHeaders[$0.key] = $0.value }

                    let headerLines = requestHeaders
                        .map { "\($0.key): \($0.value)" }
                        .joined(separator: "\r\n")
                    var requestData = Data("POST \(self.path) HTTP/1.1\r\n\(headerLines)\r\n\r\n".utf8)
                    requestData.append(self.body)

                    connection.send(content: requestData, completion: .contentProcessed { error in
                        if let error {
                            finish(.failure(error))
                        } else {
                            receiveLoop()
                        }
                    })
                case .waiting(let error):
                    finish(.failure(error))
                case .failed(let error):
                    finish(.failure(error))
                case .cancelled:
                    break
                default:
                    break
                }
            }

            queue.asyncAfter(deadline: .now() + timeout) {
                finish(.failure(FeishuAPIService.APIError.timeout))
            }

            connection.start(queue: queue)
            cancelBox.store(connection: connection) {
                finish(.failure(CancellationError()))
            }
        }
        } onCancel: {
            cancelBox.cancel()
        }
    }

    private static func parseResponse(_ responseData: Data) throws -> DirectHTTPResponse {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let headerRange = responseData.range(of: delimiter),
              let headerText = String(data: responseData[..<headerRange.lowerBound], encoding: .utf8) else {
            throw FeishuAPIService.APIError.invalidResponse
        }

        let statusLine = headerText.components(separatedBy: "\r\n").first ?? ""
        let statusParts = statusLine.split(separator: " ")
        guard statusParts.count >= 2, let statusCode = Int(statusParts[1]) else {
            throw FeishuAPIService.APIError.invalidResponse
        }

        let rawBody = responseData[headerRange.upperBound...]
        let headers = parseHeaders(headerText)
        let body: Data

        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
            body = try decodeChunkedBody(Data(rawBody))
        } else {
            body = Data(rawBody)
        }

        return DirectHTTPResponse(statusCode: statusCode, body: body)
    }

    private static func parseHeaders(_ headerText: String) -> [String: String] {
        var headers: [String: String] = [:]

        for line in headerText.components(separatedBy: "\r\n").dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }

        return headers
    }

    private static func decodeChunkedBody(_ data: Data) throws -> Data {
        var decoded = Data()
        var index = data.startIndex
        let lineDelimiter = Data("\r\n".utf8)

        while index < data.endIndex {
            guard let lineRange = data[index...].range(of: lineDelimiter),
                  let sizeLine = String(data: data[index..<lineRange.lowerBound], encoding: .ascii) else {
                throw FeishuAPIService.APIError.invalidResponse
            }

            let sizeText = sizeLine.split(separator: ";", maxSplits: 1).first ?? ""
            guard let chunkSize = Int(sizeText.trimmingCharacters(in: .whitespacesAndNewlines), radix: 16) else {
                throw FeishuAPIService.APIError.invalidResponse
            }

            index = lineRange.upperBound

            if chunkSize == 0 {
                return decoded
            }

            let chunkEnd = index + chunkSize
            guard chunkEnd <= data.endIndex else {
                throw FeishuAPIService.APIError.invalidResponse
            }

            decoded.append(data[index..<chunkEnd])
            index = chunkEnd

            guard data[index...].starts(with: lineDelimiter) else {
                throw FeishuAPIService.APIError.invalidResponse
            }
            index += lineDelimiter.count
        }

        return decoded
    }
}

actor FeishuAPIService {
    static let shared = FeishuAPIService()

    private var cachedToken: String?
    private var tokenExpiry: Date?
    private var lastNetworkError: Error?
    private var networkMonitor: NWPathMonitor?
    private var isNetworkAvailable = true

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

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

    func resetState() {
        cachedToken = nil
        tokenExpiry = nil
        lastNetworkError = nil
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

                guard error.isRetriable else { throw error }

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

        let body: [String: String] = [
            "app_id": appId,
            "app_secret": appSecret
        ]
        let requestBody = try JSONSerialization.data(withJSONObject: body)

        let response = try await sendDirectRequest(
            path: authPath,
            headers: ["Content-Type": "application/json"],
            body: requestBody
        )

        logger.info("Auth response status: \(response.statusCode)")

        guard response.statusCode == 200 else {
            throw APIError.httpError(response.statusCode)
        }

        let authResponse = try decoder.decode(AuthResponse.self, from: response.body)

        guard authResponse.code == 0, let token = authResponse.tenantAccessToken else {
            logger.error("Auth failed: \(authResponse.msg)")
            throw APIError.authFailed(authResponse.msg)
        }

        cachedToken = token
        tokenExpiry = Date().addingTimeInterval(6000)

        logger.info("Access token obtained successfully")
        return token
    }

    private func sendSpeechRequest(audioData: Data, token: String) async throws -> String {
        let fileId = generateFileId()
        let speechRequest = SpeechRequest(
            speech: SpeechData(speech: audioData.base64EncodedString()),
            config: SpeechConfig(fileId: fileId)
        )
        let requestBody = try encoder.encode(speechRequest)

        logger.info("Sending speech request with fileId: \(fileId)")

        let response = try await sendDirectRequest(
            path: speechPath,
            headers: [
                "Authorization": "Bearer \(token)",
                "Content-Type": "application/json"
            ],
            body: requestBody
        )

        logger.info("Speech API response status: \(response.statusCode)")

        guard response.statusCode == 200 else {
            let responseString = String(data: response.body, encoding: .utf8) ?? "No response body"
            logger.error("Speech API error response: \(responseString)")

            if response.statusCode == 400 || response.statusCode == 401 {
                cachedToken = nil
                tokenExpiry = nil
            }

            throw APIError.httpError(response.statusCode)
        }

        let speechResponse = try decoder.decode(SpeechResponse.self, from: response.body)

        guard speechResponse.code == 0, let result = speechResponse.data else {
            logger.error("Recognition failed: \(speechResponse.msg)")
            throw APIError.recognitionFailed(speechResponse.msg)
        }

        logger.info("Recognition successful: \(result.recognitionText)")
        return result.recognitionText
    }

    private func sendDirectRequest(path: String, headers: [String: String], body: Data) async throws -> DirectHTTPResponse {
        var lastError: Error?

        for ipAddress in feishuDirectIPs {
            do {
                let client = DirectFeishuHTTPClient(
                    host: feishuAPIHost,
                    ipAddress: ipAddress,
                    path: path,
                    headers: headers,
                    body: body,
                    timeout: requestTimeout
                )
                let response = try await client.send()
                logger.info("Direct Feishu request via \(ipAddress), status: \(response.statusCode)")
                return response
            } catch let error as APIError {
                lastError = error
                logger.warning("Direct Feishu request via \(ipAddress) failed: \(error.localizedDescription)")
            } catch {
                lastError = error
                logger.warning("Direct Feishu request via \(ipAddress) failed: \(error.localizedDescription)")
            }
        }

        // #3: all direct IPs failed — fall back to system DNS via URLSession
        do {
            logger.warning("All direct IPs failed, falling back to URLSession DNS")
            return try await sendViaURLSession(path: path, headers: headers, body: body)
        } catch {
            lastError = error
            logger.warning("URLSession DNS fallback failed: \(error.localizedDescription)")
        }

        if let error = lastError as? APIError {
            throw error
        }

        throw APIError.connectionFailed
    }

    private func sendViaURLSession(path: String, headers: [String: String], body: Data) async throws -> DirectHTTPResponse {
        guard let url = URL(string: "https://\(feishuAPIHost)\(path)") else {
            throw APIError.invalidResponse
        }
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        return DirectHTTPResponse(statusCode: httpResponse.statusCode, body: data)
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

        var isRetriable: Bool {
            switch self {
            case .timeout, .connectionFailed, .networkError:
                return true
            case .httpError(let code):
                return code == 400 || code == 401 || (500...599).contains(code)
            case .networkUnavailable, .authFailed, .recognitionFailed, .invalidResponse, .unknown:
                return false
            }
        }

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
