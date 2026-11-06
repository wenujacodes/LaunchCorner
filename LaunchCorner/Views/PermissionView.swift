import SwiftUI

struct PermissionView: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var permissionManager: PermissionManager
    @EnvironmentObject var configStore: ConfigStore
    
    private var glassEnabled: Bool { GlassSupport.isEnabled(configStore.config) }
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // App icon
            Image(systemName: "macwindow.on.rectangle")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.accentColor)
                .padding(.bottom, 20)
                .accessibilityHidden(true)
            
            // Title
            Text("Welcome to LaunchCorner")
                .font(.title)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .padding(.bottom, 8)
            
            // Subtitle
            Text("A hot corner utility for macOS")
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.bottom, 36)
            
            // Feature list
            VStack(alignment: .leading, spacing: 24) {
                featureRow(
                    icon: "cursorarrow.motionlines",
                    title: "Corner Detection",
                    description: "Launch apps by moving your cursor to screen corners"
                )
                
                featureRow(
                    icon: "display.2",
                    title: "Multi-Monitor",
                    description: "Works across all your connected displays"
                )
                
                featureRow(
                    icon: "gearshape",
                    title: "Customizable",
                    description: "Adjust sensitivity and dwell time"
                )
                
                featureRow(
                    icon: "lock.open",
                    title: "Accessibility Access",
                    description: "Required to detect cursor position globally"
                )
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            // Action button
            Button(action: {
                permissionManager.requestPermission()
                permissionManager.openAccessibilitySettings()
                permissionManager.startMonitoringPermission()
            }) {
                Text("Open System Settings")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(glassEnabled ? Color.primary : Color.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .background {
                        if glassEnabled {
                            if #available(macOS 26, *) {
                                Capsule().glassEffect(.regular, in: .capsule)
                            }
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.accentColor)
                        }
                    }
            }
            .buttonStyle(.plain)
            .padding(.bottom, 6)
            
            // Helper text
            Text("Grant Accessibility access to get started")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Spacer()
                .frame(height: 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            permissionManager.startMonitoringPermission()
        }
    }
    
    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.accentColor)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}
