import SwiftUI

struct ScreenCornerView: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var configStore: ConfigStore
    @EnvironmentObject var engine: CornerDetectionEngine
    
    @State private var selectedScreenID: String? = nil
    @State private var activeSheet: Corner? = nil
    
    private let imageSize: CGFloat = 460
    
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
                
                // Corner buttons moved out away from the MacBook screen to the left and right sides
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        CornerButton(corner: .topLeft, screenID: selectedScreenID) {
                            activeSheet = .topLeft
                        }
                        Spacer()
                        CornerButton(corner: .topRight, screenID: selectedScreenID) {
                            activeSheet = .topRight
                        }
                    }
                    Spacer()
                    HStack(spacing: 0) {
                        CornerButton(corner: .bottomLeft, screenID: selectedScreenID) {
                            activeSheet = .bottomLeft
                        }
                        Spacer()
                        CornerButton(corner: .bottomRight, screenID: selectedScreenID) {
                            activeSheet = .bottomRight
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
                        .overlay(
                            Circle()
                                .stroke(
                                    cornerAction.isConfigured ? Color.accentColor : Color.secondary.opacity(0.5),
                                    style: StrokeStyle(lineWidth: 1.5, dash: cornerAction.isConfigured ? [] : [4])
                                )
                        )
                } else {
                    Circle()
                        .fill(colorScheme == .dark ? Color.black.opacity(0.4) : Color.white)
                        .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.12), radius: 3, x: 0, y: 1)
                        .frame(width: buttonSize, height: buttonSize)
                        .overlay(
                            Circle()
                                .stroke(
                                    cornerAction.isConfigured ? Color.accentColor : (colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.3)),
                                    style: StrokeStyle(lineWidth: 1.5, dash: cornerAction.isConfigured ? [] : [4])
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
        } else {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isHovering ? .accentColor : plusIdleColor)
                .animation(.easeInOut(duration: 0.2), value: isHovering)
                .accessibilityHidden(true)
        }
    }
    
    private var plusIdleColor: Color {
        if GlassSupport.isEnabled(configStore.config) {
            return .secondary.opacity(0.7)
        }
        return colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5)
    }
}
