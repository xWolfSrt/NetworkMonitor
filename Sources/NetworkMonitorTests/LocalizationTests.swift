import AppKit
import Foundation
import NetworkMonitorCore

func runLocalizationTests() {
    Check.suite("Language — selection and catalogs") {
        Check.test("default, persistence, and invalid preferences") {
            let name = "language-test-\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            let settings = LanguageSettings(defaults: defaults)
            Check.expectEqual(settings.language, .simplifiedChinese)
            settings.select(.english)
            Check.expectEqual(LanguageSettings(defaults: defaults).language, .english)
            settings.select(.simplifiedChinese)
            Check.expectEqual(LanguageSettings(defaults: defaults).language, .simplifiedChinese)
            defaults.set("invalid", forKey: LanguageSettings.key)
            Check.expectEqual(LanguageSettings(defaults: defaults).language, .simplifiedChinese)
        }
        Check.test("catalogs match and preserve every interpolation") {
            func entries(_ language: String) -> [String: String] {
                let path = L10n.resourceBundle.path(forResource: language.lowercased(), ofType: "lproj")!
                let url = URL(fileURLWithPath: path).appendingPathComponent("Localizable.strings")
                let data = try! Data(contentsOf: url)
                return try! PropertyListSerialization.propertyList(from: data, format: nil) as! [String: String]
            }
            let en = entries("en"), zh = entries("zh-Hans")
            Check.expectEqual(Set(en.keys), Set(zh.keys))
            let expression = try! NSRegularExpression(pattern: #"\{[0-9]+\}"#)
            func placeholders(_ text: String) -> [String] {
                expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).map {
                    String(text[Range($0.range, in: text)!])
                }.sorted()
            }
            Check.expectTrue(en.count > 200)
            for (key, value) in zh {
                Check.expectTrue(!value.isEmpty, key)
                Check.expectEqual(placeholders(key), placeholders(value), key)
            }
        }
        Check.test("interpolation does not interpret app names as templates") {
            let name = "App {1} %s 中文"
            let bytes = "12 MB"
            Check.expectEqual(L10n.text("\(name) used \(bytes) during the test — figures may read low", language: .simplifiedChinese),
                              "测速期间 App {1} %s 中文 使用了 12 MB，测量结果可能偏低")
            Check.expectEqual(L10n.text("unknown \(name)", language: .english), "unknown \(name)")
        }
        Check.test("network display translation preserves names and stored labels") {
            let previous = LanguageSettings.shared.language
            defer { LanguageSettings.shared.select(previous, persist: false) }
            LanguageSettings.shared.select(.simplifiedChinese, persist: false)
            let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("language-network-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = UsageStore(storeURL: directory.appendingPathComponent("usage.json"))
            Check.expectEqual(store.localizedDisplayLabel(for: "test", defaultLabel: "Personal Hotspot · 12ab"), "个人热点 · 12ab")
            Check.expectEqual(store.displayLabel(for: "test", defaultLabel: "Personal Hotspot · 12ab"), "Personal Hotspot · 12ab")
            store.setLabel("Personal Hotspot", for: "test")
            Check.expectEqual(store.localizedDisplayLabel(for: "test", defaultLabel: "Personal Hotspot · 12ab"), "Personal Hotspot")
            Check.expectEqual(L10n.defaultNetworkLabel("Ethernet"), "以太网")
            Check.expectEqual(L10n.defaultNetworkLabel("Ethernet · My Home"), "Ethernet · My Home")
            Check.expectEqual(store.localizedDisplayLabel(for: "if:en0", defaultLabel: "Wi-Fi"), "Wi-Fi · 无法区分不同网络")
        }
        Check.test("period dates follow the selected language") {
            let previous = LanguageSettings.shared.language
            defer { LanguageSettings.shared.select(previous, persist: false) }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10))!
            let period = HistoryPeriod(scale: .month, containing: date, calendar: calendar)
            LanguageSettings.shared.select(.simplifiedChinese, persist: false)
            Check.expectTrue(period.title(now: date, calendar: calendar).contains("10月"))
            LanguageSettings.shared.select(.english, persist: false)
            Check.expectTrue(period.title(now: date, calendar: calendar).contains("October"))
        }
        Check.test("switching updates labels and emits one notification") {
            let previous = LanguageSettings.shared.language
            defer { LanguageSettings.shared.select(previous, persist: false) }
            LanguageSettings.shared.select(.simplifiedChinese, persist: false)
            var notifications = 0
            let observer = NotificationCenter.default.addObserver(forName: .appLanguageDidChange,
                object: nil, queue: nil) { _ in notifications += 1 }
            defer { NotificationCenter.default.removeObserver(observer) }
            Check.expectEqual(SettingsPane.general.title, "通用")
            LanguageSettings.shared.select(.english, persist: false)
            Check.expectEqual(SettingsPane.general.title, "General")
            LanguageSettings.shared.select(.english, persist: false)
            Check.expectEqual(notifications, 1)

        }
    }
}

/// Native AppKit/SwiftUI rendering with an isolated store and no samplers,
/// suppressors, privileged helper requests or speed tests.
func renderLocalizationPreviews() throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    let directory = URL(fileURLWithPath: "/private/tmp/networkmonitor-localization-preview", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let name = "localization-preview-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let store = UsageStore(storeURL: directory.appendingPathComponent("usage.json"))
    let metering = MeteringController(store: store,
        journal: SuppressionJournal(url: directory.appendingPathComponent("journal.json")),
        suppressors: [], defaults: defaults)
    let model = MonitorViewModel(store: store, metering: metering)
    let history = HistoryViewModel(monitor: model)
    let controller = SettingsWindowController(model: model, history: history,
        onUninstall: {}, defaults: defaults)
    let content = controller.window.contentViewController
    let old = LanguageSettings.shared.language
    defer {
        LanguageSettings.shared.select(old, persist: false)
        controller.windowWillClose()
        controller.window.orderOut(nil)
    }
    for language in AppLanguage.allCases {
        LanguageSettings.shared.select(language, persist: false)
        for pane in SettingsPane.allCases {
            controller.select(pane)
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
            controller.fitSelectedPane()
            controller.window.orderFront(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            let view = controller.window.contentView!.superview!
            view.layoutSubtreeIfNeeded()
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let url = directory.appendingPathComponent("\(language.rawValue)-\(pane.rawValue).png")
            try bitmap.representation(using: .png, properties: [:])!.write(to: url)
            guard controller.window.title == pane.title,
                  controller.window.contentViewController === content else {
                throw NSError(domain: "LocalizationPreview", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Language refresh discarded the selected pane"])
            }
            print("RENDER", language.rawValue, pane.rawValue, Int(view.bounds.width), Int(view.bounds.height))
        }
        print("TOOLBAR", controller.window.toolbar!.items.map { "\($0.itemIdentifier.rawValue)=\($0.label)" })
    }
    // A switch with the same pane selected must update AppKit immediately.
    controller.select(.history)
    LanguageSettings.shared.select(.simplifiedChinese, persist: false)
    guard controller.window.title == "历史", SettingsPane.last(in: defaults) == .history else {
        throw NSError(domain: "LocalizationPreview", code: 2)
    }
    let labels = controller.window.toolbar!.items.map(\.label)
    guard labels == ["通用", "测速", "历史", "热点", "关于"] else {
        throw NSError(domain: "LocalizationPreview", code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Toolbar did not refresh: \(labels)"])
    }
    print("LIVE_SWITCH_PRESERVES_PANE_AND_CONTROLLER")
}
