import SwiftUI

// MARK: - Minidisc Design Tokens

public enum MinidiscColors {
    
    // MARK: — Accent
    public static let accent = Color("MinidiscAccent")

    public static let accentBackground = Color("MinidiscAccentBackground")

    public static let accentForeground = Color("MinidiscAccentForeground")

    // MARK: — Backgrounds
    public static let backgroundPrimary = Color("MinidiscBackgroundPrimary")

    public static let backgroundSecondary = Color("MinidiscBackgroundSecondary")

    public static let backgroundTertiary = Color("MinidiscBackgroundTertiary")

    // MARK: — Text
    public static let textPrimary = Color("MinidiscTextPrimary")

    public static let textSecondary = Color("MinidiscTextSecondary")

    public static let textTertiary = Color("MinidiscTextTertiary")

    // MARK: — Structure
    public static let separator = Color("MinidiscSeparator")

    public static let border = Color("MinidiscBorder")
    
    // MARK: — Accent Ramp (raw gold stops from the 💽 icon's disc, light-mode only — gradients, artwork tints, brand chips).
    public enum AccentRamp {
        public static let v50  = Color(hex: "#FDF5E2")
        public static let v100 = Color(hex: "#FBE8BB")
        public static let v200 = Color(hex: "#F4D07C")
        public static let v300 = Color(hex: "#E9B337")
        public static let v400 = Color(hex: "#D59C18")
        public static let v500 = Color(hex: "#926A0C") // brand chip base — keeps white legible (~4.9:1)
        public static let v600 = Color(hex: "#7A5706")
        public static let v700 = Color(hex: "#624605")
        public static let v800 = Color(hex: "#4A3504")
        public static let v900 = Color(hex: "#302203")
    }
}

// MARK: - Color(hex:) helper
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// AccentColor mirrors MinidiscAccent. Apply branded tints locally, not at WindowGroup,
// so secondary actions and alerts retain their contextual appearance.
