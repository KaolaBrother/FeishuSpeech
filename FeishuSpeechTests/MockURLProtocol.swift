import XCTest
import Combine
@testable import FeishuSpeech

final class MockURLProtocol: URLProtocol {
    
    static var mockResponses: [String: MockResponse] = [:]
    static var defaultResponse: MockResponse?
    
    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        guard let url = request.url?.absoluteString else {
            client?.urlProtocol(self, didFailWithError: MockError.invalidURL)
            return
        }
        
        let mockResponse = Self.mockResponses[url] ?? Self.defaultResponse
        
        guard let response = mockResponse else {
            client?.urlProtocol(self, didFailWithError: MockError.noMockFound)
            return
        }
        
        if let error = response.error {
            client?.urlProtocol(self, didFailWithError: error)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        
        if let httpResponse = HTTPURLResponse(
            url: request.url!,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        ) {
            client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        }
        
        if let data = response.data {
            client?.urlProtocol(self, didLoad: data)
        }
        
        client?.urlProtocolDidFinishLoading(self)
    }
    
    override func stopLoading() {}
}

struct MockResponse {
    let statusCode: Int
    let data: Data?
    let headers: [String: String]
    let error: Error?
    
    init(
        statusCode: Int = 200,
        data: Data? = nil,
        headers: [String: String] = ["Content-Type": "application/json"],
        error: Error? = nil
    ) {
        self.statusCode = statusCode
        self.data = data
        self.headers = headers
        self.error = error
    }
    
    static func json(_ json: Any, statusCode: Int = 200) -> MockResponse {
        let data = try? JSONSerialization.data(withJSONObject: json)
        return MockResponse(statusCode: statusCode, data: data)
    }
}

enum MockError: Error {
    case invalidURL
    case noMockFound
}
