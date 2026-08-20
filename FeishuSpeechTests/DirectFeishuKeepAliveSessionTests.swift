import Foundation
import Network
import XCTest
import os.log

@testable import FeishuSpeech

private let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "DirectFeishuKeepAliveSessionTests"
)

final class DirectFeishuKeepAliveSessionTests: XCTestCase {
    func test_parametersUsePreferNoProxiesAndFeishuSNIHost() {
        logger.info("DirectFeishuKeepAliveSessionTests starting")
        let parameters = DirectFeishuKeepAliveSession.makeParameters()
        XCTAssertTrue(parameters.preferNoProxies)

        let production = try? String(contentsOfFile: keepAliveSourcePath, encoding: .utf8)
        XCTAssertNotNil(production)
        XCTAssertTrue(production?.contains("open.feishu.cn") == true)
        XCTAssertFalse(production?.contains("sec_protocol_options_set_verify_block") == true)
    }

    func test_mapTransportErrorNeverExposesNWErrorToCoordinator() {
        let posix = NWError.posix(.ETIMEDOUT)
        let mapped = mapTransportError(posix)
        XCTAssertTrue(mapped is FeishuAPIService.APIError)
        if let apiError = mapped as? FeishuAPIService.APIError {
            switch apiError {
            case .timeout, .connectionFailed, .networkError:
                break
            default:
                XCTFail("NWError must map to a recoverable connect-class APIError")
            }
        }
    }

    private var keepAliveSourcePath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift")
            .path
    }
}
