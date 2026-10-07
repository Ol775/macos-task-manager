import SwiftUI
import AppKit

// MARK: - Accent themes

/// Interface accent (sidebar pill, buttons, selection). Each theme has a brighter colour for dark mode and a deeper one for
/// light mode; `Checks` verifies every pair against the WCAG contrast formula.
enum AccentTheme: String, CaseIterable, Identifiable {
    case ocean, teal, green, violet, rose, graphite, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .ocean: "Ocean blue"
        case .teal: "Teal"
        case .green: "Forest green"
        case .violet: "Violet"
        case .rose: "Rose"
        case .graphite: "Graphite"
        case .custom: "Custom"
        }
    }
    /// (dark-mode colour, light-mode colour)
    func colors(custom: String) -> (NSColor, NSColor) {
        func c(_ r: Double, _ g: Double, _ b: Double) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
        switch self {
        case .ocean: return (c(0.36, 0.67, 1.00), c(0.00, 0.37, 0.80))
        case .teal: return (c(0.25, 0.82, 0.82), c(0.00, 0.43, 0.46))
        case .green: return (c(0.30, 0.85, 0.52), c(0.07, 0.48, 0.24))
        case .violet: return (c(0.72, 0.58, 1.00), c(0.46, 0.22, 0.80))
        case .rose: return (c(1.00, 0.45, 0.65), c(0.77, 0.13, 0.38))
        case .graphite: return (c(0.78, 0.80, 0.84), c(0.30, 0.32, 0.36))
        case .custom:
            let base = NSColor(hexString: custom) ?? c(0.36, 0.67, 1.00)
            return (base.blended(withFraction: 0.18, of: .white) ?? base, base.blended(withFraction: 0.30, of: .black) ?? base)
        }
    }
}

/// Text size choice. Fonts, row heights and column widths all follow it (macOS has no system-wide Dynamic Type).
enum TextSize: String, CaseIterable, Identifiable {
    case small, standard, large, xlarge
    var id: String { rawValue }
    var label: String { switch self { case .small: "Small"; case .standard: "Standard"; case .large: "Large"; case .xlarge: "Extra large" } }
    var scale: CGFloat { switch self { case .small: 0.9; case .standard: 1; case .large: 1.15; case .xlarge: 1.3 } }
}

enum TextScale { static var factor: CGFloat = 1 }
/// A point size scaled by the Text size setting.
func ts(_ n: CGFloat) -> CGFloat { n * TextScale.factor }

enum CardCorners: String, CaseIterable, Identifiable {
    case sharp, standard, round
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var radius: CGFloat { switch self { case .sharp: 6; case .standard: 14; case .round: 22 } }
}

extension NSColor {
    convenience init?(hexString: String) {
        var h = hexString.trimmingCharacters(in: .whitespaces); if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
    }

    /// Dynamic colour: `dark` in dark appearances, `light` otherwise.
    static func dynamic(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }

    /// WCAG relative luminance.
    var luminance: Double {
        let s = usingColorSpace(.sRGB) ?? self
        func lin(_ v: CGFloat) -> Double { let d = Double(v); return d <= 0.03928 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(s.redComponent) + 0.7152 * lin(s.greenComponent) + 0.0722 * lin(s.blueComponent)
    }

    func contrast(on other: NSColor) -> Double {
        let a = luminance, b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

extension Color {
    /// A chart colour that stays readable on white cards: as picked in dark mode, deepened in light mode.
    static func metric(_ base: Color) -> Color {
        let n = NSColor(base)
        return Color(nsColor: .dynamic(dark: n, light: n.blended(withFraction: 0.28, of: .black) ?? n))
    }
}

// MARK: - Shared pieces

struct CardStyle: ViewModifier {
    @EnvironmentObject var s: AppSettings
    @Environment(\.colorSchemeContrast) private var contrast
    var padding: CGFloat = 0
    func body(content: Content) -> some View {
        let r = s.corners.radius
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: r, style: .continuous).fill(s.cardColor))
            .overlay(RoundedRectangle(cornerRadius: r, style: .continuous).stroke(contrast == .increased ? Color.primary.opacity(0.6) : (s.oled ? Color(white: 0.2) : Color(nsColor: .separatorColor)), lineWidth: contrast == .increased ? 1.5 : 1))
    }
}

extension View {
    func card(padding: CGFloat = 0) -> some View { modifier(CardStyle(padding: padding)) }
}

/// Large page title with a quiet subtitle, and room for controls on the right.
struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: ts(28), weight: .bold, design: .rounded)).accessibilityAddTraits(.isHeader)
                Text(subtitle).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

/// Circular gauge, drawn by hand so it takes the metric colour in both appearances.
struct RingGauge: View {
    let value: Double          // 0...100
    let color: Color
    var size: CGFloat = 120
    var line: CGFloat = 12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.10), lineWidth: line)
            Circle().trim(from: 0, to: CGFloat(min(max(value, 0), 100) / 100))
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90)).animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: value)
            VStack(spacing: 0) {
                Text(String(format: "%.0f%%", value)).font(.system(size: size * 0.26, weight: .bold, design: .rounded)).monospacedDigit()
                Text("used").font(.system(size: size * 0.10)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Utilisation").accessibilityValue(String(format: "%.0f percent", value))
    }
}

/// Thin capsule bar, drawn by hand (the system progress bar ignores a custom tint in dark mode).
struct CapsuleBar: View {
    let value: Double          // 0...1
    let color: Color
    var height: CGFloat = 6
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(color).frame(width: max(height, g.size.width * CGFloat(min(max(value, 0), 1))))
            }
        }.frame(height: height).accessibilityHidden(true)
    }
}

/// Segmented control in the accent colour (the selected segment is filled).
struct PillPicker<T: Hashable>: View {
    @EnvironmentObject var s: AppSettings
    @Binding var selection: T
    let options: [(T, String)]
    var label = ""
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, label in
                let on = selection == value
                Button { selection = value } label: {
                    Text(label).font(.system(size: ts(12.5), weight: .medium)).lineLimit(1).fixedSize()
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .background(Capsule().fill(on ? s.accentFill : Color.clear))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2).background(Capsule().fill(Color.primary.opacity(0.08))).fixedSize()
        .accessibilityElement(children: .contain).accessibilityLabel(label)
    }
}
