import Foundation
import NetworkMonitorCore

func runHeadroomLoopbackIntegrationTests() {
    Check.suite("Headroom — live two-hop loopback chain") {
        guard !Check.skipsLiveTests else {
            Check.skip("counts the source once across two local forwarding hops", "needs live nettop")
            return
        }
        Check.test("counts the source once across two local forwarding hops") {
            let python = "/opt/homebrew/bin/python3.12"
            guard FileManager.default.isExecutableFile(atPath: python) else {
                Check.skip("two-hop fixture", "needs Python"); return
            }
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("headroom-live-" + UUID().uuidString)
            try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            func stop(_ task: Process) {
                if task.isRunning { task.terminate() }
                let deadline = Date() + 0.3
                while task.isRunning, Date() < deadline { usleep(10_000) }
                if task.isRunning { kill(task.processIdentifier, SIGKILL) }
            }
            func run(_ executable: String, _ args: [String], environment: [String: String]? = nil) -> Process {
                let task = Process(); task.executableURL = URL(fileURLWithPath: executable)
                task.arguments = args; task.environment = environment
                task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
                try! task.run(); return task
            }
            func waitFor(_ url: URL, task: Process) -> Bool {
                let deadline = Date() + 3
                while !FileManager.default.fileExists(atPath: url.path), task.isRunning, Date() < deadline { usleep(20_000) }
                return FileManager.default.fileExists(atPath: url.path)
            }
            let portsURL = dir.appendingPathComponent("ports")
            let nano = run(python, ["-u", "-c", """
            import http.server, socket, pathlib, sys, time
            class Payload(http.server.BaseHTTPRequestHandler):
                def log_message(self, *args): pass
                def do_GET(self):
                    self.send_response(200); self.send_header('Content-Length', str(1024*1024)); self.end_headers()
                    try:
                        for _ in range(64):
                            self.wfile.write(b'x'*16384); self.wfile.flush(); time.sleep(0.05)
                    except (BrokenPipeError, ConnectionResetError): pass
            server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Payload)
            reserve=socket.socket(); reserve.bind(('127.0.0.1',0)); port=reserve.getsockname()[1]; reserve.close()
            pathlib.Path(sys.argv[1]).write_text(str(server.server_port)+','+str(port))
            server.serve_forever()
            """, portsURL.path])
            defer { stop(nano) }
            guard waitFor(portsURL, task: nano),
                  let ports = try? String(contentsOf: portsURL).split(separator: ",").compactMap({ Int($0) }), ports.count == 2 else {
                Check.expectTrue(false, "downstream fixture did not start"); return
            }
            let package = dir.appendingPathComponent("headroom")
            try! FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
            try! "".write(to: package.appendingPathComponent("__init__.py"), atomically: true, encoding: .utf8)
            let module = """
            import http.server, urllib.request, pathlib, sys
            port=int(sys.argv[sys.argv.index('--port')+1])
            target=sys.argv[sys.argv.index('--target')+1]
            ready=sys.argv[sys.argv.index('--ready')+1]
            opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
            class Forward(http.server.BaseHTTPRequestHandler):
                def log_message(self, *args): pass
                def do_GET(self):
                    with opener.open(target,timeout=7) as response:
                        self.send_response(200); self.send_header('Content-Length',response.headers['Content-Length']); self.end_headers()
                        while True:
                            data=response.read(16384)
                            if not data: break
                            self.wfile.write(data); self.wfile.flush()
            server=http.server.ThreadingHTTPServer(('127.0.0.1',port),Forward)
            pathlib.Path(ready).write_text('ready')
            server.serve_forever()
            """
            try! module.write(to: package.appendingPathComponent("cli.py"), atomically: true, encoding: .utf8)
            let ready = dir.appendingPathComponent("ready")
            let env = ProcessInfo.processInfo.environment.merging(["PYTHONPATH": dir.path, "PYTHONNOUSERSITE": "1"]) { _, b in b }
            let headroom = run(python, ["-m", "headroom.cli", "proxy", "--host", "127.0.0.1", "--port", String(ports[1]), "--target", "http://127.0.0.1:\(ports[0])/", "--ready", ready.path], environment: env)
            defer { stop(headroom) }
            guard waitFor(ready, task: headroom) else { Check.expectTrue(false, "forwarder did not start"); return }
            Check.expectEqual(AppIdentityResolver().identity(pid: headroom.processIdentifier, fallbackName: "Python").displayName, "Headroom")
            let stream = NettopStream(interfaceScope: .loopback,
                proxyEndpoints: { [LocalProxyEndpoint(host: "127.0.0.1", port: ports[0])!] })
            let lock = NSLock(); var samples: [NettopRow] = []
            stream.onSample = { rows in lock.lock(); samples += rows; lock.unlock() }
            stream.start(); defer { stream.stop() }
            Thread.sleep(forTimeInterval: 1.4)
            let client = run("/usr/bin/curl", ["--noproxy", "*", "--max-time", "8", "--silent", "--output", "/dev/null", "http://127.0.0.1:\(ports[1])/"])
            defer { stop(client) }
            let deadline = Date() + 8
            while client.isRunning, Date() < deadline { usleep(20_000) }
            Thread.sleep(forTimeInterval: 1.3); stream.stop()
            Check.expectFalse(client.isRunning)
            if !client.isRunning { Check.expectEqual(client.terminationStatus, 0) }
            lock.lock(); let rows = samples; lock.unlock()
            let source = rows.filter { $0.pid == client.processIdentifier }.reduce(Int64(0)) { $0 + $1.internetBytesIn }
            let transport = rows.filter { $0.pid == headroom.processIdentifier }.reduce(Int64(0)) { $0 + $1.internetBytesIn }
            Check.expectTrue(source >= 262_144 && source < 1_200_000, "source received \(source) B for a 1 MiB response")
            Check.expectTrue(transport >= 262_144 && transport < 1_200_000, "one forwarded copy, not both socket halves: \(transport) B")
            Check.expectTrue(rows.contains { $0.pid == headroom.processIdentifier && $0.isProxyTransport })
            Check.expectEqual(rows.filter { $0.pid == nano.processIdentifier }.reduce(Int64(0)) { $0 + $1.internetBytesIn + $1.internetBytesOut }, 0)
        }
    }
}
