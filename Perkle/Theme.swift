import SwiftUI

// MARK: - Palette & type

/// The "Sticker" look: off-black ink outlines, hard offset shadows,
/// one loud accent colour and a rounded display face.
enum Theme {
    static let ink = Color(hex: 0x16161D)
    static let ink2 = Color(hex: 0x3A3A44)
    static let muted = Color(hex: 0x5A5A66)
    static let faint = Color(hex: 0x8A8A96)
    static let hairline = Color(hex: 0xC5C8D2)
    static let line = Color(hex: 0xECEEF2)
    static let soft = Color(hex: 0xF4F6FB)
    static let cream = Color(hex: 0xFFF1C9)
    static let sun = Color(hex: 0xFFC93C)
    static let cheek = Color(hex: 0xFFD0BF)
    static let good = Color(hex: 0x1F7A50)
    static let paper = Color.white

    /// Headlines and buttons. SF Pro Rounded stands in for Fredoka and ships with macOS.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static let outline: CGFloat = 3
    static let shadowOffset: CGFloat = 6
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

// MARK: - Sticker card

struct StickerCard: ViewModifier {
    var radius: CGFloat = 22
    var fill: Color = Theme.paper
    var shadow: CGFloat = Theme.shadowOffset
    var lineWidth: CGFloat = Theme.outline

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    if shadow > 0 {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(Theme.ink)
                            .offset(x: shadow, y: shadow)
                    }
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(fill)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Theme.ink, lineWidth: lineWidth)
                }
            }
    }
}

extension View {
    func stickerCard(radius: CGFloat = 22,
                     fill: Color = Theme.paper,
                     shadow: CGFloat = Theme.shadowOffset,
                     lineWidth: CGFloat = Theme.outline) -> some View {
        modifier(StickerCard(radius: radius, fill: fill, shadow: shadow, lineWidth: lineWidth))
    }
}

// MARK: - Buttons

struct StickerButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost }

    var kind: Kind = .primary
    var accent: Color
    var fullWidth = false
    var height: CGFloat = 40

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shadow: CGFloat = kind == .primary ? 3 : 0
        return configuration.label
            .font(kind == .primary ? Theme.display(16, .semibold) : Theme.body(14, .semibold))
            .foregroundStyle(kind == .ghost ? Theme.muted : Theme.ink)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
            .background {
                if kind != .ghost {
                    ZStack {
                        if shadow > 0 {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Theme.ink)
                                .offset(x: pressed ? 0 : shadow, y: pressed ? 0 : shadow)
                        }
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(kind == .primary ? accent : Theme.paper)
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Theme.ink, lineWidth: Theme.outline)
                    }
                }
            }
            .offset(x: pressed ? shadow : 0, y: pressed ? shadow : 0)
            .opacity(kind == .ghost && pressed ? 0.6 : 1)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

/// Small selectable pill (interval presets, weekdays).
struct ChipButtonStyle: ButtonStyle {
    var selected: Bool
    var accent: Color
    var circle = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: circle ? 20 : 12, style: .continuous)
        return configuration.label
            .font(Theme.body(13, .semibold))
            .foregroundStyle(selected ? Theme.ink : Theme.ink2)
            .padding(.horizontal, circle ? 0 : 14)
            .frame(width: circle ? 40 : nil, height: 40)
            .background {
                ZStack {
                    if selected {
                        shape.fill(Theme.ink).offset(x: 3, y: 3)
                    }
                    shape.fill(selected ? accent : Theme.paper)
                    shape.strokeBorder(selected ? Theme.ink : Theme.hairline,
                                       lineWidth: selected ? Theme.outline : 2)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .contentShape(shape)
    }
}

// MARK: - Toggle

struct StickerToggleStyle: ToggleStyle {
    var accent: Color

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                configuration.label
                    .font(Theme.body(13, .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? accent : Theme.soft)
                    Capsule().strokeBorder(Theme.ink, lineWidth: 2.5)
                    Circle()
                        .fill(Theme.paper)
                        .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 2))
                        .frame(width: 18, height: 18)
                        .padding(4)
                }
                .frame(width: 46, height: 26)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isOn)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

// MARK: - Small helpers

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.body(13, .semibold))
            .foregroundStyle(Theme.ink)
    }
}

struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.body(11, .semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.muted)
    }
}

/// One "stand" token: filled for done, dashed for still to do.
struct StandToken: View {
    var filled: Bool
    var accent: Color
    var width: CGFloat = 14
    var height: CGFloat = 18

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: width / 2, style: .continuous)
        ZStack {
            if filled {
                shape.fill(accent)
                shape.strokeBorder(Theme.ink, lineWidth: 2)
            } else {
                shape.fill(Theme.paper)
                shape.strokeBorder(Theme.faint, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
            }
        }
        .frame(width: width, height: height)
    }
}
