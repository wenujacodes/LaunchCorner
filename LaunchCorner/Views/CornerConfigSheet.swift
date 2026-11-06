import SwiftUI
import UniformTypeIdentifiers

struct CornerConfigSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var configStore: ConfigStore
    
    let corner: Corner
    let screenID: String?
    
    @State private var selectedAppPath: String = ""
    @State private var selectedAppName: String = ""
    @State private var selectedAppIcon: NSImage? = nil
    
    private var glassEnabled: Bool { GlassSupport.isEnabled(configStore.config) }
    
    init(corner: Corner, screenID: String? = nil) {
        self.corner = corner
        self.screenID = screenID
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Header with SF Symbol
            HStack(spacing: 12) {
                Image(systemName: corner.symbolName)
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.accentColor)
                    .accessibilityHidden(true)
                Text("\(corner.displayName) Configuration")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.bottom, 4)
            
            // App Selection area
            VStack(spacing: 16) {
                if !selectedAppName.isEmpty {
                    HStack(spacing: 16) {
                        if let icon = selectedAppIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 48, height: 48)
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 48, height: 48)
                                .overlay(Image(systemName: "questionmark.app.dashed").foregroundColor(.secondary))
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedAppName)
                                .font(.headline)
                            Text(selectedAppPath)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                    }
                    .padding()
                    .cardChrome(glass: glassEnabled, colorScheme: colorScheme, darkFill: 0.06, darkStroke: 0.1)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                            .accessibilityHidden(true)
                        Text("No application selected")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .cardChrome(glass: glassEnabled, colorScheme: colorScheme)
                }
                
                Button(action: selectApp) {
                    Text(selectedAppName.isEmpty ? "Choose Application..." : "Change Application...")
                        .font(.body)
                        .fontWeight(.medium)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .foregroundColor(.accentColor)
                        .background {
                            if !glassEnabled {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.accentColor.opacity(0.15))
                            }
                        }
                }
                .buttonStyle(.plain)
                .tint(.accentColor)
                .adaptiveGlassButton(glass: glassEnabled)
                .help("Pick the application launched by the \(corner.displayName) corner")
            }
            
            Spacer()
            
            // Footer
            HStack {
                Button("Clear") {
                    selectedAppPath = ""
                    selectedAppName = ""
                    selectedAppIcon = nil
                }
                .foregroundColor(.red)
                .disabled(selectedAppPath.isEmpty)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Save") {
                    saveAction()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .adaptiveGlassButton(glass: glassEnabled, prominent: true)
            }
        }
        .padding(28)
        .frame(width: 440, height: 320)
        .appBackdrop(glass: glassEnabled, colorScheme: colorScheme)
        .onAppear {
            loadCurrentConfig()
        }
    }
    
    private func loadCurrentConfig() {
        let config = configStore.cornerConfig(forScreenID: screenID)
        let action = config.action(for: corner)
        
        switch action {
        case .none:
            selectedAppPath = ""
            selectedAppName = ""
            selectedAppIcon = nil
        case .launchApp(let path, let name):
            selectedAppPath = path
            selectedAppName = name
            selectedAppIcon = action.appIcon()
        }
    }
    
    private func saveAction() {
        let newAction: CornerAction
        if !selectedAppPath.isEmpty {
            newAction = .launchApp(bundlePath: selectedAppPath, appName: selectedAppName)
        } else {
            newAction = .none
        }
        configStore.setCornerAction(newAction, for: corner, screenID: screenID)
        configStore.save()
    }
    
    private func selectApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        
        if panel.runModal() == .OK, let url = panel.url {
            selectedAppPath = url.path
            selectedAppName = url.deletingPathExtension().lastPathComponent
            let workspace = NSWorkspace.shared
            selectedAppIcon = workspace.icon(forFile: url.path)
        }
    }
}
