import SwiftUI
import AppKit

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

    /// Pill/circle control background: explicit Liquid Glass on 26+, legacy
    /// ultra-thin material otherwise. Explicit `glassEffect` (rather than a
    /// glass button style) so the glass is always visible.
    @ViewBuilder
    func legacyPillBackground<S: Shape>(glass: Bool, shape: S) -> some View {
        self.background {
            if glass {
                if #available(macOS 26, *) {
                    shape.glassEffect(.regular, in: shape)
                }
            } else {
                shape.fill(.ultraThinMaterial)
            }
        }
    }

    /// Selected-option fill for dense lists (snap grid, system rows, category
    /// segments). Plain translucent fills — never glass-on-glass.
    func selectedOptionFill(selected: Bool, colorScheme: ColorScheme) -> Color {
        if selected {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.28 : 0.15)
        }
        return colorScheme == .dark ? Color.white.opacity(0.06) : Color.primary.opacity(0.05)
    }

    /// Detail-area container: glass card in glass mode, flat legacy card
    /// otherwise. Controls inside stay plain fills — no glass-on-glass.
    @ViewBuilder
    func detailChrome(glass: Bool, colorScheme: ColorScheme) -> some View {
        self
            .padding(12)
            .cardChrome(glass: glass, colorScheme: colorScheme)
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

/// Makes the hosting window transparent when glass is on so materials and
/// Liquid Glass sample the real wallpaper (over an opaque window they
/// flatten to dull gray with dark edges). Reverts when glass is off.
struct GlassWindowConfigurator: NSViewRepresentable {
    let enabled: Bool

    func makeNSView(context: Context) -> GlassWindowTuner {
        GlassWindowTuner(enabled: enabled)
    }

    func updateNSView(_ view: GlassWindowTuner, context: Context) {
        view.enabled = enabled
        view.tune()
    }
}

final class GlassWindowTuner: NSView {
    var enabled: Bool
    private var appliedFullSize = false

    init(enabled: Bool) {
        self.enabled = enabled
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        tune()
    }
    func tune() {
        guard let window else { return }
        // Sheets keep system chrome; only top-level titled windows change.
        let isMainWindow = window.parent == nil && window.styleMask.contains(.titled)
        if enabled, isMainWindow {
            // Solid black custom bar (drawn in content): hide the system
            // titlebar, which on Tahoe is Liquid Glass by design.
            var mask = window.styleMask
            mask.insert(.fullSizeContentView)
            window.styleMask = mask
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.title = ""
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            appliedFullSize = true
        } else {
            if appliedFullSize {
                var mask = window.styleMask
                mask.remove(.fullSizeContentView)
                window.styleMask = mask
                appliedFullSize = false
            }
            window.titlebarAppearsTransparent = false
            window.titleVisibility = .visible
            window.title = "LaunchCorner"
            window.isOpaque = !enabled
            window.backgroundColor = enabled ? .clear : .windowBackgroundColor
        }
    }
}
