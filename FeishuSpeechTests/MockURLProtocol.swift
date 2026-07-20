import Foundation

@testable import FeishuSpeech

struct MockFeishuRequest: Sendable {
    let host: String?
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

    func send(request: URLRequest) throws -> DirectHTTPResponse {
        lock.lock()
        requests.append(
            MockFeishuRequest(
                host: request.url?.host,
                path: request.url?.path ?? "",
                headers: request.allHTTPHeaderFields ?? [:],
                body: request.httpBody ?? Data()
            )
        )
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

    func requestHosts() -> [String?] {
        lock.lock()
        let hosts = requests.map(\.host)
        lock.unlock()
        return hosts
    }

    func authorizationHeaders() -> [String] {
        lock.lock()
        let values = requests.compactMap { $0.headers["Authorization"] }
        lock.unlock()
        return values
    }
}
