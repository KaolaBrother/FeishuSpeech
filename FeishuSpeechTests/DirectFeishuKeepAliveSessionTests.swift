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
    func test_parametersPreferNoProxiesAndProhibitOtherInterfaceTypes() {
        logger.info("DirectFeishuKeepAliveSessionTests starting")
        let parameters = DirectFeishuKeepAliveSession.makeParameters()
        XCTAssertTrue(parameters.preferNoProxies)
        XCTAssertEqual(
            parameters.prohibitedInterfaceTypes?.contains(.other),
            true,
            "keep-alive must skip VPN/TUN by prohibiting InterfaceType.other"
        )
        XCTAssertNil(parameters.requiredInterface)
    }

    func test_makeParametersBindsProvidedPhysicalInterface() {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "DirectFeishuKeepAliveSessionTests.path")
        let lock = NSLock()
        var physical: NWInterface?
        let arrived = expectation(description: "path")
        monitor.pathUpdateHandler = { path in
            lock.lock()
            physical = DirectFeishuKeepAliveSession.physicalInterface(from: path)
            lock.unlock()
            arrived.fulfill()
        }
        monitor.start(queue: queue)
        wait(for: [arrived], timeout: 2)
        monitor.cancel()
        lock.lock()
        let interface = physical
        lock.unlock()
        guard let interface, interface.type == .wifi || interface.type == .wiredEthernet else {
            XCTFail("test host must expose wifi or wired ethernet for bind probe")
            return
        }
        let parameters = DirectFeishuKeepAliveSession.makeParameters(requiredInterface: interface)
        XCTAssertEqual(parameters.requiredInterface?.type, interface.type)
        XCTAssertTrue(parameters.preferNoProxies)
        XCTAssertEqual(parameters.prohibitedInterfaceTypes?.contains(.other), true)
    }

    func test_productionSourcePinsOpenFeishuHostWithoutEn0OrCustomVerifyBlock() {
        let production = try? String(contentsOfFile: keepAliveSourcePath, encoding: .utf8)
        XCTAssertNotNil(production)
        XCTAssertTrue(production?.contains("open.feishu.cn") == true)
        XCTAssertTrue(production?.contains("requiredInterface") == true)
        XCTAssertTrue(production?.contains(".wifi") == true)
        XCTAssertTrue(production?.contains(".wiredEthernet") == true)
        XCTAssertTrue(production?.contains("BoundTLSSocket") == true)
        XCTAssertFalse(production?.contains("en0") == true)
        XCTAssertFalse(production?.contains("sec_protocol_options_set_verify_block") == true)
        XCTAssertFalse(production?.contains("98.96.213.145") == true)
        XCTAssertFalse(production?.contains("98.96.242.53") == true)
    }

    func test_productionSourcePinsBoundUDPPhysicalDNSWithoutEn0CDNOrCustomVerify() {
        let keepAlive = try? String(contentsOfFile: keepAliveSourcePath, encoding: .utf8)
        let boundTLS = try? String(contentsOfFile: boundTLSSourcePath, encoding: .utf8)
        XCTAssertNotNil(keepAlive)
        XCTAssertNotNil(boundTLS)
        XCTAssertTrue(keepAlive?.contains("open.feishu.cn") == true)
        XCTAssertTrue(boundTLS?.contains("IP_BOUND_IF") == true)
        XCTAssertTrue(
            boundTLS?.contains("SOCK_DGRAM") == true,
            "BoundTLS DNS must use bound UDP, not getaddrinfo-only"
        )
        XCTAssertTrue(
            boundTLS?.contains("IPPROTO_UDP") == true || boundTLS?.contains("SOCK_DGRAM") == true,
            "BoundTLS DNS must be UDP"
        )
        XCTAssertTrue(
            hasDNSPort53(boundTLS ?? ""),
            "BoundTLS DNS must target UDP port 53"
        )
        XCTAssertTrue(boundTLS?.contains("0xC612_0000") == true)
        XCTAssertTrue(boundTLS?.contains("0xFFFE_0000") == true)
        XCTAssertFalse(keepAlive?.contains("en0") == true)
        XCTAssertFalse(boundTLS?.contains("en0") == true)
        XCTAssertFalse(keepAlive?.contains("sec_protocol_options_set_verify_block") == true)
        XCTAssertFalse(boundTLS?.contains("sec_protocol_options_set_verify_block") == true)
        XCTAssertFalse(keepAlive?.contains("98.96.213.145") == true)
        XCTAssertFalse(keepAlive?.contains("98.96.242.53") == true)
        XCTAssertFalse(boundTLS?.contains("98.96.213.145") == true)
        XCTAssertFalse(boundTLS?.contains("98.96.242.53") == true)
    }

    func test_liveKeepAliveTCPIsNotOnVPNTunnelAddress() async throws {
        throw XCTSkip(
            "live TCP previously hung the XCTest host; issue #34 forbids additional live sockets"
        )
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

    private func hasDNSPort53(_ source: String) -> Bool {
        source.range(of: #"\b53\b"#, options: .regularExpression) != nil
            && (source.contains("SOCK_DGRAM") || source.contains("IPPROTO_UDP"))
    }

    private var keepAliveSourcePath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift")
            .path
    }

    private var boundTLSSourcePath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("FeishuSpeech/Services/BoundTLSSocket.swift")
            .path
    }
}
