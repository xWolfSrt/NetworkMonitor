import Foundation

/// A runtime's entry point, never a substring search through arbitrary arguments.
/// Only the classification and local listen endpoint survive the argv lookup.
public struct RuntimeTool: Equatable {
    public static let headroomKey = "runtime:headroom"
    public let proxyEndpoints: Set<LocalProxyEndpoint>
    public var identity: AppIdentity {
        AppIdentity(key: Self.headroomKey, displayName: "Headroom", bundlePath: nil, isSystem: false)
    }

    public static func recognize(executablePath: String, arguments: [String]) -> RuntimeTool? {
        let name = (executablePath as NSString).lastPathComponent.lowercased()
        let python = name.range(of: #"^python(?:[0-9]+(?:\.[0-9]+)*)?$"#, options: .regularExpression) != nil
        guard !arguments.isEmpty, python || name == "headroom" else { return nil }
        var index = 1
        if python {
            // Interpreter options only. `-c "... headroom ..."` is not Headroom.
            while index < arguments.count, ["-u", "-B", "-E", "-I", "-s", "-S", "-O", "-OO", "-q"].contains(arguments[index]) { index += 1 }
            guard index < arguments.count else { return nil }
            if arguments[index] == "-m" {
                guard index + 1 < arguments.count,
                      ["headroom", "headroom.cli", "headroom.__main__"].contains(arguments[index + 1]) else { return nil }
                index += 2
            } else if (arguments[index] as NSString).lastPathComponent == "headroom" {
                index += 1
            } else if (arguments[0] as NSString).lastPathComponent == "headroom" {
                // A console-script launcher can retain its script as argv[0].
            } else { return nil }
        }
        var endpoints: Set<LocalProxyEndpoint> = []
        if index < arguments.count, arguments[index] == "proxy" {
            var host: String?, port: Int?
            index += 1
            while index < arguments.count {
                let arg = arguments[index]
                if arg == "--host", index + 1 < arguments.count { index += 1; host = arguments[index] }
                else if arg.hasPrefix("--host=") { host = String(arg.dropFirst(7)) }
                else if arg == "--port", index + 1 < arguments.count { index += 1; port = Int(arguments[index]) }
                else if arg.hasPrefix("--port=") { port = Int(arg.dropFirst(7)) }
                index += 1
            }
            // Never guess a default port, bind address, PAC endpoint or remote listener.
            if let host, let port, let endpoint = LocalProxyEndpoint(host: host, port: port) { endpoints.insert(endpoint) }
        }
        return RuntimeTool(proxyEndpoints: endpoints)
    }

    /// Decode just argc argv entries, stopping before environment variables.
    public static func decodeArguments(_ data: Data) -> [String]? {
        let bytes = [UInt8](data)
        guard bytes.count > 4 else { return nil }
        let count = bytes.prefix(4).enumerated().reduce(UInt32(0)) { $0 | (UInt32($1.element) << ($1.offset * 8)) }
        guard count > 0, count <= 4096 else { return nil }
        var index = 4
        while index < bytes.count, bytes[index] != 0 { index += 1 } // kernel executable path
        while index < bytes.count, bytes[index] == 0 { index += 1 } // alignment padding
        var result: [String] = []
        for _ in 0..<count {
            guard index < bytes.count, let end = bytes[index...].firstIndex(of: 0),
                  let value = String(bytes: bytes[index..<end], encoding: .utf8) else { return nil }
            result.append(value); index = end + 1
        }
        return result
    }
}

/// Queue-confined cache. PID, UID, executable and kernel start time are rechecked;
/// raw arguments and environment are neither cached, logged nor persisted.
final class RuntimeToolLookup {
    private struct Entry { let snapshot: NettopChildSnapshot; let tool: RuntimeTool? }
    private var cache: [Int32: Entry] = [:]

    func tool(pid: Int32, processName: String) -> RuntimeTool? {
        let lower = processName.lowercased()
        guard lower.contains("python") || lower.hasPrefix("headroom"),
              let snapshot = NettopChildSnapshot.read(pid: pid), snapshot.uid == getuid() else { return nil }
        if let previous = cache[pid], previous.snapshot == snapshot { return previous.tool }
        var mib = [CTL_KERN, KERN_ARGMAX], maximum: Int32 = 0
        var length = MemoryLayout<Int32>.size
        guard sysctl(&mib, 2, &maximum, &length, nil, 0) == 0, maximum > 0, maximum <= 1_048_576 else { return nil }
        var buffer = [UInt8](repeating: 0, count: Int(maximum))
        length = buffer.count
        mib = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, 3, &buffer, &length, nil, 0) == 0,
              let arguments = RuntimeTool.decodeArguments(Data(buffer.prefix(length))) else { return nil }
        let tool = RuntimeTool.recognize(executablePath: snapshot.executablePath, arguments: arguments)
        if cache.count >= 512 { cache.removeAll(keepingCapacity: true) }
        cache[pid] = Entry(snapshot: snapshot, tool: tool)
        return tool
    }
}
