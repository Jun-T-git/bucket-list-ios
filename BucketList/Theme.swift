import SwiftUI
import UIKit

// Design tokens transcribed from styles/tokens.css.
// Paper + green base; sun (yellow) and peach (coral) are decorative accents.
// All tokens resolve dynamically per UITraitCollection so the app adapts to
// Light / Dark appearance without a hard switch.
enum Theme {
    enum Color {
        // Paper — inverts to deep paper greens in dark mode so the page still
        // reads as "ground" rather than UIKit-default near-black.
        static let paper0 = SwiftUI.Color(light: 0xFFFFFF, dark: 0x12201A)
        static let paper1 = SwiftUI.Color(light: 0xFAFCFA, dark: 0x141F18)
        static let paper2 = SwiftUI.Color(light: 0xF1F5F2, dark: 0x1B2620)
        static let paper3 = SwiftUI.Color(light: 0xE4EBE6, dark: 0x24322B)
        static let paper4 = SwiftUI.Color(light: 0xCBD6CE, dark: 0x35463C)

        // Ink — text family. Inverts toward warm off-white in dark.
        static let ink0 = SwiftUI.Color(light: 0x0F1A12, dark: 0xF0F4F1)
        static let ink1 = SwiftUI.Color(light: 0x2F3A33, dark: 0xD5DCD7)
        static let ink2 = SwiftUI.Color(light: 0x5F6A62, dark: 0x9CA8A0)
        // Darkened from 0x97A29B so meaningful muted text (counts, dim chips)
        // clears a usable contrast ratio; ink3Soft remains for pure decoration.
        static let ink3 = SwiftUI.Color(light: 0x7E8A82, dark: 0x8A968F)
        static let ink3Soft = SwiftUI.Color(light: 0xB3BDB6, dark: 0x5E6B65)

        // Hairline / separator that stays visible in BOTH appearances. A flat
        // black line (the previous Color.black.opacity approach) vanishes on the
        // dark page, so dark mode uses a faint white instead. Apply directly —
        // the per-mode alpha is baked in.
        static let hairline = SwiftUI.Color(light: 0x0F1A12, lightAlpha: 0.10,
                                            dark: 0xFFFFFF, darkAlpha: 0.14)
        // Slightly stronger variant for card / control outlines.
        static let cardBorder = SwiftUI.Color(light: 0x0F1A12, lightAlpha: 0.14,
                                              dark: 0xFFFFFF, darkAlpha: 0.18)

        // Green — structural hue. Slightly brighter in dark to keep contrast.
        static let green50  = SwiftUI.Color(light: 0xEEF7F1, dark: 0x0F2A1B)
        static let green100 = SwiftUI.Color(light: 0xD5EBDC, dark: 0x1A3D28)
        static let green200 = SwiftUI.Color(light: 0xB3DCC0, dark: 0x28583D)
        static let green300 = SwiftUI.Color(light: 0x7AC495, dark: 0x53A47A)
        static let green500 = SwiftUI.Color(light: 0x2E8855, dark: 0x55C087)
        static let green700 = SwiftUI.Color(light: 0x195A37, dark: 0x83D9AC)
        static let green900 = SwiftUI.Color(light: 0x0A2A1A, dark: 0xCDEED9)

        // Sun / Peach accents — decorative only. Toned for dark backgrounds.
        static let sun100  = SwiftUI.Color(light: 0xFFF1C2, dark: 0x3A2E10)
        static let sun300  = SwiftUI.Color(light: 0xFFDC6E, dark: 0xC9A035)
        static let sun500  = SwiftUI.Color(light: 0xF5C04A, dark: 0xE3B04A)
        static let sun700  = SwiftUI.Color(light: 0xC99312, dark: 0xFFD466)
        static let peach100 = SwiftUI.Color(light: 0xFFE3D6, dark: 0x3A2218)
        static let peach300 = SwiftUI.Color(light: 0xFFB89C, dark: 0x945236)
        static let peach500 = SwiftUI.Color(light: 0xFF9B7A, dark: 0xCB7257)
        static let peach700 = SwiftUI.Color(light: 0xD96A4A, dark: 0xFF9477)

        // Page background — radial wash on top of paper1. The dark value sits a
        // step below paper0 (the card surface) so cards read as raised above the
        // ground; a black shadow can't do that separation on a dark page.
        static let pageBackground = SwiftUI.Color(light: 0xFAFCFA, dark: 0x0C1510)
    }

    enum Font {
        // The design calls for Zen Maru Gothic / Zen Kaku Gothic New / Klee One /
        // JetBrains Mono. We map to system equivalents so the app builds without
        // bundling fonts. Drop the .ttf files in the bundle and switch to
        // .custom("Zen Maru Gothic", size:) when ready.
        // All roles resolve to the standard system font (San Francisco), and
        // every fixed design size is scaled with Dynamic Type via UIFontMetrics
        // — mapped to the closest built-in text style so the growth curve
        // matches the rest of iOS. Call sites keep passing a plain (size, weight)
        // and get accessibility text sizing for free. SwiftUI re-renders on a
        // content-size-category trait change, so the scaled value tracks the
        // user's setting live.
        private static func textStyle(for size: CGFloat) -> UIFont.TextStyle {
            switch size {
            case ..<13: return .caption1
            case ..<15: return .footnote
            case ..<17: return .subheadline
            case ..<20: return .body
            case ..<24: return .title3
            case ..<30: return .title2
            default:    return .title1
            }
        }
        private static func scaledSize(_ size: CGFloat) -> CGFloat {
            UIFontMetrics(forTextStyle: textStyle(for: size)).scaledValue(for: size)
        }
        static func display(_ size: CGFloat, weight: SwiftUI.Font.Weight = .bold) -> SwiftUI.Font {
            .system(size: scaledSize(size), weight: weight, design: .default)
        }
        static func sans(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .system(size: scaledSize(size), weight: weight, design: .default)
        }
        static func hand(_ size: CGFloat) -> SwiftUI.Font {
            .system(size: scaledSize(size), weight: .regular, design: .default)
        }
        static func mono(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .system(size: scaledSize(size), weight: weight, design: .default)
        }
    }
}

extension Color {
    // Hex initializer kept for any one-off uses outside Theme.Color.
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }

    // Dynamic Color that resolves per trait collection. Used by Theme.Color
    // so every token automatically adapts to Light / Dark.
    init(light: UInt32, dark: UInt32) {
        self.init(light: light, lightAlpha: 1.0, dark: dark, darkAlpha: 1.0)
    }

    // Per-appearance color with a per-appearance alpha, so a token can be a
    // faint line in light and a (differently-faint) line in dark.
    init(light: UInt32, lightAlpha: Double = 1.0, dark: UInt32, darkAlpha: Double = 1.0) {
        let dynamic = UIColor { trait in
            let isDark = trait.userInterfaceStyle == .dark
            let hex = isDark ? dark : light
            let a = isDark ? darkAlpha : lightAlpha
            let r = CGFloat((hex >> 16) & 0xFF) / 255.0
            let g = CGFloat((hex >> 8) & 0xFF) / 255.0
            let b = CGFloat(hex & 0xFF) / 255.0
            return UIColor(red: r, green: g, blue: b, alpha: CGFloat(a))
        }
        self = Color(uiColor: dynamic)
    }
}

// Common shadow profiles used across cards / stickers / floats.
extension View {
    func paperShadow() -> some View {
        self.shadow(color: .black.opacity(0.04), radius: 0, x: 0, y: 1)
            .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
    }
    func stickerShadow() -> some View {
        self.shadow(color: .black.opacity(0.05), radius: 0, x: 0, y: 1)
            .shadow(color: .black.opacity(0.05), radius: 14, x: 0, y: 6)
    }
    func floatShadow() -> some View {
        self.shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
            .shadow(color: .black.opacity(0.08), radius: 24, x: 0, y: 8)
    }

    // Glassmorphism for genuinely floating chrome (tab bar, selection icons).
    // iOS 26+: the real Liquid Glass (edge refraction + specular highlights).
    // Older OS: a frosted ultraThin Material with a hairline rim as a fallback.
    @ViewBuilder
    func glass<S: InsettableShape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.45), lineWidth: 0.8))
        }
    }
}

// MARK: - Haptics
// Thin wrapper around UIKit feedback generators. Generators are kept as
// statics so we don't re-instantiate per call — prepare() is cheap but
// gratuitous if repeated. Use Haptics.tap() for buttons, Haptics.select()
// for tab/segment changes, Haptics.success()/warning() for state changes.
enum Haptics {
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let medImpact   = UIImpactFeedbackGenerator(style: .medium)
    private static let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private static let selectionGen = UISelectionFeedbackGenerator()
    private static let notify = UINotificationFeedbackGenerator()

    static func light()   { lightImpact.impactOccurred() }
    static func medium()  { medImpact.impactOccurred() }
    static func tap()     { rigidImpact.impactOccurred(intensity: 0.7) }
    static func select()  { selectionGen.selectionChanged() }
    static func success() { notify.notificationOccurred(.success) }
    static func warning() { notify.notificationOccurred(.warning) }
    static func error()   { notify.notificationOccurred(.error) }
}
