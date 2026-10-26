import Foundation
import NetworkMonitorCore

/// Two bounded HTTP fixtures on loopback: one configured as a proxy endpoint,
/// the other representing local AI/development traffic. Neither reaches the internet.
func runProxyLoopbackIntegrationTests() {
    Check.suite("Proxy attribution — live loopback") {
        guard !Check.skipsLiveTests else {
            Check.skip("attributes only the original client, never the server or unrelated localhost", "needs live nettop")
            return
        }
        Check.test("attributes only the original client, never the server or unrelated localhost") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("proxy-live-" + UUID().uuidString)
            try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let portsURL = directory.appendingPathComponent("ports")
            let server = Process()
            server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            server.arguments = ["-u", "-c", """
            import http.server, threading, time, pathlib, sys
            class Handler(http.server.BaseHTTPRequestHandler):
                def log_message(self, *args): pass
                def do_GET(self):
                    self.send_response(200)
                    self.send_header('Content-Length', str(1024*1024))
                    self.end_headers()
                    try:
                        for _ in range(64):
                            self.wfile.write(b'x'*16384)
                            self.wfile.flush()
                            time.sleep(0.05)
                    except (BrokenPipeError, ConnectionResetError): pass
            servers = [http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler) for _ in range(2)]
            for s in servers:
                threading.Thread(target=s.serve_forever, daemon=True).start()
            pathlib.Path(sys.argv[1]).write_text(','.join(str(s.server_port) for s in servers))
            threading.Event().wait(10)
            """, portsURL.path]
            server.standardOutput = FileHandle.nullDevice
            server.standardError = FileHandle.nullDevice
            func end(_ process: Process) {
                guard process.isRunning else { return }
                process.terminate()
                let deadline = Date() + 0.3
                while process.isRunning, Date() < deadline { usleep(10_000) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
            do { try server.run() } catch { Check.expectTrue(false, "fixture failed: \(error)"); return }
            defer { end(server) }
            let readyBy = Date() + 2
            while !FileManager.default.fileExists(atPath: portsURL.path), server.isRunning, Date() < readyBy {
                usleep(20_000)
            }
            let ports = ((try? String(contentsOf: portsURL)) ?? "").split(separator: ",").compactMap { Int($0) }
            guard ports.count == 2 else { Check.expectTrue(false, "local fixtures did not start"); return }
            let stream = NettopStream(interfaceScope: .loopback, proxyEndpoints: {
                [LocalProxyEndpoint(host: "127.0.0.1", port: ports[0])!]
            })
            let lock = NSLock()
            var samples: [NettopRow] = []
            var transports: [Int32: String] = [:]
            var failure: String?
            stream.onSample = { rows in lock.lock(); samples += rows; lock.unlock() }
            stream.onProxyProcesses = { rows in lock.lock(); transports.merge(rows, uniquingKeysWith: { _, b in b }); lock.unlock() }
            stream.onFailure = { message in lock.lock(); failure = message; lock.unlock() }
            stream.start()
            defer { stream.stop() }
            // Let nettop discard its lifetime baseline before generating traffic.
            Thread.sleep(forTimeInterval: 1.4)
            func client(_ port: Int) -> Process {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                task.arguments = ["--noproxy", "*", "--max-time", "6", "--silent", "--output", "/dev/null", "http://127.0.0.1:\(port)/"]
                task.standardOutput = FileHandle.nullDevice
                task.standardError = FileHandle.nullDevice
                try! task.run()
                return task
            }
            let original = client(ports[0]), unrelated = client(ports[1])
            defer { end(original); end(unrelated) }
            let deadline = Date() + 6
            while (original.isRunning || unrelated.isRunning), Date() < deadline { usleep(20_000) }
            Thread.sleep(forTimeInterval: 1.3)
            stream.stop()
            lock.lock()
            let rows = samples, roles = transports, reported = failure
            lock.unlock()
            Check.expectNil(reported)
            Check.expectFalse(original.isRunning)
            Check.expectFalse(unrelated.isRunning)
            if !original.isRunning { Check.expectEqual(original.terminationStatus, 0) }
            if !unrelated.isRunning { Check.expectEqual(unrelated.terminationStatus, 0) }
            let attributed = rows.filter { $0.pid == original.processIdentifier }.reduce(Int64(0)) { $0 + $1.internetBytesIn }
            Check.expectTrue(attributed >= 262_144 && attributed <= 1_100_000, "observed \(attributed) B of a 1 MiB local transfer")
            Check.expectEqual(rows.filter { $0.pid == unrelated.processIdentifier }.reduce(Int64(0)) { $0 + $1.internetBytesIn + $1.internetBytesOut }, 0)
            Check.expectEqual(rows.filter { $0.pid == server.processIdentifier }.reduce(Int64(0)) { $0 + $1.internetBytesIn + $1.internetBytesOut }, 0)
            Check.expectNotNil(roles[server.processIdentifier], "server-side sockets must identify the forwarding process")
        }
    }
}
