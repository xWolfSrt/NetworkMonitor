import Foundation
import SQLite3
import NetworkMonitorCore

func runRuntimeToolTests() {
    let python = "/opt/homebrew/Python.app/Contents/MacOS/Python"
    Check.suite("Runtime entry points and safe metadata") {
        Check.test("only an actual Headroom entry point is recognised") {
            for args in [["python", "-m", "headroom.cli", "serve"],
                         ["python", "-u", "-m", "headroom", "proxy"],
                         ["python", "/Users/me/.local/bin/headroom", "serve"]] {
                Check.expectEqual(RuntimeTool.recognize(executablePath: python, arguments: args)?.identity.displayName, "Headroom")
            }
            for args in [["python", "other.py", "--description", "headroom"],
                         ["python", "-c", "import headroom"],
                         ["python", "-m", "headroom_other", "proxy"],
                         ["python", "headroom_helper.py", "proxy"]] {
                Check.expectNil(RuntimeTool.recognize(executablePath: python, arguments: args))
            }
        }
        Check.test("only explicit local proxy listeners become endpoints, never MCP proxy-url options") {
            let proxy = RuntimeTool.recognize(executablePath: python, arguments: ["python", "-m", "headroom.cli", "proxy", "--host=::1", "--port=8788"])!
            Check.expectEqual(proxy.proxyEndpoints, [LocalProxyEndpoint(host: "::1", port: 8788)!])
            for args in [["python", "-m", "headroom.cli", "serve", "--proxy-url", "http://127.0.0.1:8787"],
                         ["python", "-m", "headroom.cli", "proxy"],
                         ["python", "-m", "headroom.cli", "proxy", "--host", "example.invalid", "--port", "8787"],
                         ["python", "-m", "headroom.cli", "proxy", "--host", "127.0.0.1", "--port", "65536"]] {
                Check.expectTrue(RuntimeTool.recognize(executablePath: python, arguments: args)!.proxyEndpoints.isEmpty)
            }
        }
        Check.test("kernel argv decoding stops at argc and rejects truncated data") {
            var data = Data([3, 0, 0, 0])
            data.append(Data("/runtime/python\0\0python\0-m\0headroom.cli\0SECRET_ENV=hidden\0".utf8))
            Check.expectEqual(RuntimeTool.decodeArguments(data), ["python", "-m", "headroom.cli"])
            Check.expectNil(RuntimeTool.decodeArguments(Data([3, 0, 0, 0, 47, 0, 0])))
            Check.expectNil(RuntimeTool.decodeArguments(Data([255, 255, 255, 255, 0])))
        }
        Check.test("a vanished proxy port does not turn a new localhost service into internet usage") {
            let endpoint = LocalProxyEndpoint(host: "127.0.0.1", port: 8787)!
            var parser = NettopParser(loopbackOnly: true, processProxyEndpoints: { pid, _ in pid == 42 ? [endpoint] : [] })
            _ = parser.consume("time,,bytes_in,bytes_out,\n00:00:00,Python.42,1,1,\ntime,,bytes_in,bytes_out,\n")
            Check.expectEqual(parser.proxyTransportProcesses[42], "Python", "known proxy metadata must survive an empty priming row")
            let rows = parser.consume("00:00:01,Client.22,500,50,\n00:00:01,tcp4 127.0.0.1:50000<->127.0.0.1:8787,500,50,\n00:00:01,OtherService.43,50,500,\n00:00:01,tcp4 127.0.0.1:8787<->127.0.0.1:50000,50,500,\ntime,,bytes_in,bytes_out,\n").first!
            Check.expectEqual(rows[0].internetBytesIn + rows[0].internetBytesOut, 0)
            Check.expectFalse(rows[1].isProxyTransport)
        }
        Check.test("a newly discovered proxy also attributes clients written earlier in the same frame") {
            let endpoint = LocalProxyEndpoint(host: "127.0.0.1", port: 8787)!
            var parser = NettopParser(loopbackOnly: true, processProxyEndpoints: { pid, _ in pid == 42 ? [endpoint] : [] })
            _ = parser.consume("time,,bytes_in,bytes_out,\n00:00:00,Primer.1,1,1,\ntime,,bytes_in,bytes_out,\n")
            let rows = parser.consume("00:00:01,Client.22,500,50,\n00:00:01,tcp4 127.0.0.1:50000<->127.0.0.1:8787,500,50,\n00:00:01,Python.42,50,500,\n00:00:01,tcp4 127.0.0.1:8787<->127.0.0.1:50000,50,500,\ntime,,bytes_in,bytes_out,\n").first!
            Check.expectEqual(rows[0].internetBytesIn, 500)
            Check.expectEqual(rows[0].internetBytesOut, 50)
            Check.expectTrue(rows[1].isProxyTransport)
            Check.expectEqual(rows[1].internetBytesIn + rows[1].internetBytesOut, 0)
            parser.resetForRestart()
            Check.expectTrue(parser.proxyTransportProcesses.isEmpty, "restart must not reuse a vanished listener")
        }
    }
}

func runLegacyRuntimeAccountingTests() {
    Check.suite("Earlier mixed runtime records") {
        Check.test("a v2 store moves exact mixed bytes aside once, keeping new Python and Headroom separate") {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("runtime-migration-" + UUID().uuidString)
            try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let url = dir.appendingPathComponent("history.sqlite"), storeURL = dir.appendingPathComponent("usage.json")
            let now = Date(), network = NetworkFingerprint.make(kind: .wifi, gatewayMAC: "legacy-runtime-test", interfaceName: "en0", isExpensive: false, isConstrained: false)
            let python = AppIdentity(key: "/old/Python.app", displayName: "Python", bundlePath: "/old/Python.app", isSystem: false)
            let child = AppIdentity(key: "curl", displayName: "curl", bundlePath: nil, isSystem: false,
                parent: ParentApp(key: python.key, displayName: "Python", bundlePath: python.bundlePath!))
            do {
                let history = UsageHistory(databaseURL: url)
                let store = UsageStore(storeURL: storeURL, history: history)
                store.setCurrentNetwork(network, now: now)
                store.recordInterface(bytesIn: 1000, bytesOut: 100, now: now)
                store.recordApps([(python, 100, 50), (child, 10, 7)], now: now)
                store.save(); history.flush(now: now)
            }
            var json = try! JSONSerialization.jsonObject(with: Data(contentsOf: storeURL)) as! [String: Any]
            json.removeValue(forKey: "runtimeAttributionStartedAt")
            try! JSONSerialization.data(withJSONObject: json).write(to: storeURL)
            var db: OpaquePointer?
            Check.expectEqual(sqlite3_open(url.path, &db), SQLITE_OK)
            Check.expectEqual(sqlite3_exec(db, "PRAGMA user_version=2", nil, nil, nil), SQLITE_OK)
            sqlite3_close(db)
            let history = UsageHistory(databaseURL: url), store = UsageStore(storeURL: storeURL)
            store.setCurrentNetwork(network, now: now)
            Check.expectTrue(store.currentBucket.apps.isEmpty)
            Check.expectEqual(store.currentBucket.legacyApps.values.reduce(0) { $0 + $1.total }, 167)
            Check.expectEqual(store.currentBucket.internetTotal, 1100)
            let period = HistoryPeriod(scale: .day, containing: now)
            let migrated = history.report(for: period)
            Check.expectTrue(migrated.apps.isEmpty)
            Check.expectEqual(migrated.legacyApps.reduce(0) { $0 + $1.total }, 167)
            Check.expectEqual(migrated.total, 1100)
            let headroom = RuntimeTool.recognize(executablePath: "/usr/bin/python3", arguments: ["python3", "-m", "headroom.cli", "serve"])!.identity
            history.recordApps([(python, 8, 2), (headroom, 200, 20)], proxyTransportKeys: [headroom.key], now: now)
            store.recordApps([(python, 8, 2)], now: now); store.save()
            let report = history.report(for: period)
            Check.expectEqual(report.apps.first?.total, 10)
            Check.expectEqual(report.proxyTransports.first?.displayName, "Headroom")
            Check.expectEqual(report.proxyTransports.first?.total, 220)
            Check.expectEqual(report.legacyApps.reduce(0) { $0 + $1.total }, 167)
            Check.expectFalse(history.exportCSV(for: period).contains(",Headroom,"))
            let reopened = UsageStore(storeURL: storeURL)
            reopened.setCurrentNetwork(network, now: now)
            Check.expectEqual(reopened.currentBucket.apps[python.key]?.total, 10)
            Check.expectEqual(reopened.currentBucket.legacyApps.values.reduce(0) { $0 + $1.total }, 167)
            let secondHistory = UsageHistory(databaseURL: url)
            Check.expectEqual(secondHistory.report(for: period).legacyApps.reduce(0) { $0 + $1.total }, 167)
            history.clear(now: now)
            Check.expectTrue(history.report(for: period).legacyApps.isEmpty)
        }
    }
}
