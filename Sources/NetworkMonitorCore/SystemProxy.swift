import Foundation
import SystemConfiguration

/// An explicitly enabled system proxy on this machine. Credentials are never read.
public struct LocalProxyEndpoint: Hashable {
    public let host: String
    public let port: Int

    public init?(host: String, port: Int) {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard (1...65535).contains(port),
              host == "localhost" || Self.loopbackHost(host) != nil else { return nil }
        self.host = host == "localhost" ? host : Self.loopbackHost(host)!
        self.port = port
    }

    func matches(host: String, port: Int) -> Bool {
        guard self.port == port, let numeric = Self.loopbackHost(host) else { return false }
        return self.host == "localhost" ? ["127.0.0.1", "::1"].contains(numeric) : self.host == numeric
    }

    static func loopbackHost(_ input: String) -> String? {
        let host = input.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .split(separator: "%", maxSplits: 1).first.map(String.init) ?? ""
        let components = host.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = components.compactMap { Int($0) }
        if components.count == 4, numbers.count == 4,
           numbers.allSatisfy({ (0...255).contains($0) }), numbers[0] == 127 {
            return numbers.map(String.init).joined(separator: ".")
        }
        var address = in6_addr()
        guard host.withCString({ inet_pton(AF_INET6, $0, &address) }) == 1 else { return nil }
        return withUnsafeBytes(of: address) { bytes in
            if bytes.prefix(15).allSatisfy({ $0 == 0 }), bytes[15] == 1 { return "::1" }
            if bytes.prefix(10).allSatisfy({ $0 == 0 }), bytes[10] == 255, bytes[11] == 255,
               bytes[12] == 127 {
                return bytes.suffix(4).map(String.init).joined(separator: ".")
            }
            return nil
        }
    }
}

public enum SystemProxyEndpoints {
    public static func current() -> Set<LocalProxyEndpoint> {
        guard let values = SCDynamicStoreCopyProxies(nil) as? [String: Any] else { return [] }
        return endpoints(in: values)
    }

    public static func endpoints(in values: [String: Any]) -> Set<LocalProxyEndpoint> {
        var result: Set<LocalProxyEndpoint> = []
        for name in ["HTTP", "HTTPS", "SOCKS"] {
            guard (values[name + "Enable"] as? NSNumber)?.boolValue == true,
                  let host = values[name + "Proxy"] as? String,
                  let port = values[name + "Port"] as? NSNumber,
                  let endpoint = LocalProxyEndpoint(host: host, port: port.intValue) else { continue }
            result.insert(endpoint)
        }
        return result
    }
}

/// Only one side of a local proxy connection is original-app usage.
public struct LocalProxyConnection {
    public enum Role: Equatable { case none, client, transport }
    public let isLoopback: Bool
    public let role: Role

    public init(label: String, endpoints: Set<LocalProxyEndpoint>) {
        guard let arrow = label.range(of: "<->"),
              let local = Self.socket(String(label[..<arrow.lowerBound])),
              let remote = Self.socket(String(label[arrow.upperBound...])),
              LocalProxyEndpoint.loopbackHost(local.host) != nil,
              LocalProxyEndpoint.loopbackHost(remote.host) != nil else {
            isLoopback = false; role = .none; return
        }
        isLoopback = true
        // Explicit HTTP/HTTPS/SOCKS endpoints describe TCP listeners. A UDP
        // relay can use a different negotiated port; guessing would bill local services.
        guard ["tcp4", "tcp6"].contains(label.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? "") else {
            role = .none; return
        }
        let client = endpoints.contains { $0.matches(host: remote.host, port: remote.port) }
        let server = endpoints.contains { $0.matches(host: local.host, port: local.port) }
        role = client && !server ? .client : server && !client ? .transport : .none
    }

    private static func socket(_ label: String) -> (host: String, port: Int)? {
        guard let value = label.split(whereSeparator: { $0.isWhitespace }).last else { return nil }
        let text = String(value)
        if text.hasPrefix("["), let end = text.firstIndex(of: "]") {
            let tail = text[text.index(after: end)...]
            guard let separator = tail.first, separator == ":" || separator == ".",
                  let port = Int(tail.dropFirst()) else { return nil }
            return (String(text[text.index(after: text.startIndex)..<end]), port)
        }
        // nettop's unbracketed IPv6 sockets use a dot before the port.
        let separator = text.filter { $0 == ":" }.count > 1
            ? text.lastIndex(of: ".") : text.lastIndex(of: ":")
        guard let separator, let port = Int(text[text.index(after: separator)...]) else { return nil }
        return (String(text[..<separator]), port)
    }
}
