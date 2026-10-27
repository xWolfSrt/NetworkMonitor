import Foundation
import NetworkMonitorCore

func runNettopEncodingTests() {
    Check.suite("NettopStream — truncated Unicode process names") {
        Check.test("an invalid process name does not discard another app's sample") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("nettop-encoding-\(UUID().uuidString)")
            try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let script = directory.appendingPathComponent("fixture.sh")
            let body = #"""
            #!/bin/sh
            printf 'time,,bytes_in,bytes_out,\n00:00:00,baseline.90,100,100,\n'
            sleep 0.25
            printf 'time,,bytes_in,bytes_out,\n00:00:01,broken\345.91,2,3,\n00:00:01,curl.92,10,20,\n'
            sleep 2
            """#
            try! body.write(to: script, atomically: true, encoding: .utf8)
            try! FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            let stream = NettopStream(executable: script.path)
            let ready = DispatchSemaphore(value: 0)
            let lock = NSLock()
            var samples: [NettopRow] = []
            stream.onSample = { rows in
                lock.lock(); samples += rows; lock.unlock()
                if rows.contains(where: { $0.pid == 92 }) { ready.signal() }
            }
            stream.start()
            let result = ready.wait(timeout: .now() + 1.8)
            stream.stop()
            Check.expectTrue(result == .success, "invalid UTF-8 discarded the surrounding valid rows")
            lock.lock(); let rows = samples; lock.unlock()
            Check.expectEqual(rows.first(where: { $0.pid == 92 })?.bytesIn, 10)
        }
    }
}

func runNettopTextDecoderTests() {
    Check.suite("NettopTextDecoder — byte boundaries") {
        Check.test("every split preserves valid Chinese and emoji names") {
            let row = "00:00:01,微信🦊.42,10,20,\n"
            let bytes = Data(row.utf8)
            for split in 0...bytes.count {
                var decoder = NettopTextDecoder()
                let value = decoder.consume(bytes.prefix(split)) + decoder.consume(bytes.dropFirst(split))
                Check.expectEqual(value, row)
                Check.expectFalse(decoder.hasPartialLine)
            }
            var decoder = NettopTextDecoder()
            let value = bytes.reduce(into: "") { result, byte in result += decoder.consume(Data([byte])) }
            Check.expectEqual(value, row)
        }
        Check.test("invalid names are repaired without losing surrounding rows") {
            var decoder = NettopTextDecoder()
            var bytes = Data("broken".utf8)
            bytes.append(0xE5)
            bytes.append(Data(".91,2,3,\r\ncurl.92,10,20,\r\n".utf8))
            Check.expectEqual(decoder.consume(bytes), "broken�.91,2,3,\ncurl.92,10,20,\n")
            Check.expectFalse(decoder.hasPartialLine)
        }
        Check.test("partial lines block quiet publication and reset between children") {
            var decoder = NettopTextDecoder()
            Check.expectEqual(decoder.consume(Data("first\npart".utf8)), "first\n")
            Check.expectTrue(decoder.hasPartialLine)
            Check.expectEqual(decoder.consume(Data("ial\n".utf8)), "partial\n")
            Check.expectFalse(decoder.hasPartialLine)
            _ = decoder.consume(Data("old child".utf8))
            decoder.reset()
            Check.expectEqual(decoder.consume(Data("new child\n".utf8)), "new child\n")
        }
    }
}
