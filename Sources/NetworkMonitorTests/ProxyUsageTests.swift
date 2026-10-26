import Foundation
import SQLite3
import NetworkMonitorCore

func runProxyUsageTests() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let now = cal.startOfDay(for: Date()).addingTimeInterval(12 * 3600)
    let network = NetworkFingerprint.make(kind: .wifi, gatewayMAC: "test-proxy-network",
                                         interfaceName: "en0", isExpensive: false, isConstrained: false)
    let client = AppIdentity(key: "client", displayName: "Chrome", bundlePath: "/Applications/Chrome.app", isSystem: false)
    let proxy = AppIdentity(key: "proxy", displayName: "nano", bundlePath: "/Applications/nano.app", isSystem: false)
    func fixture(_ body: (URL, UsageStore, UsageHistory) -> Void) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("proxy-store-" + UUID().uuidString)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = UsageHistory(databaseURL: directory.appendingPathComponent("history.sqlite"), calendar: cal)
        let store = UsageStore(storeURL: directory.appendingPathComponent("usage.json"), calendar: cal, history: history)
        store.setCurrentNetwork(network, now: now)
        body(directory, store, history)
    }
    func day(_ date: Date) -> HistoryPeriod { HistoryPeriod(scale: .day, containing: date, calendar: cal) }

    Check.suite("Proxy usage accounting and history") {
        Check.test("client and transport totals persist separately without doubling the headline or CSV") {
            fixture { directory, store, history in
                store.noteProxyAttribution(now: now)
                store.recordInterface(bytesIn: 1000, bytesOut: 100, now: now)
                store.recordApps([(client, 800, 60), (proxy, 1000, 100)],
                                 proxyTransportKeys: [proxy.key], now: now)
                Check.expectEqual(store.currentBucket.apps[client.key]?.total, 860)
                Check.expectNil(store.currentBucket.apps[proxy.key])
                Check.expectEqual(store.currentBucket.proxyTransports[proxy.key]?.total, 1100)
                Check.expectEqual(store.currentBucket.internetTotal, 1100)
                store.save()
                let reopened = UsageStore(storeURL: directory.appendingPathComponent("usage.json"), calendar: cal)
                reopened.setCurrentNetwork(network, now: now)
                Check.expectEqual(reopened.currentBucket.apps[client.key]?.total, 860)
                Check.expectEqual(reopened.currentBucket.proxyTransports[proxy.key]?.total, 1100)
                Check.expectEqual(reopened.proxyAttributionStartedAt, now)
                let report = history.report(for: day(now))
                Check.expectEqual(report.total, 1100)
                Check.expectEqual(report.apps.first?.displayName, "Chrome")
                Check.expectEqual(report.apps.first?.total, 860)
                Check.expectEqual(report.proxyTransports.first?.displayName, "nano")
                Check.expectEqual(report.proxyTransports.first?.total, 1100)
                let csv = history.exportCSV(for: day(now))
                Check.expectTrue(csv.contains(",Chrome,800,60"))
                Check.expectFalse(csv.contains(",nano,"), "transport totals must not be summed twice")
            }
        }
        Check.test("existing proxy bytes are kept as an aggregate without inventing historical client use") {
            fixture { _, store, history in
                store.recordInterface(bytesIn: 1000, bytesOut: 0, now: now)
                store.recordApps([(proxy, 500, 0)], now: now)
                store.recordApps([(proxy, 200, 0)], proxyTransportKeys: [proxy.key], now: now + 1)
                Check.expectNil(store.currentBucket.apps[proxy.key])
                Check.expectEqual(store.currentBucket.proxyTransports[proxy.key]?.total, 700)
                let report = history.report(for: day(now))
                Check.expectEqual(report.apps.first?.total, 500, "old stored history is unchanged")
                Check.expectEqual(report.proxyTransports.first?.total, 200)
                Check.expectFalse(report.apps.contains { $0.id == client.key })
            }
        }
        Check.test("transport history survives reopening and follows retention and clear") {
            fixture { directory, store, history in
                let old = now - 90 * 24 * 3600
                history.join(network, label: "Test", switched: false, now: old)
                history.recordInterface(bytesIn: 20, bytesOut: 0, now: old)
                history.recordApps([(proxy, 20, 0)], proxyTransportKeys: [proxy.key], now: old)
                history.join(network, label: "Test", switched: false, now: now)
                history.recordInterface(bytesIn: 30, bytesOut: 0, now: now)
                history.recordApps([(proxy, 30, 0)], proxyTransportKeys: [proxy.key], now: now)
                history.flush(now: now)
                let reopened = UsageHistory(databaseURL: directory.appendingPathComponent("history.sqlite"), calendar: cal)
                Check.expectEqual(reopened.report(for: day(now)).proxyTransports.first?.total, 30)
                history.retention = .oneMonth
                Check.expectTrue(history.report(for: day(old)).proxyTransports.isEmpty)
                Check.expectEqual(history.report(for: day(now)).proxyTransports.first?.total, 30)
                history.clear(now: now)
                Check.expectTrue(history.report(for: day(now)).proxyTransports.isEmpty)
                Check.expectTrue(history.report(for: day(now)).apps.isEmpty)
            }
        }
        Check.test("a version-one database is upgraded additively without losing app history") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("proxy-migrate-" + UUID().uuidString)
            try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("history.sqlite")
            do {
                let history = UsageHistory(databaseURL: url, calendar: cal)
                history.join(network, label: "Test", switched: false, now: now)
                history.recordInterface(bytesIn: 44, bytesOut: 0, now: now)
                history.recordApps([(client, 44, 0)], now: now)
                history.flush(now: now)
            }
            var db: OpaquePointer?
            guard sqlite3_open(url.path, &db) == SQLITE_OK else { Check.expectTrue(false); return }
            Check.expectEqual(sqlite3_exec(db, "DROP TABLE proxy_transport_traffic; PRAGMA user_version=1", nil, nil, nil), SQLITE_OK)
            sqlite3_close(db)
            let history = UsageHistory(databaseURL: url, calendar: cal)
            Check.expectEqual(history.report(for: day(now)).apps.first?.total, 44)
            history.recordApps([(proxy, 10, 0)], proxyTransportKeys: [proxy.key], now: now)
            Check.expectEqual(history.report(for: day(now)).proxyTransports.first?.total, 10)
            Check.expectEqual(history.report(for: day(now)).apps.first?.total, 44)
        }
        Check.test("the view model routes a proxy fixture to the source process and separate transport") {
            fixture { directory, store, _ in
                let script = directory.appendingPathComponent("fixture-external")
                let loopScript = directory.appendingPathComponent("fixture-loopback")
                let data = """
                time,,bytes_in,bytes_out,
                00:00:00,ProxyFixture.200000002,1,1,
                time,,bytes_in,bytes_out,
                00:00:01,ProxyFixture.200000002,550,50,
                00:00:01,tcp4 192.168.1.2:50001<->1.1.1.1:443,550,50,
                time,,bytes_in,bytes_out,
                """
                let loopData = """
                time,,bytes_in,bytes_out,
                00:00:00,ProxyFixture.200000002,1,1,
                00:00:00,tcp4 127.0.0.1:65532<->127.0.0.1:50000,1,1,
                time,,bytes_in,bytes_out,
                00:00:01,ClientFixture.200000001,500,50,
                00:00:01,tcp4 127.0.0.1:50000<->127.0.0.1:65532,500,50,
                00:00:01,ProxyFixture.200000002,50,500,
                00:00:01,tcp4 127.0.0.1:65532<->127.0.0.1:50000,50,500,
                time,,bytes_in,bytes_out,
                """
                for (url, content, delay) in [(script, data, "sleep 0.25\n"), (loopScript, loopData, "")] {
                    try! ("#!/bin/sh\n" + delay + "cat <<'FIXTURE'\n" + content + "\nFIXTURE\nexec /bin/cat\n").write(to: url, atomically: true, encoding: .utf8)
                    try! FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
                }
                let defaults = UserDefaults(suiteName: "proxy-model-" + UUID().uuidString)!
                let metering = MeteringController(store: store, journal: SuppressionJournal(url: directory.appendingPathComponent("journal.json")), suppressors: [], defaults: defaults)
                let stream = NettopStream(executable: script.path)
                let loopStream = NettopStream(executable: loopScript.path, interfaceScope: .loopback,
                                             proxyEndpoints: { [LocalProxyEndpoint(host: "127.0.0.1", port: 65532)!] })
                let model = MonitorViewModel(store: store, metering: metering, nettop: stream, proxyNettop: loopStream)
                model.start()
                let deadline = Date() + 2
                while store.allNetworks().flatMap({ $0.bucket.proxyTransports.values }).reduce(0, { $0 + $1.total }) < 600, Date() < deadline {
                    RunLoop.main.run(until: Date() + 0.02)
                }
                model.stop()
                let buckets = store.allNetworks().map(\.bucket)
                Check.expectEqual(buckets.flatMap { $0.apps.values }.reduce(0) { $0 + $1.total }, 550)
                Check.expectEqual(buckets.flatMap { $0.proxyTransports.values }.reduce(0) { $0 + $1.total }, 600)
                Check.expectNotNil(store.proxyAttributionStartedAt)
            }
        }
    }
}
