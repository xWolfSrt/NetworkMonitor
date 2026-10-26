import Foundation
import NetworkMonitorCore

func runNettopChildTrackerTests() {
    let owned = NettopChildSnapshot(pid: 4242, parentPID: getpid(), uid: getuid(),
                                   startSeconds: 12345, startMicroseconds: 678,
                                   executablePath: "/usr/bin/nettop")
    var orphan = owned
    orphan.parentPID = 1

    func reap(recorded: NettopChildSnapshot?, current: NettopChildSnapshot?) -> [Int32] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nettop-identity-test-" + UUID().uuidString)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("child.json")
        if let recorded { try! JSONEncoder().encode(recorded).write(to: url) }
        var signals: [Int32] = []
        let tracker = NettopChildTracker(recordURL: url,
                                        lookup: { _ in current },
                                        signal: { signals.append($0); return true })
        tracker.reapRecordedOrphan()
        Check.expectFalse(FileManager.default.fileExists(atPath: url.path))
        return signals
    }

    Check.suite("Nettop child ownership") {
        Check.test("only a recorded orphan with the same kernel identity is signalled") {
            Check.expectEqual(reap(recorded: owned, current: orphan), [owned.pid])
        }
        Check.test("unrecorded processes are left alone even when they are nettop orphans") {
            Check.expectEqual(reap(recorded: nil, current: orphan), [])
        }
        Check.test("a reused PID is left alone") {
            var reused = orphan
            reused.startSeconds += 1
            Check.expectEqual(reap(recorded: owned, current: reused), [])
            reused = orphan
            reused.startMicroseconds += 1
            Check.expectEqual(reap(recorded: owned, current: reused), [])
        }
        Check.test("a command description cannot substitute for the nettop executable") {
            var unrelated = orphan
            unrelated.executablePath = "/usr/bin/python3"
            Check.expectEqual(reap(recorded: owned, current: unrelated), [])
            Check.expectEqual(reap(recorded: unrelated, current: unrelated), [])
        }
        Check.test("another user's process and a live parent's child are left alone") {
            var other = orphan
            other.uid = owned.uid + 1
            Check.expectEqual(reap(recorded: owned, current: other), [])
            Check.expectEqual(reap(recorded: other, current: other), [])
            Check.expectEqual(reap(recorded: owned, current: owned), [])
        }
        Check.test("a missing process and a mismatched PID are left alone") {
            Check.expectEqual(reap(recorded: owned, current: nil), [])
            var other = orphan
            other.pid += 1
            Check.expectEqual(reap(recorded: owned, current: other), [])
        }
        Check.test("only our live child is recorded and a normal stop clears it") {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("nettop-record-test-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("child.json")
            let tracker = NettopChildTracker(recordURL: url, lookup: { _ in owned },
                                            signal: { _ in false })
            tracker.rememberChild(pid: owned.pid)
            let data = try? Data(contentsOf: url)
            let decoded = data.flatMap { try? JSONDecoder().decode(NettopChildSnapshot.self, from: $0) }
            Check.expectEqual(decoded, owned)
            let permissions = try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
            Check.expectEqual((permissions as? NSNumber)?.intValue, 0o600)
            tracker.forgetChild(pid: owned.pid + 1)
            Check.expectTrue(FileManager.default.fileExists(atPath: url.path))
            tracker.forgetChild(pid: owned.pid)
            Check.expectFalse(FileManager.default.fileExists(atPath: url.path))
        }
        Check.test("invalid recovery data never sends a signal") {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("nettop-corrupt-" + UUID().uuidString)
            try! Data("not JSON".utf8).write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            var signals = 0
            let tracker = NettopChildTracker(recordURL: url, lookup: { _ in orphan },
                                            signal: { _ in signals += 1; return true })
            Check.expectFalse(tracker.reapRecordedOrphan())
            Check.expectEqual(signals, 0)
        }
        Check.test("the kernel reader identifies this process without trusting its command line") {
            let actual = NettopChildSnapshot.read(pid: getpid())
            Check.expectEqual(actual?.pid, getpid())
            Check.expectEqual(actual?.parentPID, getppid())
            Check.expectEqual(actual?.uid, getuid())
            Check.expectTrue((actual?.startSeconds ?? 0) > 0)
        }
    }
}
