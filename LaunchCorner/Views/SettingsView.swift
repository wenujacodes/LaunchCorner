import SwiftUI

struct SettingsView: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var configStore: ConfigStore
    @EnvironmentObject var permissionManager: PermissionManager
    @EnvironmentObject var updateManager: UpdateManager
    
    var onBack: () -> Void
    
    @State private var showingResetAlert = false
    
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
                        .background(colorScheme == .dark ? Color.white.opacity(0.04) : Color.white)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08), lineWidth: 1)
                        )
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
                        .background(colorScheme == .dark ? Color.white.opacity(0.04) : Color.white)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08), lineWidth: 1)
                        )
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
                            }
                        }
                        .padding(14)
                        .background(colorScheme == .dark ? Color.white.opacity(0.04) : Color.white)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08), lineWidth: 1)
                        )
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
                            }
                        }
                        .padding(14)
                        .background(colorScheme == .dark ? Color.white.opacity(0.04) : Color.white)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08), lineWidth: 1)
                        )
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
                        .background(colorScheme == .dark ? Color.white.opacity(0.04) : Color.white)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colorScheme == .dark ? Color(red: 0x24/255.0, green: 0x23/255.0, blue: 0x21/255.0) : Color(red: 0xF5/255.0, green: 0xF5/255.0, blue: 0xF7/255.0))
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
