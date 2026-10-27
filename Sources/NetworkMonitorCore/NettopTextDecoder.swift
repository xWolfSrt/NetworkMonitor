import Foundation

/// Decode complete CSV lines rather than individual PTY reads. A read can split
/// a valid multibyte name; nettop can also truncate a process name in the middle
/// of a scalar. Repair that name without discarding other apps in the same read.
public struct NettopTextDecoder {
    private var pending = Data()
    public init() {}
    public var hasPartialLine: Bool { !pending.isEmpty }

    public mutating func consume(_ bytes: Data) -> String {
        pending.append(bytes)
        guard let newline = pending.lastIndex(of: 0x0A) else { return "" }
        let end = pending.index(after: newline)
        let complete = pending[pending.startIndex..<end].filter { $0 != 0x0D }
        let result = String(decoding: complete, as: UTF8.self)
        pending.removeSubrange(pending.startIndex..<end)
        return result
    }

    public mutating func reset() { pending.removeAll(keepingCapacity: true) }
}
