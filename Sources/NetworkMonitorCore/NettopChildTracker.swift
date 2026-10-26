import Foundation

/// Kernel identity, rather than a command-line description or a PID alone.
public struct NettopChildSnapshot: Codable, Equatable {
    public var pid: Int32
    public var parentPID: Int32
    public var uid: UInt32
    public var startSeconds: UInt64
    public var startMicroseconds: UInt64
    public var executablePath: String

    public init(pid: Int32, parentPID: Int32, uid: UInt32,
                startSeconds: UInt64, startMicroseconds: UInt64, executablePath: String) {
        self.pid = pid
        self.parentPID = parentPID
        self.uid = uid
        self.startSeconds = startSeconds
        self.startMicroseconds = startMicroseconds
        self.executablePath = executablePath
    }

    public static func read(pid: Int32) -> NettopChildSnapshot? {
        guard pid > 1 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              let path = AppIdentityResolver.executablePath(pid: pid) else { return nil }
        return NettopChildSnapshot(pid: pid, parentPID: Int32(bitPattern: info.pbi_ppid),
                                   uid: info.pbi_uid, startSeconds: info.pbi_start_tvsec,
                                   startMicroseconds: info.pbi_start_tvusec, executablePath: path)
    }
}

/// Records only the child we spawned. It never enumerates or matches other processes.
public final class NettopChildTracker {
    private let recordURL: URL?
    private let currentUID: UInt32
    private let lookup: (Int32) -> NettopChildSnapshot?
    private let signal: (Int32) -> Bool

    /// Bare test/CLI executables must not share the installed app's child record.
    public static var defaultRecordURL: URL? {
        guard Bundle.main.bundleIdentifier == "com.kevinabouhanna.NetworkMonitor" else { return nil }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("NetworkMonitor/nettop-child.json")
    }

    public init(recordURL: URL? = NettopChildTracker.defaultRecordURL,
                currentUID: UInt32 = getuid(),
                lookup: @escaping (Int32) -> NettopChildSnapshot? = NettopChildSnapshot.read,
                signal: @escaping (Int32) -> Bool = { kill($0, SIGKILL) == 0 }) {
        self.recordURL = recordURL
        self.currentUID = currentUID
        self.lookup = lookup
        self.signal = signal
    }

    public func rememberChild(pid: Int32) {
        guard let recordURL, let snapshot = lookup(pid), snapshot.pid == pid,
              snapshot.parentPID == getpid(), snapshot.uid == currentUID,
              snapshot.executablePath == "/usr/bin/nettop" else { return }
        do {
            try FileManager.default.createDirectory(at: recordURL.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: recordURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                   ofItemAtPath: recordURL.path)
        } catch {
            // Losing recovery is safer than guessing which process might be ours.
            try? FileManager.default.removeItem(at: recordURL)
        }
    }

    @discardableResult
    public func reapRecordedOrphan() -> Bool {
        defer { clearRecord() }
        guard let recorded = load(), recorded.pid > 1,
              recorded.uid == currentUID, recorded.executablePath == "/usr/bin/nettop",
              let current = lookup(recorded.pid), current.pid == recorded.pid,
              current.parentPID == 1, current.uid == recorded.uid,
              current.executablePath == recorded.executablePath,
              current.startSeconds == recorded.startSeconds,
              current.startMicroseconds == recorded.startMicroseconds else { return false }
        return signal(current.pid)
    }

    public func forgetChild(pid: Int32) {
        guard load()?.pid == pid else { return }
        clearRecord()
    }

    private func load() -> NettopChildSnapshot? {
        guard let recordURL, let data = try? Data(contentsOf: recordURL) else { return nil }
        return try? JSONDecoder().decode(NettopChildSnapshot.self, from: data)
    }

    private func clearRecord() {
        if let recordURL { try? FileManager.default.removeItem(at: recordURL) }
    }
}
