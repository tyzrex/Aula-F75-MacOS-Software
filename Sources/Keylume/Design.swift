import SwiftUI
import KeylumeKit

// MARK: - Cards and headers

/// A rounded, softly bordered container used throughout the app.
struct Card<Content: View>: View {
    var title: String?
    var subtitle: String?
    var systemImage: String?
    /// Fill the height of a grid row so neighbouring cards line up.
    var stretch = false
    @ViewBuilder var content: Content

    init(_ title: String? = nil, subtitle: String? = nil, systemImage: String? = nil, stretch: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title; self.subtitle = subtitle; self.systemImage = systemImage; self.stretch = stretch; self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if title != nil || subtitle != nil {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let systemImage { Image(systemName: systemImage).foregroundStyle(.secondary) }
                    VStack(alignment: .leading, spacing: 2) {
                        if let title { Text(title).font(.headline) }
                        if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 0)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: stretch ? .infinity : nil, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
    }
}

/// Page scaffold: a large title, an optional subtitle and scrolling content.
struct Screen<Content: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }, @ViewBuilder content: () -> Content) {
        self.title = title; self.subtitle = subtitle; self.trailing = trailing(); self.content = content()
    }

    @Environment(\.flatLayout) private var flat

    var body: some View {
        if flat { page } else { ScrollView { page }.background(Color(nsColor: .windowBackgroundColor)) }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.largeTitle.weight(.bold))
                        if let subtitle { Text(subtitle).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    trailing
                }
                content
        }
        .padding(.horizontal, 24).padding(.vertical, 20)
        .frame(maxWidth: 1100, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: flat ? .infinity : nil, alignment: .top)
    }
}

private struct FlatLayoutKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// True when rendering to an image: ScrollViews don't draw there, so pages lay out flat.
    var flatLayout: Bool { get { self[FlatLayoutKey.self] } set { self[FlatLayoutKey.self] = newValue } }
}

/// A small capsule with an icon and text, used for status in toolbars and cards.
struct Pill: View {
    var text: String
    var systemImage: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 9).padding(.vertical, 4)
        .foregroundStyle(tint)
        .background(Capsule().fill(tint.opacity(0.14)))
    }
}

/// A banner for things the user should know before acting (read-only connection, demo mode, errors).
struct Banner: View {
    var systemImage: String
    var text: String
    var tint: Color = .orange
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(tint.opacity(0.25)))
    }
}

/// A label and a control in one row with a fixed label column.
struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var control: Control
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            .frame(width: 150, alignment: .leading)
            control
        }
    }
}

// MARK: - Colors

extension RGB {
    var color: Color { Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1) }
    init(_ c: Color) {
        let ns = NSColor(c).usingColorSpace(.sRGB) ?? .white
        self.init(Int((ns.redComponent * 255).rounded()), Int((ns.greenComponent * 255).rounded()), Int((ns.blueComponent * 255).rounded()))
    }
    /// Perceived brightness, to pick a readable label color.
    var luminance: Double { (0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)) / 255 }
}

// MARK: - Effects

extension Effect {
    /// An SF Symbol that hints at what the effect looks like.
    var symbol: String {
        switch hw {
        case 1: return "circle.fill"
        case 2: return "waveform.path"
        case 3: return "rainbow"
        case 4: return "bolt.fill"
        case 5: return "cloud.rain"
        case 6: return "arrow.triangle.2.circlepath"
        case 7: return "circle.circle"
        case 8: return "sparkles"
        case 9: return "snowflake"
        case 10: return "water.waves"
        case 11: return "wind"
        case 12: return "moon.fill"
        case 13: return "waveform"
        case 15: return "fanblades"
        case 16: return "arrow.left.arrow.right"
        case 17: return "arrow.down.to.line"
        default: return "paintpalette"
        }
    }
    var reactsToKeys: Bool { Effects.reactive.contains(hw) }
}

extension LiveAnimation {
    var symbol: String {
        switch self {
        case .rainbowWave: return "rainbow"
        case .aurora: return "wand.and.stars"
        case .fire: return "flame.fill"
        case .matrixRain: return "chevron.down.2"
        case .sparkle: return "sparkles"
        case .pulse: return "waveform.path.ecg"
        case .scanner: return "arrow.left.arrow.right"
        case .themeFlow: return "paintbrush.pointed.fill"
        }
    }
}

/// A grid of selectable tiles (effects, animations).
struct Tile: View {
    var title: String
    var systemImage: String
    var selected: Bool
    var badge: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage).font(.title3).frame(height: 24)
                Text(title).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 1))
            .overlay(alignment: .topTrailing) {
                if let badge { Text(badge).font(.system(size: 9, weight: .bold)).padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Capsule().fill(Color.orange.opacity(0.85))).foregroundStyle(.white).padding(4) }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Color.accentColor : Color.primary)
    }
}
