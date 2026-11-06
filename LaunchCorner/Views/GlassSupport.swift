import SwiftUI

/// Liquid Glass (macOS 26+) helpers.
///
/// Every helper degrades to an identity operation when running on older
/// systems or when the user turned Liquid Glass off in Settings, so the
/// original look is preserved there.
enum GlassSupport {
    /// macOS 26+ availability, regardless of user preference.
    static var isAvailable: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    /// True only on macOS 26+ with the user preference enabled.
    static func isEnabled(_ config: AppConfig) -> Bool {
        if #available(macOS 26, *) {
            return config.useLiquidGlass
        }
        return false
    }
}

extension View {
    /// Window/content backdrop: translucent material on glass, legacy flat colors otherwise.
    @ViewBuilder
    func appBackdrop(glass: Bool, colorScheme: ColorScheme) -> some View {
        if glass {
            // Materials sample the wallpaper through the window; on Tahoe this reads as Liquid Glass.
            // (macOS 12+, so no availability gate needed; `glass` is only true on 26+.)
            self.background(.regularMaterial)
        } else {
            self.background(colorScheme == .dark ? Color(red: 0x24/255.0, green: 0x23/255.0, blue: 0x21/255.0) : Color(red: 0xF5/255.0, green: 0xF5/255.0, blue: 0xF7/255.0))
        }
    }

    /// Settings-card chrome: Liquid Glass on 26+, legacy white card otherwise.
    @ViewBuilder
    func cardChrome(glass: Bool, colorScheme: ColorScheme, darkFill: CGFloat = 0.04, darkStroke: CGFloat = 0.08) -> some View {
        if #available(macOS 26, *), glass {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
        } else {
            self
                .background(colorScheme == .dark ? Color.white.opacity(darkFill) : Color.white)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(colorScheme == .dark ? Color.white.opacity(darkStroke) : Color.black.opacity(0.08), lineWidth: 1)
                )
        }
    }

    /// Legacy pill/circle material background. Renders nothing when glass is on
    /// (the outer glass button style provides the chrome instead).
    @ViewBuilder
    func legacyPillBackground<S: Shape>(glass: Bool, shape: S) -> some View {
        if !glass {
            self.background(shape.fill(.ultraThinMaterial))
        } else {
            self
        }
    }

    /// Overrides the inner (legacy) button style with glass on 26+. No-op otherwise,
    /// so call sites keep their existing `.buttonStyle(...)` for older systems.
    @ViewBuilder
    func adaptiveGlassButton(glass: Bool, prominent: Bool = false) -> some View {
        if #available(macOS 26, *), glass {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            self
        }
    }
}
