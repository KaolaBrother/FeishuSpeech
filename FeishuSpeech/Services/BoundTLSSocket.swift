import CoreFoundation
import Darwin
import Foundation
import SystemConfiguration
import SystemConfiguration.SCDynamicStoreCopyDHCPInfo

import os.log

private nonisolated let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "BoundTLS"
)

/// Physical-path DNS over bound UDP/53. Skips the VPN fake-ip range via bitmask.
nonisolated enum BoundPhysicalDNS {
    private static let dnsPort: UInt16 = 53
    private static let dnsTimeoutSeconds: __darwin_time_t = 0
    private static let dnsTimeoutMicroseconds: __darwin_suseconds_t = 400_000
    private static let dnsTypeA: UInt16 = 1
    private static let dhcpDomainNameServersOption: UInt8 = 6
    private static let maxNameHops = 16

    static func ipv4ARecords(from response: Data) -> [in_addr] {
        guard response.count >= 12 else { return [] }
        let questionCount = intValue(readU16(response, offset: 4))
        let answerCount = intValue(readU16(response, offset: 6))
        let authorityCount = intValue(readU16(response, offset: 8))
        let additionalCount = intValue(readU16(response, offset: 10))
        var offset = 12
        for _ in 0..<questionCount {
            guard skipName(response, offset: &offset), offset + 4 <= response.count else {
                return []
            }
            offset += 4
        }
        var state = RecordParseState(offset: offset)
        let recordCounts = [answerCount, authorityCount, additionalCount]
        for (index, count) in recordCounts.enumerated() {
            collectIPv4ARecords(
                from: response,
                count: count,
                collectA: index != 1,
                state: &state
            )
        }
        return state.addresses
    }

    static func resolveIPv4(host: String, interfaceName: String) throws -> [in_addr] {
        let nameservers = dhcpNameservers(on: interfaceName) + recursiveResolverAddresses()
        for nameserver in nameservers {
            guard let packet = udpQuery(
                host: host,
                nameserver: nameserver,
                interfaceName: interfaceName
            ) else {
                continue
            }
            let records = ipv4ARecords(from: packet)
            if !records.isEmpty {
                logger.notice("transport=direct dns=udp")
                return records
            }
        }
        throw FeishuAPIService.APIError.connectionFailed
    }

    private struct RecordParseState {
        var offset: Int
        var addresses: [in_addr] = []
        var seen: Set<UInt32> = []
    }

    private static func collectIPv4ARecords(
        from data: Data,
        count: Int,
        collectA: Bool,
        state: inout RecordParseState
    ) {
        for _ in 0..<count {
            guard skipName(data, offset: &state.offset), state.offset + 10 <= data.count else { return }
            let type = readU16(data, offset: state.offset)
            let rdlength = intValue(readU16(data, offset: state.offset + 8))
            state.offset += 10
            guard state.offset + rdlength <= data.count else { return }
            if collectA, type == dnsTypeA, rdlength == 4 {
                var addr = in_addr()
                let start = state.offset
                withUnsafeMutableBytes(of: &addr.s_addr) { dest in
                    _ = data.copyBytes(to: dest, from: start..<(start + 4))
                }
                if state.seen.insert(addr.s_addr).inserted, !isTunnelOnlyIPv4(addr) {
                    state.addresses.append(addr)
                }
            }
            state.offset += rdlength
        }
    }

    private static func dhcpNameservers(on interfaceName: String) -> [in_addr] {
        let store = SCDynamicStoreCreate(
            nil,
            "com.feishuspeech.bound-dns" as CFString,
            nil,
            nil
        )
        var collected: [in_addr] = []
        var seen = Set<UInt32>()
        func append(_ addresses: [in_addr]) {
            for addr in addresses where seen.insert(addr.s_addr).inserted {
                collected.append(addr)
            }
        }
        for serviceID in matchingServiceIDs(store: store, interfaceName: interfaceName) {
            append(nameserversFromDHCP(store: store, serviceID: serviceID as CFString))
        }
        if collected.isEmpty {
            append(nameserversFromDHCP(store: store, serviceID: nil))
        }
        return collected
    }

    private static func matchingServiceIDs(
        store: SCDynamicStore?,
        interfaceName: String
    ) -> [String] {
        var ids: [String] = []
        var seen = Set<String>()
        func consider(key: String, deviceName: String?) {
            guard deviceName == interfaceName else { return }
            guard let serviceID = serviceID(fromNetworkKey: key), seen.insert(serviceID).inserted else {
                return
            }
            ids.append(serviceID)
        }
        let interfacePattern = SCDynamicStoreKeyCreateNetworkServiceEntity(
            nil,
            kSCDynamicStoreDomainSetup,
            kSCCompAnyRegex,
            kSCEntNetInterface
        )
        if let keys = SCDynamicStoreCopyKeyList(store, interfacePattern) as? [String] {
            for key in keys {
                let entity = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any]
                let device = entity?[kSCPropNetInterfaceDeviceName as String] as? String
                consider(key: key, deviceName: device)
            }
        }
        let globalKey = SCDynamicStoreKeyCreateNetworkGlobalEntity(
            nil,
            kSCDynamicStoreDomainState,
            kSCEntNetIPv4
        )
        if let global = SCDynamicStoreCopyValue(store, globalKey) as? [String: Any] {
            let primaryInterface = global[kSCDynamicStorePropNetPrimaryInterface as String] as? String
            let primaryService = global[kSCDynamicStorePropNetPrimaryService as String] as? String
            if primaryInterface == interfaceName, let primaryService, seen.insert(primaryService).inserted {
                ids.append(primaryService)
            }
        }
        return ids
    }

    private static func serviceID(fromNetworkKey key: String) -> String? {
        let marker = "/Service/"
        guard let range = key.range(of: marker) else { return nil }
        let rest = key[range.upperBound...]
        if let slash = rest.firstIndex(of: "/") {
            return String(rest[..<slash])
        }
        return String(rest)
    }

    private static func nameserversFromDHCP(
        store: SCDynamicStore?,
        serviceID: CFString?
    ) -> [in_addr] {
        guard let info = SCDynamicStoreCopyDHCPInfo(store, serviceID),
              let option = DHCPInfoGetOptionData(info, dhcpDomainNameServersOption) else {
            return []
        }
        return ipv4Addresses(fromOption: option as Data)
    }

    private static func ipv4Addresses(fromOption data: Data) -> [in_addr] {
        var addresses: [in_addr] = []
        var offset = 0
        while offset + 4 <= data.count {
            var addr = in_addr()
            withUnsafeMutableBytes(of: &addr.s_addr) { dest in
                _ = data.copyBytes(to: dest, from: offset..<(offset + 4))
            }
            if !isTunnelOnlyIPv4(addr) {
                addresses.append(addr)
            }
            offset += 4
        }
        return addresses
    }

    private static func udpQuery(
        host: String,
        nameserver: in_addr,
        interfaceName: String
    ) -> Data? {
        let index = if_nametoindex(interfaceName)
        guard index != 0 else { return nil }
        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }
        var ifindex = index
        guard setsockopt(
            fd,
            IPPROTO_IP,
            IP_BOUND_IF,
            &ifindex,
            socklen_t(MemoryLayout<UInt32>.size)
        ) == 0 else {
            return nil
        }
        var timeout = timeval(tv_sec: dnsTimeoutSeconds, tv_usec: dnsTimeoutMicroseconds)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        let transactionID = UInt16.random(in: 1...UInt16.max)
        let query = makeQuery(host: host, transactionID: transactionID)
        var dest = sockaddr_in()
        dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = dnsPort.bigEndian
        dest.sin_addr = nameserver
        let sent = query.withUnsafeBytes { raw -> ssize_t in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            return withUnsafePointer(to: &dest) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    sendto(fd, base, query.count, 0, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == query.count else { return nil }
        var buffer = [UInt8](repeating: 0, count: 4096)
        let received = recvfrom(fd, &buffer, buffer.count, 0, nil, nil)
        guard received > 0 else { return nil }
        let packet = Data(buffer.prefix(Int(received)))
        guard packet.count >= 12, readU16(packet, offset: 0) == transactionID else {
            return nil
        }
        return packet
    }

    private static func makeQuery(host: String, transactionID: UInt16) -> Data {
        var data = Data()
        data.append(contentsOf: u16Bytes(transactionID))
        data.append(contentsOf: u16Bytes(0x0100))
        data.append(contentsOf: u16Bytes(1))
        data.append(contentsOf: u16Bytes(0))
        data.append(contentsOf: u16Bytes(0))
        data.append(contentsOf: u16Bytes(0))
        data.append(encodeName(host))
        data.append(contentsOf: u16Bytes(dnsTypeA))
        data.append(contentsOf: u16Bytes(1))
        return data
    }

    private static func encodeName(_ name: String) -> Data {
        var data = Data()
        for label in name.split(separator: ".") {
            let bytes = Array(label.utf8)
            guard bytes.count < 64 else { continue }
            data.append(UInt8(bytes.count))
            data.append(contentsOf: bytes)
        }
        data.append(0)
        return data
    }

    /// Recursor *hostnames* (not IP literals). LAN DHCP DNS is often blocked by
    /// Local Network TCC; these names resolve to public recursors on the physical path.
    private static func recursiveResolverAddresses() -> [in_addr] {
        var collected: [in_addr] = []
        var seen = Set<UInt32>()
        for host in ["dns.alidns.com", "public1.114dns.com"] {
            for addr in systemIPv4(host: host) where seen.insert(addr.s_addr).inserted {
                collected.append(addr)
            }
        }
        return collected
    }

    private static func systemIPv4(host: String) -> [in_addr] {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_INET,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, "443", &hints, &result) == 0, let head = result else {
            return []
        }
        defer { freeaddrinfo(head) }
        var addresses: [in_addr] = []
        var seen = Set<UInt32>()
        var cursor: UnsafeMutablePointer<addrinfo>? = head
        while let info = cursor?.pointee {
            if info.ai_family == AF_INET, let addrPtr = info.ai_addr {
                let ipv4 = addrPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    $0.pointee.sin_addr
                }
                if seen.insert(ipv4.s_addr).inserted, !isTunnelOnlyIPv4(ipv4) {
                    addresses.append(ipv4)
                }
            }
            cursor = info.ai_next
        }
        return addresses
    }

    private static func isTunnelOnlyIPv4(_ addr: in_addr) -> Bool {
        let ip = UInt32(bigEndian: addr.s_addr)
        return (ip & 0xFFFE_0000) == 0xC612_0000
    }

    private static func skipName(_ data: Data, offset: inout Int) -> Bool {
        var jumped = false
        var cursor = offset
        var hops = 0
        while cursor < data.count {
            let length = data[cursor]
            if length == 0 {
                cursor += 1
                if !jumped {
                    offset = cursor
                }
                return true
            }
            if (length & 0xC0) == 0xC0 {
                guard cursor + 1 < data.count else { return false }
                hops += 1
                if hops > maxNameHops { return false }
                if !jumped {
                    offset = cursor + 2
                    jumped = true
                }
                cursor = (Int(length & 0x3F) << 8) | Int(data[cursor + 1])
                continue
            }
            if (length & 0xC0) != 0 { return false }
            cursor += 1 + Int(length)
            if cursor > data.count { return false }
        }
        return false
    }

    private static func readU16(_ data: Data, offset: Int) -> UInt16 {
        UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }

    private static func u16Bytes(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0xFF)]
    }

    private static func intValue(_ value: UInt16) -> Int {
        Int(value)
    }
}

/// POSIX TCP bound with `IP_BOUND_IF`, then CFStream TLS.
/// Network.framework `requiredInterface` still hairpins through Astrill utun.
nonisolated final class BoundTLSSocket: @unchecked Sendable {
    private let readStream: CFReadStream
    private let writeStream: CFWriteStream
    private let fd: Int32
    private let lock = NSLock()
    private var closed = false

    private init(readStream: CFReadStream, writeStream: CFWriteStream, fd: Int32) {
        self.readStream = readStream
        self.writeStream = writeStream
        self.fd = fd
    }

    deinit {
        close()
    }

    static func connect(
        host: String,
        interfaceName: String,
        port: UInt16 = 443,
        timeoutSeconds: Int32 = 5
    ) throws -> BoundTLSSocket {
        let fd = try posixConnect(
            host: host,
            interfaceName: interfaceName,
            port: port,
            timeoutSeconds: timeoutSeconds
        )
        var readUnmanaged: Unmanaged<CFReadStream>?
        var writeUnmanaged: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocket(nil, fd, &readUnmanaged, &writeUnmanaged)
        guard let readStream = readUnmanaged?.takeRetainedValue(),
              let writeStream = writeUnmanaged?.takeRetainedValue() else {
            Darwin.close(fd)
            throw FeishuAPIService.APIError.connectionFailed
        }
        CFReadStreamSetProperty(
            readStream,
            CFStreamPropertyKey(rawValue: kCFStreamPropertyShouldCloseNativeSocket),
            kCFBooleanTrue
        )
        let sslSettings: [CFString: Any] = [
            kCFStreamSSLLevel: kCFStreamSocketSecurityLevelNegotiatedSSL as Any,
            kCFStreamSSLPeerName: host as CFString,
            kCFStreamSSLValidatesCertificateChain: kCFBooleanTrue as Any
        ]
        let sslDict = sslSettings as CFDictionary
        CFReadStreamSetProperty(
            readStream,
            CFStreamPropertyKey(rawValue: kCFStreamPropertySSLSettings),
            sslDict
        )
        CFWriteStreamSetProperty(
            writeStream,
            CFStreamPropertyKey(rawValue: kCFStreamPropertySSLSettings),
            sslDict
        )
        guard CFReadStreamOpen(readStream), CFWriteStreamOpen(writeStream) else {
            Darwin.close(fd)
            throw FeishuAPIService.APIError.connectionFailed
        }
        try waitUntilOpen(readStream, writeStream, timeoutSeconds: timeoutSeconds)
        logger.notice("transport=direct bound-if")
        return BoundTLSSocket(readStream: readStream, writeStream: writeStream, fd: fd)
    }

    func write(_ data: Data) throws {
        try data.withUnsafeBytes { raw in
            var sent = 0
            let total = raw.count
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else {
                throw FeishuAPIService.APIError.connectionFailed
            }
            while sent < total {
                let written = CFWriteStreamWrite(writeStream, base + sent, total - sent)
                if written <= 0 {
                    throw FeishuAPIService.APIError.connectionFailed
                }
                sent += written
            }
        }
    }

    func read(maxLength: Int) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: maxLength)
        let readCount = CFReadStreamRead(readStream, &buffer, maxLength)
        if readCount == 0 {
            return Data()
        }
        guard readCount > 0 else {
            throw FeishuAPIService.APIError.connectionFailed
        }
        return Data(buffer.prefix(readCount))
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        CFReadStreamClose(readStream)
        CFWriteStreamClose(writeStream)
    }

    var localIPv4: String? {
        var addr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let rc = withUnsafeMutablePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                getsockname(fd, sockPtr, &len)
            }
        }
        guard rc == 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &addr.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
            return nil
        }
        return String(cString: buffer)
    }

    private static func posixConnect(
        host: String,
        interfaceName: String,
        port: UInt16,
        timeoutSeconds: Int32
    ) throws -> Int32 {
        let index = if_nametoindex(interfaceName)
        guard index != 0 else {
            throw FeishuAPIService.APIError.connectionFailed
        }
        let addresses = try BoundPhysicalDNS.resolveIPv4(host: host, interfaceName: interfaceName)
        guard !addresses.isEmpty else {
            throw FeishuAPIService.APIError.connectionFailed
        }
        var lastError: Error = FeishuAPIService.APIError.connectionFailed
        for address in addresses {
            do {
                return try connectBound(
                    address: address,
                    interfaceIndex: index,
                    port: port,
                    timeoutSeconds: timeoutSeconds
                )
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private static func connectBound(
        address: in_addr,
        interfaceIndex: UInt32,
        port: UInt16,
        timeoutSeconds: Int32
    ) throws -> Int32 {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else {
            throw FeishuAPIService.APIError.connectionFailed
        }
        var yes: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
        var ifindex = interfaceIndex
        guard setsockopt(
            fd,
            IPPROTO_IP,
            IP_BOUND_IF,
            &ifindex,
            socklen_t(MemoryLayout<UInt32>.size)
        ) == 0 else {
            Darwin.close(fd)
            throw FeishuAPIService.APIError.connectionFailed
        }
        var timeout = timeval(tv_sec: __darwin_time_t(timeoutSeconds), tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        do {
            try connectBlocking(fd: fd, address: address, port: port, timeoutSeconds: timeoutSeconds)
        } catch {
            Darwin.close(fd)
            throw error
        }
        return fd
    }

    private static func waitUntilOpen(
        _ readStream: CFReadStream,
        _ writeStream: CFWriteStream,
        timeoutSeconds: Int32
    ) throws {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            let readStatus = CFReadStreamGetStatus(readStream)
            let writeStatus = CFWriteStreamGetStatus(writeStream)
            if readStatus == .error || writeStatus == .error {
                throw FeishuAPIService.APIError.connectionFailed
            }
            if readStatus == .open && writeStatus == .open {
                return
            }
            usleep(20_000)
        }
        throw FeishuAPIService.APIError.timeout
    }

    private static func connectBlocking(
        fd: Int32,
        address: in_addr,
        port: UInt16,
        timeoutSeconds: Int32
    ) throws {
        let original = fcntl(fd, F_GETFL, 0)
        guard original >= 0 else {
            throw FeishuAPIService.APIError.connectionFailed
        }
        _ = fcntl(fd, F_SETFL, original | O_NONBLOCK)
        var sin = sockaddr_in()
        sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sin.sin_family = sa_family_t(AF_INET)
        sin.sin_port = port.bigEndian
        sin.sin_addr = address
        let rc: Int32 = withUnsafePointer(to: &sin) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if rc != 0 && errno != EINPROGRESS {
            _ = fcntl(fd, F_SETFL, original)
            throw FeishuAPIService.APIError.connectionFailed
        }
        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let pollRC = poll(&pfd, 1, timeoutSeconds * 1000)
        var soError: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &len)
        _ = fcntl(fd, F_SETFL, original)
        guard pollRC > 0, soError == 0 else {
            throw FeishuAPIService.APIError.connectionFailed
        }
    }
}
