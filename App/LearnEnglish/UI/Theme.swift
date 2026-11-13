import SwiftUI

/// Colours and type of the #13 prototype, variant A ("卡片").
enum Theme {
    static let accent = Color(light: 0x2F6BFF, dark: 0x5B8CFF)
    static let accentSoft = Color(light: 0xE6EEFF, dark: 0x1C2740)
    static let good = Color(light: 0x1FA463, dark: 0x34C77B)
    static let bad = Color(light: 0xE5484D, dark: 0xFF6369)
    static let goodSoft = Color(light: 0xE3F6EC, dark: 0x14301F)
    static let badSoft = Color(light: 0xFDEAEA, dark: 0x3A1719)
    static let background = Color(light: 0xF4F5F8, dark: 0x0E1015)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1A1D24)
    static let line = Color(light: 0xE3E5EB, dark: 0x2A2E38)
    static let muted = Color(light: 0x7A7F8C, dark: 0x8B90A0)

    /// Rounded, tabular figures for every number on screen.
    static func number(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

extension Color {
    /// A colour that follows the system light/dark appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

extension Int {
    /// `6,375`
    var grouped: String { formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_US"))) }

    /// `+237` / `−42` / `±0`
    var signed: String { self > 0 ? "+\(grouped)" : self < 0 ? "−\((-self).grouped)" : "±0" }
}

/// Full-width primary button (the prototype's `.cta`).
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Rounded white section on the 进度 / 设置 tabs (the prototype's `.sec`).
struct Panel<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.muted)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
