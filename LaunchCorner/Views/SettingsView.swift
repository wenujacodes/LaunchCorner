import SwiftUI

struct SettingsView: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var configStore: ConfigStore
    @EnvironmentObject var permissionManager: PermissionManager
    @EnvironmentObject var updateManager: UpdateManager
    
    var onBack: () -> Void
    
    @State private var showingResetAlert = false
    
    private var glassEnabled: Bool { GlassSupport.isEnabled(configStore.config) }
    
    private var enableLaunchCornerBinding: Binding<Bool> {
        Binding(
            get: { configStore.config.isActive },
            set: { newValue in
                configStore.config.isActive = newValue
                configStore.save()
            }
        )
    }
    
    private var autoCheckUpdatesBinding: Binding<Bool> {
        Binding(
            get: { configStore.config.autoCheckUpdates },
            set: { newValue in
                configStore.config.autoCheckUpdates = newValue
                configStore.save()
            }
        )
    }
    
    private var dwellTimeBinding: Binding<Double> {
        Binding(
            get: { configStore.config.dwellTime },
            set: { newValue in
                configStore.config.dwellTime = newValue
                configStore.save()
            }
        )
    }
    
    private var liquidGlassBinding: Binding<Bool> {
        Binding(
            get: { configStore.config.useLiquidGlass },
            set: { newValue in
                configStore.config.useLiquidGlass = newValue
                configStore.save()
            }
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Left Title (Matching original screenshot)
            HStack {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 16)
            
            ScrollView {
                VStack(spacing: 24) {
                    // General
                    VStack(alignment: .leading, spacing: 10) {
                        Text("General")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        VStack(spacing: 12) {
                            HStack {
                                Text("Enable LaunchCorner")
                                    .font(.body)
                                Spacer()
                                Toggle("", isOn: enableLaunchCornerBinding)
                                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                                    .controlSize(.small)
                                    .labelsHidden()
                            }
                            
                            Divider()
                            
                            HStack {
                                Text("Launch at Login")
                                    .font(.body)
                                Spacer()
                                Toggle("", isOn: $configStore.isLaunchAtLoginEnabled)
                                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                                    .controlSize(.small)
                                    .labelsHidden()
                            }
                        }
                        .padding(14)
                        .cardChrome(glass: glassEnabled, colorScheme: colorScheme)
                    }
                    
                    // Appearance (Liquid Glass needs macOS 26+)
                    if GlassSupport.isAvailable {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Appearance")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Liquid Glass")
                                        .font(.body)
                                    Text("Translucent glass interface")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: liquidGlassBinding)
                                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                                    .controlSize(.small)
                                    .labelsHidden()
                                    .help("Use the Liquid Glass look. Turn off to keep the classic appearance.")
                            }
                            .padding(14)
                            .cardChrome(glass: glassEnabled, colorScheme: colorScheme)
                        }
                    }
                    
                    // Sensitivity
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sensitivity")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Dwell Time")
                                    .font(.body)
                                Spacer()
                                Text(configStore.config.dwellTime <= 0.01 ? "Instant (0 ms)" : String(format: "%.0f ms", configStore.config.dwellTime * 1000))
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                            }
                            
                            Slider(value: dwellTimeBinding, in: 0.0...0.5, step: 0.05)
                            
                            Text("How long the cursor rests in a corner before triggering. Set to 0 ms for instant response.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(14)
                        .cardChrome(glass: glassEnabled, colorScheme: colorScheme)
                    }
                    
                    // Updates
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Updates")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        VStack(spacing: 12) {
                            HStack {
                                Text("Automatically check for updates")
                                    .font(.body)
                                Spacer()
                                Toggle("", isOn: autoCheckUpdatesBinding)
                                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                                    .controlSize(.small)
                                    .labelsHidden()
                            }
                            
                            Divider()
                            
                            HStack {
                                Text("Software Update")
                                    .font(.body)
                                Spacer()
                                Button("Check Now") {
                                    updateManager.checkForUpdates()
                                }
                                .buttonStyle(.bordered)
                                .adaptiveGlassButton(glass: glassEnabled)
                                .help("Check for software updates now")
                            }
                        }
                        .padding(14)
                        .cardChrome(glass: glassEnabled, colorScheme: colorScheme)
                    }
                    
                    // App
                    VStack(alignment: .leading, spacing: 10) {
                        Text("App")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        VStack(spacing: 12) {
                            HStack {
                                Text("Quit LaunchCorner")
                                    .font(.body)
                                Spacer()
                                Button("Quit App") {
                                    NSApp.terminate(nil)
                                }
                                .buttonStyle(.bordered)
                                .adaptiveGlassButton(glass: glassEnabled)
                                .help("Quit LaunchCorner")
                            }
                            
                            Divider()
                            
                            HStack {
                                Text("Reset All Configurations & Permissions")
                                    .font(.body)
                                Spacer()
                                Button("Reset") {
                                    showingResetAlert = true
                                }
                                .foregroundColor(.red)
                                .buttonStyle(.bordered)
                                .adaptiveGlassButton(glass: glassEnabled)
                                .help("Reset all corner assignments and preferences")
                            }
                        }
                        .padding(14)
                        .cardChrome(glass: glassEnabled, colorScheme: colorScheme)
                    }
                    
                    // About
                    VStack(alignment: .leading, spacing: 10) {
                        Text("About")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        VStack(spacing: 12) {
                            HStack {
                                Text("Version")
                                    .font(.body)
                                Spacer()
                                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                            
                            Divider()
                            
                            Link(destination: URL(string: "https://github.com/wenujacodes/LaunchCorner/issues")!) {
                                HStack {
                                    Text("Report an Issue")
                                        .font(.body)
                                        .foregroundColor(.accentColor)
                                    Spacer()
                                    Image(systemName: "bubble.left.and.bubble.right")
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Divider()
                            
                            Link(destination: URL(string: "https://github.com/wenujacodes/LaunchCorner")!) {
                                HStack {
                                    Text("GitHub")
                                        .font(.body)
                                        .foregroundColor(.accentColor)
                                    Spacer()
                                    Image(systemName: "arrow.up.right.square")
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Divider()
                            
                            Link(destination: URL(string: "https://x.com/wenujatweets")!) {
                                HStack {
                                    Text("X (Twitter)")
                                        .font(.body)
                                        .foregroundColor(.accentColor)
                                    Spacer()
                                    Image(systemName: "arrow.up.right.square")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(14)
                        .cardChrome(glass: glassEnabled, colorScheme: colorScheme)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBackdrop(glass: glassEnabled, colorScheme: colorScheme)
        .alert("Reset All Configurations?", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Everything", role: .destructive) {
                configStore.resetAllCorners()
                permissionManager.isAccessibilityGranted = false
                permissionManager.openAccessibilitySettings()
            }
        } message: {
            Text("This will clear all corner assignments, reset preferences, and return LaunchCorner to setup. This cannot be undone.")
        }
    }
}
