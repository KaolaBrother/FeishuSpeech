import Foundation

@testable import FeishuSpeech

struct MockFeishuRequest: Sendable {
    let path: String
    let headers: [String: String]
    let body: Data
}

final class MockFeishuRequestSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<DirectHTTPResponse, Error>]
    private(set) var requests: [MockFeishuRequest] = []

    init(_ results: [Result<DirectHTTPResponse, Error>]) {
        self.results = results
    }

    func send(path: String, headers: [String: String], body: Data) throws -> DirectHTTPResponse {
        lock.lock()
        requests.append(MockFeishuRequest(path: path, headers: headers, body: body))
        let result = results.isEmpty ? nil : results.removeFirst()
        lock.unlock()

        guard let result else {
            throw FeishuAPIService.APIError.connectionFailed
        }

        return try result.get()
    }

    func requestPaths() -> [String] {
        lock.lock()
        let paths = requests.map(\.path)
        lock.unlock()
        return paths
    }

    func authorizationHeaders() -> [String] {
        lock.lock()
        let values = requests.compactMap { $0.headers["Authorization"] }
        lock.unlock()
        return values
    }
}
