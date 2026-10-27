import Combine
import Foundation
import SwiftUI

public enum AppLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    public var id: String { rawValue }
    public var nativeName: String { self == .simplifiedChinese ? "简体中文" : "English" }
    public var locale: Locale { Locale(identifier: self == .simplifiedChinese ? "zh_CN" : "en_US") }
}

extension Notification.Name {
    public static let appLanguageDidChange = Notification.Name("NetworkMonitor.appLanguageDidChange")
}

/// App-owned preference. Does not change the system language or measurement data.
public final class LanguageSettings: ObservableObject {
    public static let shared = LanguageSettings()
    public static let key = "interfaceLanguage"
    @Published public private(set) var language: AppLanguage
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = defaults.string(forKey: Self.key).flatMap(AppLanguage.init(rawValue:)) ?? .simplifiedChinese
    }

    /// Non-persisting selection is used by isolated tests only.
    public func select(_ value: AppLanguage, persist: Bool = true) {
        if persist { defaults.set(value.rawValue, forKey: Self.key) }
        guard language != value else { return }
        language = value
        NotificationCenter.default.post(name: .appLanguageDidChange, object: self)
    }
}

/// Interpolation values stay separate from the translation key: names supplied
/// by the user never become format strings or translation lookups.
public struct LocalizedText: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    let key: String
    let arguments: [String]

    public init(stringLiteral value: String) { key = value; arguments = [] }
    public init(stringInterpolation value: StringInterpolation) {
        key = value.key; arguments = value.arguments
    }

    public struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []
        public init(literalCapacity: Int, interpolationCount: Int) {
            key.reserveCapacity(literalCapacity); arguments.reserveCapacity(interpolationCount)
        }
        public mutating func appendLiteral(_ literal: String) { key += literal }
        public mutating func appendInterpolation<T>(_ value: T) {
            key += "{\(arguments.count)}"
            arguments.append(String(describing: value))
        }
    }
}

public enum L10n {
    public static var locale: Locale { LanguageSettings.shared.language.locale }
    // SwiftPM's accessor can fall back to the build directory. Installed apps
    // resolve their own bundled resources first; CLI tests use Bundle.module.
    public static let resourceBundle: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("NetworkMonitor_NetworkMonitorCore.bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return .module
    }()

    /// Only generated fallback labels enter this function. User labels and
    /// SSIDs must be returned unchanged by the caller.
    public static func defaultNetworkLabel(_ label: String) -> String {
        for base in ["Wi-Fi", "Personal Hotspot", "Ethernet", "Network", "No Connection"] {
            if label == base { return translate(base) }
            let prefix = base + " · "
            if label.hasPrefix(prefix) {
                let suffix = String(label.dropFirst(prefix.count))
                if suffix.count == 4 && suffix.allSatisfy({ $0.isHexDigit }) {
                    return translate(base) + " · " + suffix
                }
            }
        }
        return label
    }

    public static func translate(_ key: String, language: AppLanguage? = nil) -> String {
        let selected = language ?? LanguageSettings.shared.language
        guard let path = resourceBundle.path(forResource: selected.rawValue.lowercased(), ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    public static func text(_ value: LocalizedText, language: AppLanguage? = nil) -> String {
        var result = translate(value.key, language: language)
        // Collect ranges before substitution. A name containing "{1}" stays
        // literal, even when another argument occupies placeholder 1.
        let expression = try! NSRegularExpression(pattern: #"\{([0-9]+)\}"#)
        let matches = expression.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let indexRange = Range(match.range(at: 1), in: result),
                  let index = Int(result[indexRange]), value.arguments.indices.contains(index),
                  let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: value.arguments[index])
        }
        return result
    }
}

/// Keeps SwiftUI identity and state while updating native date/number controls.
public struct LocalizedRoot<Content: View>: View {
    @ObservedObject private var settings = LanguageSettings.shared
    private let content: Content
    public init(_ content: Content) { self.content = content }
    public var body: some View { content.environment(\.locale, settings.language.locale) }
}

extension UsageStore {
    /// UI-only counterpart of displayLabel; storage and exports retain their
    /// original names, and user-supplied names never become translation keys.
    public func localizedDisplayLabel(for id: String, defaultLabel: String) -> String {
        if let name = customLabel(for: id) ?? wifiLabel(for: id) { return name }
        let name = L10n.defaultNetworkLabel(defaultLabel)
        return NetworkFingerprint.isUnidentified(id)
            ? L10n.text("\(name) · networks not told apart") : name
    }
}
