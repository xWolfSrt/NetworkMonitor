import AppKit
import CoreText

/// Builds the status item's title: two stacked lines, download above upload.
///
/// Kept out of `AppDelegate` so the width-stability invariant can be measured in
/// the test suite: this is the one piece of the UI where a formatting mistake is
/// immediately visible as the whole menu bar twitching on every sample.
public enum MenuBarTitle {

    /// Compact glyph baselines let 10 pt semibold text fit two readable rows
    /// inside the menu bar without the padding of a multiline text container.
    static let fontSize: CGFloat = 10
    private static let lowerBaseline: CGFloat = 2
    private static let linePitch: CGFloat = 11

    /// Height budget for the status item, for the fit test.
    public static let menuBarHeight: CGFloat = 22

    /// Fully monospaced, deliberately not `monospacedDigitSystemFont`.
    ///
    /// The monospaced-*digit* variant fixes the width of digits only — letters
    /// and spaces keep their proportional advances, so "128 KB/s" and "0 B/s"
    /// render at different widths no matter how carefully the string is padded.
    /// A fully monospaced font makes equal character counts mean equal pixel
    /// widths, which is what the padding in `ByteFormat.menuBarRate` relies on.
    public static let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)

    /// Starting download palette for custom colours, `#51FF70`.
    /// The default live status item instead uses macOS template contrast.
    public static let downTint = NSColor(srgbRed: 0x51 / 255, green: 0xFF / 255,
                                         blue: 0x70 / 255, alpha: 1)
    /// Starting upload palette for custom colours, `#E5E5E5`.
    /// These fixed values remain available when a user explicitly picks colours.
    public static let upTint = NSColor(srgbRed: 0xE5 / 255, green: 0xE5 / 255,
                                       blue: 0xE5 / 255, alpha: 1)

    public static func downLine(_ bytesPerSecond: Double, unit: SpeedUnit = .bytes) -> String {
        "↓ \(ByteFormat.menuBarRate(bytesPerSecond, unit: unit))"
    }

    public static func upLine(_ bytesPerSecond: Double, unit: SpeedUnit = .bytes) -> String {
        "↑ \(ByteFormat.menuBarRate(bytesPerSecond, unit: unit))"
    }

    /// Tints while a speed test has the menu bar, so its figures — a capacity
    /// rather than what is moving, in the same unit as the live rates — are
    /// never mistaken for them. Same family as the download green, shifted to cyan.
    /// The first of `MenuBarTints.testChoices`, used unless the live colours
    /// come too close to it.
    public static let testDownTint = NSColor(srgbRed: 0x64 / 255, green: 0xD2 / 255,
                                             blue: 0xFF / 255, alpha: 1)
    public static let testUpTint = NSColor(srgbRed: 0xB4 / 255, green: 0xE9 / 255,
                                           blue: 0xFF / 255, alpha: 1)

    /// The two lines joined, download first. Rates are always passed in bytes
    /// per second; `unit` is only how they are written.
    public static func string(down: Double, up: Double, unit: SpeedUnit = .bytes) -> String {
        "\(downLine(down, unit: unit))\n\(upLine(up, unit: unit))"
    }

    /// The two lines, each tinted separately.
    public static func attributed(down: Double, up: Double, unit: SpeedUnit = .bytes,
                                  tints: MenuBarTints = .live) -> NSAttributedString {
        attributed(downLine(down, unit: unit), tints.down, upLine(up, unit: unit), tints.up)
    }

    /// A speed test's two lines, in the chosen unit, at the live title's exact
    /// width.
    public static func speedTestAttributed(downBits: Double, upBits: Double, unit: SpeedUnit = .bits,
                                           tints: MenuBarTints = MenuBarTints.testChoices[0])
        -> NSAttributedString {
        attributed("↓ \(ByteFormat.menuBarSpeed(downBits, unit: unit))", tints.down,
                   "↑ \(ByteFormat.menuBarSpeed(upBits, unit: unit))", tints.up)
    }

    private static func attributed(_ top: String, _ topTint: NSColor,
                                   _ bottom: String, _ bottomTint: NSColor) -> NSAttributedString {
        let paragraph = MenuBarTitle.paragraphStyle()
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(
            string: top + "\n",
            attributes: [.font: font, .paragraphStyle: paragraph,
                         .foregroundColor: topTint]))
        result.append(NSAttributedString(
            string: bottom,
            attributes: [.font: font, .paragraphStyle: paragraph,
                         .foregroundColor: bottomTint]))
        return result
    }

    private static func paragraphStyle() -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        // Left, not right. Right alignment makes CoreText discard trailing
        // whitespace when it aligns, which defeats the unit-field padding: a
        // "0 B/s " row (one trailing space) rendered a full character further
        // right than a "128 KB/s" row. The status item sizes itself to the
        // title, so alignment buys nothing and only introduces that shift.
        paragraph.alignment = .left
        // Natural leading, deliberately not a forced min/maximumLineHeight.
        // Clamping the line height to less than the font's ascent+descent
        // compressed the box and clipped the top line's ascenders.
        paragraph.lineSpacing = 0
        return paragraph
    }

    /// The title drawn into an image, which is what the status item displays.
    ///
    /// `NSButton` lays a multi-line attributed title out using single-line
    /// baseline assumptions and drew the block above its own bounds, clipping the
    /// top line's ascenders — at every font size tried, including ones whose
    /// measured height fit inside 22 pt. Drawing into a correctly sized image
    /// and letting the button centre that image removes the guesswork entirely.
    ///
    /// Automatic contrast uses a template mask so macOS chooses the menu bar's
    /// foreground, including wallpaper, appearance and highlighted-item changes.
    /// Explicit custom colours remain opaque, non-template images.
    public static func image(down: Double, up: Double, unit: SpeedUnit = .bytes,
                             tints: MenuBarTints = .live,
                             automaticContrast: Bool = false) -> NSImage {
        let palette = automaticContrast ? MenuBarTints(down: .black, up: .black) : tints
        let result = image(attributed(down: down, up: up, unit: unit, tints: palette))
        result.isTemplate = automaticContrast
        return result
    }

    /// The speed test's title, drawn exactly as the live one is.
    public static func speedTestImage(downBits: Double, upBits: Double, unit: SpeedUnit,
                                      tints: MenuBarTints = MenuBarTints.testChoices[0]) -> NSImage {
        image(speedTestAttributed(downBits: downBits, upBits: upBits, unit: unit, tints: tints))
    }

    private static func lines(_ text: NSAttributedString) -> [CTLine] {
        var start = 0
        return text.string.components(separatedBy: "\n").map { value in
            let range = NSRange(location: start, length: (value as NSString).length)
            start += range.length + 1
            return CTLineCreateWithAttributedString(text.attributedSubstring(from: range))
        }
    }

    private static func baseline(for index: Int) -> CGFloat {
        lowerBaseline + (index == 0 ? linePitch : 0)
    }

    private static func image(_ text: NSAttributedString) -> NSImage {
        let size = NSSize(width: ceil(text.size().width), height: menuBarHeight)
        let image = NSImage(size: size)
        image.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            context.textMatrix = .identity
            for (index, line) in lines(text).enumerated() {
                context.textPosition = CGPoint(x: 0, y: baseline(for: index))
                CTLineDraw(line, context)
            }
        }
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    /// Rendered width in points, for the width-stability test.
    public static func renderedWidth(down: Double, up: Double, unit: SpeedUnit = .bytes) -> Double {
        Double(attributed(down: down, up: up, unit: unit).size().width)
    }

    /// Rendered height in points, for the menu-bar-fit test.
    public static func renderedHeight(down: Double, up: Double) -> Double {
        let bounds = lines(attributed(down: down, up: up)).enumerated().map { index, line in
            CTLineGetImageBounds(line, nil).offsetBy(dx: 0, dy: baseline(for: index))
        }
        return Double(bounds.reduce(CGRect.null) { $0.union($1) }.height)
    }
}
