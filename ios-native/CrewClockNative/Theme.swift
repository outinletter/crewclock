import SwiftUI

extension Color {
    init(light: Color, dark: Color) {
        self = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }
    static let ccBlue = Color(light: Color(red: 0.23, green: 0.48, blue: 0.84), dark: Color(red: 0.36, green: 0.64, blue: 1.0))
    static let ccBlueSoft = Color(light: Color(red: 0.86, green: 0.92, blue: 1.0), dark: Color(red: 0.10, green: 0.23, blue: 0.37))
    static let ccBackground = Color(light: Color(red: 0.957, green: 0.969, blue: 0.992), dark: Color(red: 0.04, green: 0.10, blue: 0.18))
    static let ccCard = Color(light: .white, dark: Color(red: 0.07, green: 0.16, blue: 0.27))
    static let ccInk = Color(light: Color(red: 0.11, green: 0.17, blue: 0.27), dark: Color(red: 0.89, green: 0.93, blue: 0.97))
    static let ccMuted = Color(light: Color(red: 0.36, green: 0.42, blue: 0.49), dark: Color(red: 0.62, green: 0.70, blue: 0.78))
    static let ccMint = Color(light: Color(red: 0.18, green: 0.62, blue: 0.54), dark: Color(red: 0.17, green: 0.72, blue: 0.64))
    static let ccMintSoft = Color(light: Color(red: 0.88, green: 0.96, blue: 0.94), dark: Color(red: 0.08, green: 0.25, blue: 0.24))
    static let ccGround = Color(light: Color(red: 0.62, green: 0.71, blue: 0.84), dark: Color(red: 0.37, green: 0.47, blue: 0.58))
    static let ccSand = Color(red: 0.80, green: 0.69, blue: 0.45)
}

struct Card<Content: View>: View {
    var tint: Color = .ccCard
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(tint, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct SectionLabel: View {
    let text: String
    var color: Color = .ccMuted
    init(_ text: String, color: Color = .ccMuted) { self.text = text; self.color = color }
    var body: some View {
        Text(text.uppercased()).font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(color)
    }
}

extension View {
    func screenBackground() -> some View {
        background(Color.ccBackground.ignoresSafeArea())
    }
}
