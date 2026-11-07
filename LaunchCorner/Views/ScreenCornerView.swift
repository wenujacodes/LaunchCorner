import SwiftUI

struct ScreenCornerView: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var configStore: ConfigStore
    @EnvironmentObject var engine: CornerDetectionEngine
    
    @State private var selectedScreenID: String? = nil
    @State private var activeSheet: Corner? = nil
    @State private var pendingCorner: Corner? = nil
    @State private var showingHotCornerGate = false
    
    private let imageSize: CGFloat = 460
    
    /// Opens the config sheet only when the macOS system corner is disabled;
    /// otherwise pops an alert sending the user to Hot Corners settings.
    /// Edges have no macOS counterpart, so they open directly.
    private func requestConfigure(_ corner: Corner) {
        if corner.isEdge || MacOSHotCorners.isDisabled(corner) {
            activeSheet = corner
        } else {
            pendingCorner = corner
            showingHotCornerGate = true
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            if NSScreen.screens.count > 1 {
                Picker("Monitor", selection: $selectedScreenID) {
                    Text("All Screens").tag(String?.none)
                    ForEach(NSScreen.screens, id: \.self) { screen in
                        Text(screen.localizedName).tag(String?.some(screen.localizedName))
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 250)
                .help("Choose which display this setup applies to")
            }
            
            ZStack {
                // MacBook image as background
                Image("mac-screen")
                    .resizable()
                    .frame(width: imageSize, height: imageSize)
                
                // Corner buttons moved out away from the MacBook screen to the left and right sides.
                // Edge buttons sit between the corners: top centered in the top row,
                // left/right centered in a middle row.
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        CornerButton(corner: .topLeft, screenID: selectedScreenID) {
                            requestConfigure(.topLeft)
                        }
                        Spacer()
                        EdgeButton(corner: .topEdge, screenID: selectedScreenID) {
                            requestConfigure(.topEdge)
                        }
                        .offset(y: -24)
                        Spacer()
                        CornerButton(corner: .topRight, screenID: selectedScreenID) {
                            requestConfigure(.topRight)
                        }
                    }
                    Spacer()
                    HStack(spacing: 0) {
                        EdgeButton(corner: .leftEdge, screenID: selectedScreenID) {
                            requestConfigure(.leftEdge)
                        }
                        .frame(width: 42, alignment: .center)
                        Spacer()
                        EdgeButton(corner: .rightEdge, screenID: selectedScreenID) {
                            requestConfigure(.rightEdge)
                        }
                        .frame(width: 42, alignment: .center)
                    }
                    Spacer()
                    HStack(spacing: 0) {
                        CornerButton(corner: .bottomLeft, screenID: selectedScreenID) {
                            requestConfigure(.bottomLeft)
                        }
                        Spacer()
                        CornerButton(corner: .bottomRight, screenID: selectedScreenID) {
                            requestConfigure(.bottomRight)
                        }
                    }
                }
                // Top padding 0.350 aligns top buttons with top corners of display
                // Horizontal padding 0.050 moves buttons far out to the left and right sides away from screen
                .padding(.top, imageSize * 0.350)
                .padding(.bottom, imageSize * 0.160)
                .padding(.horizontal, imageSize * 0.050)
            }
            .frame(width: imageSize, height: imageSize)
            .offset(y: -60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $activeSheet) { corner in
            CornerConfigSheet(corner: corner, screenID: selectedScreenID)
        }
        .alert("Disable the macOS Hot Corner first", isPresented: $showingHotCornerGate) {
            Button("Cancel", role: .cancel) {
                pendingCorner = nil
            }
            Button("Open Hot Corners…") {
                NSWorkspace.shared.open(MacOSHotCorners.settingsURL)
            }
            Button("I've Disabled It") {
                // Re-detect: the dock defaults may have lagged, so a re-tap
                // also rechecks. Only opens the sheet when truly disabled.
                if let corner = pendingCorner, MacOSHotCorners.isDisabled(corner) {
                    activeSheet = corner
                    pendingCorner = nil
                } else {
                    // Still enabled: re-present the alert after dismissal.
                    DispatchQueue.main.async {
                        showingHotCornerGate = true
                    }
                }
            }
        } message: {
            Text("This corner is still assigned in macOS (System Settings → Desktop & Dock → Hot Corners…). Set it to — first, otherwise both actions fire at once.")
        }
    }
}

struct CornerButton: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var configStore: ConfigStore
    @EnvironmentObject var engine: CornerDetectionEngine
    
    let corner: Corner
    let screenID: String?
    let action: () -> Void
    
    @State private var isHovering = false
    
    private let buttonSize: CGFloat = 42
    
    var body: some View {
        let screenConfig = configStore.cornerConfig(forScreenID: screenID)
        let cornerAction = screenConfig.action(for: corner)
        let glass = GlassSupport.isEnabled(configStore.config)
        
        Button(action: action) {
            ZStack {
                if #available(macOS 26, *), glass {
                    Circle()
                        .fill(.clear)
                        .frame(width: buttonSize, height: buttonSize)
                        .glassEffect(.regular, in: .circle)
                } else {
                    Circle()
                        .fill(colorScheme == .dark ? Color.black.opacity(0.4) : Color.white)
                        .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.12), radius: 3, x: 0, y: 1)
                        .frame(width: buttonSize, height: buttonSize)
                        .overlay(
                            Circle()
                                .stroke(
                                    cornerAction.isConfigured ? Color.accentColor : (colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.3)),
                                    // 16 × (4.25 + 4) = 132 ≈ 2π×21: divides the circumference
                                    // evenly so the seam dash matches the rest.
                                    style: StrokeStyle(lineWidth: 1.5, dash: cornerAction.isConfigured ? [] : [4.25, 4])
                                )
                        )
                }
                
                cornerGlyph(for: cornerAction)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Configure \(corner.displayName) corner")
        .help("Configure \(corner.displayName) corner")
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    @ViewBuilder
    private func cornerGlyph(for cornerAction: CornerAction) -> some View {
        if cornerAction.isConfigured, let icon = cornerAction.appIcon() {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
        } else if cornerAction != .none {
            Image(systemName: cornerAction.symbolName)
                .font(.system(size: 14, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(isHovering ? .accentColor : plusIdleColor)
                .animation(.easeInOut(duration: 0.2), value: isHovering)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isHovering ? .accentColor : plusIdleColor)
                .animation(.easeInOut(duration: 0.2), value: isHovering)
                .accessibilityHidden(true)
        }
    }
    
    private var plusIdleColor: Color {
        colorScheme == .dark ? .white : .black
    }
}

/// Rectangular trigger for a screen edge: horizontally long for top/bottom,
/// vertical and thin for left/right.
struct EdgeButton: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var configStore: ConfigStore
    @EnvironmentObject var engine: CornerDetectionEngine

    let corner: Corner
    let screenID: String?
    let action: () -> Void

    @State private var isHovering = false

    /// Horizontal edge spans wide; vertical edges run tall and narrow.
    private var isHorizontal: Bool {
        corner == .topEdge
    }

    private var buttonWidth: CGFloat { isHorizontal ? 300 : 26 }
    private var buttonHeight: CGFloat { isHorizontal ? 26 : 110 }

    var body: some View {
        let screenConfig = configStore.cornerConfig(forScreenID: screenID)
        let edgeAction = screenConfig.action(for: corner)
        let glass = GlassSupport.isEnabled(configStore.config)
        let shape = RoundedRectangle(cornerRadius: 10)

        Button(action: action) {
            ZStack {
                if #available(macOS 26, *), glass {
                    shape
                        .fill(.clear)
                        .frame(width: buttonWidth, height: buttonHeight)
                        .glassEffect(.regular, in: shape)
                } else {
                    shape
                        .fill(colorScheme == .dark ? Color.black.opacity(0.4) : Color.white)
                        .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.12), radius: 3, x: 0, y: 1)
                        .frame(width: buttonWidth, height: buttonHeight)
                        .overlay(
                            shape
                                .stroke(
                                    edgeAction.isConfigured ? Color.accentColor : (colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.3)),
                                    style: StrokeStyle(lineWidth: 1.5, dash: edgeAction.isConfigured ? [] : [4.25, 4])
                                )
                        )
                }

                edgeGlyph(for: edgeAction)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Configure \(corner.displayName) edge")
        .help("Configure \(corner.displayName) edge")
        .onHover { hovering in
            isHovering = hovering
        }
    }

    @ViewBuilder
    private func edgeGlyph(for edgeAction: CornerAction) -> some View {
        if edgeAction.isConfigured, let icon = edgeAction.appIcon() {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
        } else if edgeAction != .none {
            Image(systemName: edgeAction.symbolName)
                .font(.system(size: 13, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(isHovering ? .accentColor : plusIdleColor)
                .animation(.easeInOut(duration: 0.2), value: isHovering)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isHovering ? .accentColor : plusIdleColor)
                .animation(.easeInOut(duration: 0.2), value: isHovering)
                .accessibilityHidden(true)
        }
    }

    private var plusIdleColor: Color {
        colorScheme == .dark ? .white : .black
    }
}
