import Foundation
import NetworkMonitorCore

func withHeadroomFixture(_ directory: URL, body: (Process) -> Void) {
    let executable = "/opt/homebrew/bin/python3.12"
    guard FileManager.default.isExecutableFile(atPath: executable) else {
        Check.skip("Headroom process fixture", "needs an installed Python runtime")
        return
    }
    let package = directory.appendingPathComponent("headroom")
    try! FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    try! "".write(to: package.appendingPathComponent("__init__.py"), atomically: true, encoding: .utf8)
    try! "import sys\nsys.stdin.buffer.read()\n".write(to: package.appendingPathComponent("cli.py"), atomically: true, encoding: .utf8)
    let task = Process(), input = Pipe()
    task.executableURL = URL(fileURLWithPath: executable)
    task.arguments = ["-m", "headroom.cli", "proxy", "--host", "127.0.0.1", "--port", "8787"]
    task.environment = ProcessInfo.processInfo.environment.merging(["PYTHONPATH": directory.path, "PYTHONNOUSERSITE": "1"]) { _, b in b }
    task.standardInput = input.fileHandleForReading
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    try! task.run()
    defer {
        if task.isRunning { task.terminate() }
        let deadline = Date() + 0.3
        while task.isRunning, Date() < deadline { usleep(10_000) }
        if task.isRunning { kill(task.processIdentifier, SIGKILL) }
        try? input.fileHandleForWriting.close()
    }
    usleep(100_000)
    withExtendedLifetime(input) { body(task) }
}

func runHeadroomAccountingTests() {
    Check.suite("Headroom identity and chained proxy accounting") {
        func fixture(_ body: (URL) -> Void) {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("headroom-accounting-" + UUID().uuidString)
            try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            body(directory)
        }
        Check.test("the same Python runtime identifies its Headroom module separately") {
            fixture { directory in
                withHeadroomFixture(directory) { process in
                    let identity = AppIdentityResolver().identity(pid: process.processIdentifier, fallbackName: "Python")
                    Check.expectEqual(identity.displayName, "Headroom")
                    Check.expectFalse(identity.isSystem)
                }
            }
        }
        Check.test("a direct upstream delta stays transport even when no loopback frame currently contains the proxy") {
            fixture { directory in
                withHeadroomFixture(directory) { process in
                    let script = directory.appendingPathComponent("direct-upstream")
                    let data = "time,,bytes_in,bytes_out,\n00:00:00,Python.\(process.processIdentifier),1,1,\ntime,,bytes_in,bytes_out,\n00:00:01,Python.\(process.processIdentifier),300,20,\n00:00:01,tcp4 192.168.1.2:50001<->1.1.1.1:443,300,20,\ntime,,bytes_in,bytes_out,\n"
                    try! ("#!/bin/sh\ncat <<'FIXTURE'\n"+data+"FIXTURE\nexec /bin/cat\n").write(to: script, atomically: true, encoding: .utf8)
                    try! FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
                    let store = UsageStore(storeURL: directory.appendingPathComponent("usage.json"))
                    let metering = MeteringController(store: store, journal: SuppressionJournal(url: directory.appendingPathComponent("journal.json")), suppressors: [], defaults: UserDefaults(suiteName: UUID().uuidString)!)
                    let model = MonitorViewModel(store: store, metering: metering, nettop: NettopStream(executable: script.path))
                    model.start(); RunLoop.main.run(until: Date() + 0.5); model.stop()
                    Check.expectEqual(store.allNetworks().flatMap { $0.bucket.apps.values }.reduce(0) { $0+$1.total }, 0)
                    Check.expectEqual(store.allNetworks().flatMap { $0.bucket.proxyTransports.values }.reduce(0) { $0+$1.total }, 320)
                }
            }
        }
        Check.test("a client through Headroom and Nano is billed once and both forwarding hops are separate") {
            fixture { directory in
                withHeadroomFixture(directory) { process in
                    let pid = process.processIdentifier
                    let external = """
                    time,,bytes_in,bytes_out,
                    00:00:00,NanoFixture.200000002,1,1,
                    time,,bytes_in,bytes_out,
                    00:00:01,NanoFixture.200000002,600,70,
                    00:00:01,tcp4 192.168.1.2:50001<->1.1.1.1:443,600,70,
                    time,,bytes_in,bytes_out,
                    """
                    let loop = """
                    time,,bytes_in,bytes_out,
                    00:00:00,Python.\(pid),1,1,
                    00:00:00,tcp4 127.0.0.1:8787<->127.0.0.1:50000,1,1,
                    00:00:00,NanoFixture.200000002,1,1,
                    00:00:00,tcp4 127.0.0.1:65532<->127.0.0.1:51000,1,1,
                    time,,bytes_in,bytes_out,
                    00:00:01,ClientFixture.200000001,500,50,
                    00:00:01,tcp4 127.0.0.1:50000<->127.0.0.1:8787,500,50,
                    00:00:01,Python.\(pid),600,560,
                    00:00:01,tcp4 127.0.0.1:8787<->127.0.0.1:50000,50,500,
                    00:00:01,tcp4 127.0.0.1:51000<->127.0.0.1:65532,550,60,
                    00:00:01,NanoFixture.200000002,60,550,
                    00:00:01,tcp4 127.0.0.1:65532<->127.0.0.1:51000,60,550,
                    time,,bytes_in,bytes_out,
                    """
                    func stream(_ name: String, _ data: String, scope: NettopStream.InterfaceScope) -> NettopStream {
                        let url = directory.appendingPathComponent(name)
                        let delay = scope == .external ? "sleep 0.25\n" : ""
                        try! ("#!/bin/sh\n" + delay + "cat <<'FIXTURE'\n" + data + "\nFIXTURE\nexec /bin/cat\n").write(to: url, atomically: true, encoding: .utf8)
                        try! FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
                        return NettopStream(executable: url.path, interfaceScope: scope,
                                            proxyEndpoints: { [LocalProxyEndpoint(host: "127.0.0.1", port: 65532)!] })
                    }
                    let store = UsageStore(storeURL: directory.appendingPathComponent("usage.json"))
                    let defaults = UserDefaults(suiteName: UUID().uuidString)!
                    let metering = MeteringController(store: store, journal: SuppressionJournal(url: directory.appendingPathComponent("journal.json")), suppressors: [], defaults: defaults)
                    let model = MonitorViewModel(store: store, metering: metering,
                        nettop: stream("external", external, scope: .external),
                        proxyNettop: stream("loopback", loop, scope: .loopback))
                    model.start()
                    let deadline = Date() + 1.5
                    while Date() < deadline { RunLoop.main.run(until: Date() + 0.02) }
                    model.stop()
                    let buckets = store.allNetworks().map(\.bucket)
                    Check.expectEqual(buckets.flatMap { $0.apps.values }.reduce(0) { $0 + $1.total }, 550)
                    Check.expectFalse(buckets.flatMap { $0.apps.values }.contains { $0.displayName == "Headroom" })
                    Check.expectEqual(buckets.flatMap { $0.proxyTransports.values }.filter { $0.displayName == "Headroom" }.reduce(0) { $0 + $1.total }, 610)
                    Check.expectEqual(buckets.flatMap { $0.proxyTransports.values }.filter { $0.displayName == "NanoFixture" }.reduce(0) { $0 + $1.total }, 670)
                }
            }
        }
    }
}
