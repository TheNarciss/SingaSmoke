import SingaSmokeCore
import SwiftUI
import UIKit

/// The look: a muted map, white floating cards, black pill buttons, one green and one red.
enum Brand {
    static let accent = Color("AccentColor")
    static let accentUI = UIColor(named: "AccentColor") ?? .systemTeal
    /// Green of the places where smoking is allowed.
    static let allowed = Color(uiColor: allowedUI)
    static let allowedUI = UIColor(red: 0.05, green: 0.64, blue: 0.45, alpha: 1)     // #0DA373
    /// Red of the no-smoking zones.
    static let danger = Color(uiColor: dangerUI)
    static let dangerUI = UIColor(red: 1.0, green: 0.25, blue: 0.33, alpha: 1)       // #FF4054
    static let warning = Color(uiColor: warningUI)
    static let warningUI = UIColor(red: 1.0, green: 0.60, blue: 0.0, alpha: 1)       // #FF9900
    /// The yellow painted on the ground around a designated smoking area.
    static let boxYellowUI = UIColor(red: 0.98, green: 0.80, blue: 0.08, alpha: 1)    // #FACC15
    /// Card surfaces over the map: white in light mode, dark grey in dark mode.
    static let card = Color(.secondarySystemGroupedBackground)
    /// Opaque sheet backgrounds: the map must not show through the text.
    static let sheet = Color(.systemBackground)
    static let groupedSheet = Color(.systemGroupedBackground)
    /// Main buttons and the selected mode: near-black in light mode, white in dark mode. Solid colours,
    /// unlike `.primary`, which turns translucent on glass.
    static let ink = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .white : UIColor(white: 0.07, alpha: 1) })
    static let onInk = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .black : .white })
}

// MARK: - Surfaces

struct CardBackground: ViewModifier {
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(Brand.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 16, y: 6)
    }
}

extension View {
    /// A floating card over the map.
    func card(radius: CGFloat = 24) -> some View { modifier(CardBackground(radius: radius)) }
}

// MARK: - Buttons

/// Capsule buttons: black on light, white on dark (primary), grey (secondary), red (danger).
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, danger, allowed }
    var kind: Kind = .primary
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .subheadline.weight(.bold) : .headline)
            .lineLimit(1)
            .padding(.vertical, compact ? 9 : 15)
            .padding(.horizontal, compact ? 16 : 22)
            .frame(maxWidth: compact ? nil : .infinity)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return Brand.onInk
        case .secondary: return .primary
        case .danger, .allowed: return .white
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return Brand.ink
        case .secondary: return Color(.tertiarySystemFill)
        case .danger: return Brand.danger
        case .allowed: return Brand.allowed
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static func pill(_ kind: PillButtonStyle.Kind, compact: Bool = false) -> PillButtonStyle {
        PillButtonStyle(kind: kind, compact: compact)
    }
}

/// A round white button floating over the map.
struct FloatingButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 50
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
                .background(Brand.card, in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Small pieces

/// A coloured disc with a white symbol: the status icon, list icons, card icons.
struct IconCircle: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint, in: Circle())
            .accessibilityHidden(true)
    }
}

/// A short fact in a capsule: "6 min · 450 m", "Official", "Level 2".
struct Chip: View {
    let text: String
    var symbol: String?
    var tint: Color = .secondary
    var filled = false

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(filled ? Color.white : tint)
        .background(filled ? tint : tint.opacity(0.14), in: Capsule())
    }
}

extension WalkingDistance {
    /// "6 min · 450 m", with "≈" when estimated (but not before "< 1 min").
    var chipText: String {
        "\(isEstimate && seconds >= 30 ? "≈ " : "")\(Format.duration(seconds)) · \(Format.distance(meters))"
    }
}

/// What stays of a minimised card: a small capsule with its icon and a line or two. Tap to bring the card back.
struct CompactPill: View {
    let symbol: String
    let tint: Color
    let title: String
    var detail: String?
    /// Which way the card comes back from: "chevron.down" for the top, "chevron.up" for the bottom.
    var chevron = "chevron.down"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                IconCircle(symbol: symbol, tint: tint, size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                    if let detail {
                        Text(detail)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Image(systemName: chevron)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, 6)
            .padding(.trailing, 14)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .background(Brand.card, in: Capsule())
            .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the card again")
    }
}

extension View {
    /// Runs `action` on a mostly vertical swipe towards `edge`, without taking taps or horizontal drags away.
    func onVerticalSwipe(_ edge: VerticalEdge, perform action: @escaping () -> Void) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 16).onEnded { value in
                let dy = value.translation.height
                guard abs(dy) > 28, abs(dy) > abs(value.translation.width) * 1.5 else { return }
                if (edge == .top && dy < 0) || (edge == .bottom && dy > 0) { action() }
            }
        )
    }
}
