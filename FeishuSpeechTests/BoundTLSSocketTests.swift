import Foundation
import Darwin
import XCTest
import os.log

@testable import FeishuSpeech

private let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "BoundTLSSocketTests"
)

final class BoundTLSSocketTests: XCTestCase {
    func test_productionSourcePinsBoundUDPPhysicalDNSWithoutEn0CDNOrCustomVerify() {
        logger.info("BoundTLSSocketTests starting")
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

    func test_dnsResponseFixture_dropsTunnelRangeAndKeepsNonTunnelARecords() {
        // Expected production seam (internal, @testable):
        // nonisolated enum BoundPhysicalDNS {
        //     static func ipv4ARecords(from response: Data) -> [in_addr]
        // }
        // Parse DNS A RDATA; drop 198.18.0.0/15; no CDN allowlist.
        let fixture = DNSResponseFixture.aRecords([
            "198.18.1.23",
            "203.0.113.50",
            "198.19.255.255",
            "198.17.255.255"
        ])
        let addresses = BoundPhysicalDNS.ipv4ARecords(from: fixture).map(Self.dottedIPv4)
        XCTAssertEqual(Set(addresses), Set(["203.0.113.50", "198.17.255.255"]))
        XCTAssertFalse(addresses.contains("198.18.1.23"))
        XCTAssertFalse(addresses.contains("198.19.255.255"))
    }

    func test_dnsResponseFixture_allTunnelARecordsYieldEmptyList() {
        let fixture = DNSResponseFixture.aRecords([
            "198.18.0.0",
            "198.18.1.23",
            "198.19.255.255"
        ])
        let addresses = BoundPhysicalDNS.ipv4ARecords(from: fixture)
        XCTAssertTrue(addresses.isEmpty, "198.18.0.0/15 A records must be dropped")
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

    private static func dottedIPv4(_ addr: in_addr) -> String {
        var addr = addr
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
            return ""
        }
        return String(cString: buffer)
    }
}

private enum DNSResponseFixture {
    static func aRecords(_ addresses: [String], name: String = "open.feishu.cn") -> Data {
        var data = Data()
        data.append(contentsOf: u16(0x1234))
        data.append(contentsOf: u16(0x8180))
        data.append(contentsOf: u16(1))
        data.append(contentsOf: u16(UInt16(addresses.count)))
        data.append(contentsOf: u16(0))
        data.append(contentsOf: u16(0))
        data.append(encodeName(name))
        data.append(contentsOf: u16(1))
        data.append(contentsOf: u16(1))
        for address in addresses {
            data.append(contentsOf: u16(0xC00C))
            data.append(contentsOf: u16(1))
            data.append(contentsOf: u16(1))
            data.append(contentsOf: u32(60))
            data.append(contentsOf: u16(4))
            data.append(ipv4(address))
        }
        return data
    }

    private static func encodeName(_ name: String) -> Data {
        var data = Data()
        for label in name.split(separator: ".") {
            let bytes = Array(label.utf8)
            data.append(UInt8(bytes.count))
            data.append(contentsOf: bytes)
        }
        data.append(0)
        return data
    }

    private static func ipv4(_ dotted: String) -> Data {
        var addr = in_addr()
        let converted = dotted.withCString { inet_pton(AF_INET, $0, &addr) }
        precondition(converted == 1)
        var network = addr.s_addr
        return withUnsafeBytes(of: &network) { Data($0) }
    }

    private static func u16(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0xFF)]
    }

    private static func u32(_ value: UInt32) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
    }
}
