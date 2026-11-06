import SwiftUI

struct MainView: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var configStore: ConfigStore
    @EnvironmentObject var permissionManager: PermissionManager
    @EnvironmentObject var engine: CornerDetectionEngine
    
    @State private var showingSettings = false
    
    private var glassEnabled: Bool { GlassSupport.isEnabled(configStore.config) }
    
    /// Floating toolbar control (Back in Settings, gear on main screen).
    /// Rendered as an overlay so it takes no layout space.
    @ViewBuilder
    private var toolbarButton: some View {
        if showingSettings {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showingSettings = false
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .legacyPillBackground(glass: glassEnabled, shape: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to corner setup")
            .help("Back to corner setup")
        } else {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showingSettings = true
                }
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.secondary)
                    .frame(width: 30, height: 30)
                    .legacyPillBackground(glass: glassEnabled, shape: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Settings")
            .help("Open Settings (⌘,)")
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Hidden button to catch Cmd+, shortcut
            Button("") {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showingSettings.toggle()
                }
            }
            .keyboardShortcut(",", modifiers: .command)
            .hidden()
            .frame(width: 0, height: 0)
            
            // Content (toolbar floats above it, taking no layout space)
            Group {
                if !permissionManager.isAccessibilityGranted {
                    PermissionView()
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else if showingSettings {
                    SettingsView(onBack: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showingSettings = false
                        }
                    })
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
                } else {
                    ScreenCornerView()
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showingSettings)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: permissionManager.isAccessibilityGranted)
        }
        .overlay(alignment: .topTrailing) {
            if permissionManager.isAccessibilityGranted {
                toolbarButton
                    .padding(.trailing, 16)
                    .padding(.top, 8)
            }
        }
        .background(GlassWindowConfigurator(enabled: glassEnabled))
        .frame(width: 660, height: 540)
        .appBackdrop(glass: glassEnabled, colorScheme: colorScheme)
        // Match the window's rounded mask: square content pixels fringing
        // past the corner curve read as a white seam on transparent windows.
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear {
            if permissionManager.isAccessibilityGranted && configStore.config.isActive {
                engine.start()
            }
        }
    }
}
