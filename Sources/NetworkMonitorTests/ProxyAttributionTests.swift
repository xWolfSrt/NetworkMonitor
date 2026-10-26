import Foundation
import NetworkMonitorCore

func runProxyAttributionTests() {
    let endpoint = LocalProxyEndpoint(host: "127.0.0.1", port: 65532)!
    func sample(_ text: String, endpoints: Set<LocalProxyEndpoint> = []) -> [NettopRow] {
        var parser = NettopParser(proxyEndpoints: endpoints)
        return parser.consume("time,,bytes_in,bytes_out,\n00:00:00,Primer.1,1,1,\n"
            + "time,,bytes_in,bytes_out,\n" + text + "\ntime,,bytes_in,bytes_out,\n").first ?? []
    }
    Check.suite("Explicit local system proxies") {
        Check.test("enabled endpoints are validated and deduplicated without reading credentials") {
            let values: [String: Any] = ["HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": 65532,
                "HTTPSEnable": true, "HTTPSProxy": "127.0.0.1", "HTTPSPort": 65532,
                "SOCKSEnable": 0, "SOCKSProxy": "127.0.0.1", "SOCKSPort": 9999,
                "ProxyAutoConfigEnable": 1, "ProxyAutoConfigURLString": "https://example.invalid/proxy.pac"]
            Check.expectEqual(SystemProxyEndpoints.endpoints(in: values), [endpoint])
            Check.expectNil(LocalProxyEndpoint(host: "10.0.0.2", port: 65532))
            Check.expectNil(LocalProxyEndpoint(host: "example.invalid", port: 65532))
            Check.expectNil(LocalProxyEndpoint(host: "127.0.0.1", port: 0))
            Check.expectNil(LocalProxyEndpoint(host: "127.0.0.1", port: 65536))
        }
        Check.test("the original client and the proxy server are distinct") {
            let rows = sample("""
            00:00:01,Chrome.22,1300,150,
            00:00:01,tcp4 127.0.0.1:50000<->127.0.0.1:65532,1000,100,
            00:00:01,tcp4 10.0.0.1:50001<->1.1.1.1:443,300,50,
            00:00:01,nano.33,1200,1300,
            00:00:01,tcp4 127.0.0.1:65532<->127.0.0.1:50000,100,1000,
            00:00:01,tcp4 10.0.0.1:50002<->1.1.1.1:443,1100,300,
            """, endpoints: [endpoint])
            Check.expectEqual(rows.count, 2)
            Check.expectEqual(rows.first?.internetBytesIn, 1300)
            Check.expectEqual(rows.first?.proxyBytesIn, 1000)
            Check.expectEqual(rows.first?.subtractableLocalIn, 0)
            Check.expectEqual(rows.first?.isProxyTransport, false)
            Check.expectEqual(rows.last?.internetBytesIn, 1100)
            Check.expectEqual(rows.last?.internetBytesOut, 300)
            Check.expectEqual(rows.last?.proxyBytesIn, 0)
            Check.expectEqual(rows.last?.isProxyTransport, true)
        }
        Check.test("other localhost services stay excluded") {
            let rows = sample("""
            00:00:01,App.22,900,200,
            00:00:01,tcp4 127.0.0.1:50000<->127.0.0.1:8000,900,200,
            """, endpoints: [endpoint])
            Check.expectEqual(rows.first?.internetBytesIn, 0)
            Check.expectEqual(rows.first?.subtractableLocalIn, 0)
            Check.expectEqual(rows.first?.isProxyTransport, false)
        }
        Check.test("IPv6 dot and bracket socket forms match localhost proxies") {
            let local = LocalProxyEndpoint(host: "localhost", port: 65532)!
            for address in ["tcp6 ::1.50000<->::1.65532",
                            "tcp6 [::1]:50000<->[::1]:65532",
                            "tcp6 0:0:0:0:0:0:0:1.50000<->0:0:0:0:0:0:0:1.65532"] {
                let relation = LocalProxyConnection(label: address, endpoints: [local])
                Check.expectTrue(relation.isLoopback)
                Check.expectTrue(relation.role == .client)
            }
        }
        Check.test("a UDP service sharing a TCP proxy port is not guessed to be proxy usage") {
            let relation = LocalProxyConnection(label: "udp4 127.0.0.1:50000<->127.0.0.1:65532",
                                                endpoints: [endpoint])
            Check.expectTrue(relation.isLoopback)
            Check.expectTrue(relation.role == .none)
        }
        Check.test("an external endpoint with the proxy's port is never reclassified") {
            let relation = LocalProxyConnection(label: "tcp4 10.0.0.1:50000<->1.1.1.1:65532",
                                                endpoints: [endpoint])
            Check.expectFalse(relation.isLoopback)
            Check.expectTrue(relation.role == .none)
        }
        Check.test("changing or disabling the system proxy clears forwarding recognition") {
            var parser = NettopParser(proxyEndpoints: [endpoint])
            let first = "time,,bytes_in,bytes_out,\n00:00:00,nano.33,1,1,\n"
                + "time,,bytes_in,bytes_out,\n00:00:01,nano.33,20,30,\n"
                + "00:00:01,tcp4 127.0.0.1:65532<->127.0.0.1:50000,10,10,\ntime,,bytes_in,bytes_out,\n"
            Check.expectEqual(parser.consume(first).first?.first?.isProxyTransport, true)
            Check.expectEqual(parser.consume("00:00:02,nano.33,20,30,\ntime,,bytes_in,bytes_out,\n")
                .first?.first?.isProxyTransport, true)
            parser.proxyEndpoints = []
            Check.expectEqual(parser.consume("00:00:03,nano.33,20,30,\ntime,,bytes_in,bytes_out,\n")
                .first?.first?.isProxyTransport, false)
        }
        Check.test("loopback root totals never become internet when closed sockets disappear") {
            var parser = NettopParser(proxyEndpoints: [endpoint], loopbackOnly: true)
            let rows = parser.consume("time,,bytes_in,bytes_out,\n00:00:00,App.22,1,1,\n"
                + "time,,bytes_in,bytes_out,\n00:00:01,App.22,900,200,\ntime,,bytes_in,bytes_out,\n").first!
            Check.expectTrue(rows[0].isLoopbackSample)
            Check.expectEqual(rows[0].internetBytesIn, 0)
            Check.expectEqual(rows[0].internetBytesOut, 0)
        }
        Check.test("priming discovers the forwarding process without billing its lifetime bytes") {
            var parser = NettopParser(proxyEndpoints: [endpoint], loopbackOnly: true)
            let rows = parser.consume("time,,bytes_in,bytes_out,\n00:00:00,nano.33,1000000,1000000,\n"
                + "00:00:00,tcp4 127.0.0.1:65532<->127.0.0.1:50000,1000000,1000000,\n"
                + "time,,bytes_in,bytes_out,\n")
            Check.expectTrue(rows.isEmpty)
            Check.expectEqual(parser.proxyTransportProcesses, [33: "nano"])
            _ = parser.consume("00:00:01,Other.33,0,0,\ntime,,bytes_in,bytes_out,\n")
            Check.expectTrue(parser.proxyTransportProcesses.isEmpty, "PID reuse with a different name clears the role")
        }
        Check.test("LAN and loopback deductions remain separate") {
            let rows = sample("""
            00:00:01,App.22,1600,160,
            00:00:01,tcp4 127.0.0.1:50000<->127.0.0.1:65532,1000,100,
            00:00:01,tcp4 192.168.1.2:50001<->192.168.1.3:445,500,50,
            00:00:01,tcp4 192.168.1.2:50002<->1.1.1.1:443,100,10,
            """, endpoints: [endpoint])
            Check.expectEqual(rows.first?.internetBytesIn, 1100)
            Check.expectEqual(rows.first?.subtractableLocalIn, 500)
            Check.expectEqual(rows.first?.localBytesIn, 1500)
        }
    }
}
