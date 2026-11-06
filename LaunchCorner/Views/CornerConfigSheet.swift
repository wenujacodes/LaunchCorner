import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CornerConfigSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var configStore: ConfigStore

    let corner: Corner
    let screenID: String?

    private enum ConfigCategory: String, CaseIterable, Identifiable {
        case app, quickLink, command, window, system
        var id: String { rawValue }

        var title: String {
            switch self {
            case .app: return "App"
            case .quickLink: return "Quick Link"
            case .command: return "Script"
            case .window: return "Window"
            case .system: return "System"
            }
        }

        var symbolName: String {
            switch self {
            case .app: return "app.dashed"
            case .quickLink: return "link"
            case .command: return "doc.text"
            case .window: return "macwindow"
            case .system: return "bolt.fill"
            }
        }
    }

    @State private var selectedCategory: ConfigCategory = .app

    // App draft
    @State private var selectedAppPath: String = ""
    @State private var selectedAppName: String = ""
    @State private var selectedAppIcon: NSImage? = nil

    // Quick Link draft
    @State private var linkName: String = ""
    @State private var linkURL: String = ""
    @State private var linkOpenWithBundleID: String? = nil
    @State private var linkOpenWithName: String = ""

    // Command draft (script only)
    @State private var scriptLanguage: ScriptLanguage = .bash
    @State private var scriptPath: String = ""
    @State private var scriptDescription: String = ""

    // Window draft
    @State private var snapPosition: SnapPosition = .left
    @State private var windowTouched = false

    // System draft
    @State private var systemMode: Int = 0 // 0 = action, 1 = screenshot
    @State private var selectedSystemAction: SystemAction = .spotlight
    @State private var screenshotKind: ScreenshotKind = .full
    @State private var screenshotDestination: ScreenshotDestination = .clipboard
    @State private var screenshotDirectory: String = "~/Pictures"
    @State private var systemTouched = false

    // Snapshot at open: Save/Clear enable only when the draft differs from it,
    // so peeking at another category can never silently replace the stored action.
    @State private var initialAction: CornerAction = .none
    @State private var initialCategory: ConfigCategory = .app
    // Set only by the Clear button: clearing to "nothing" is always a valid,
    // deliberate save even though the resulting draft is .none.
    @State private var clearArmed = false
    // First-time setup gate: the user must set this corner to — in macOS
    // Hot Corners before configuring it here (prevents double triggers).
    @State private var hotCornerAck = false

    /// Direct link to System Settings → Desktop & Dock → Hot Corners.
    private static let hotCornersURL = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension?HotCorners")!

    private var glassEnabled: Bool { GlassSupport.isEnabled(configStore.config) }

    init(corner: Corner, screenID: String? = nil) {
        self.corner = corner
        self.screenID = screenID
    }

    var body: some View {
        VStack(spacing: 0) {
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
            .padding(.bottom, 12)

            // First-time gate: avoid double triggers with the system hot corner.
            if requiresHotCornerAck {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .accessibilityHidden(true)
                        Text("Set this corner to — in macOS Hot Corners first")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    Text("System Settings → Desktop & Dock → Hot Corners… — otherwise both actions fire at once.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        Button("Open Hot Corners…") {
                            NSWorkspace.shared.open(Self.hotCornersURL)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                        Spacer()
                        Toggle("This corner is set to —", isOn: $hotCornerAck)
                            .toggleStyle(.checkbox)
                    }
                }
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(colorScheme == .dark ? 0.22 : 0.12))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.45), lineWidth: 1)
                }
                .padding(.bottom, 12)
            }

            // Summary preview: what Save will persist
            summaryBlock
                .padding(.bottom, 16)

            sectionEyebrow("Category")
                .padding(.bottom, 6)

            // The single hero glass surface in glass mode; plain pills otherwise
            categorySelector
                .padding(.bottom, 16)

            sectionEyebrow("Details")
                .padding(.bottom, 6)

            // Detail area
            ScrollView {
                detailView
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.bottom, 12)

            Divider()
                .padding(.bottom, 12)

            // Footer
            HStack(spacing: 8) {
                Button("Clear") {
                    clearDraft()
                    clearArmed = true
                }
                .font(.system(size: 13))
                .foregroundColor(.red)
                // Enabled whenever there is something to clear (stored action)
                // or unsaved edits — never grayed out on a configured corner.
                .disabled(!isDirty && initialAction == .none)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    saveAction()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .adaptiveGlassButton(glass: glassEnabled, prominent: true)
                .disabled(!isDraftValid || !isDirty)
                .frame(minWidth: 72)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(width: 520, height: 600)
        .appBackdrop(glass: glassEnabled, colorScheme: colorScheme)
        .onAppear {
            loadCurrentConfig()
        }
    }

    // MARK: - Summary preview

    /// What the preview (and Save) represents: the draft once it is both
    /// valid and dirty, otherwise the stored action.
    private var previewedAction: CornerAction {
        (isDraftValid && isDirty) ? draftAction : initialAction
    }

    @ViewBuilder
    private var summaryBlock: some View {
        if glassEnabled {
            summaryRow
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
        } else {
            summaryRow
                .padding(12)
                .cardChrome(glass: false, colorScheme: colorScheme)
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 12) {
            previewIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(previewedAction.isConfigured ? previewedAction.displayName : "Nothing chosen")
                    .font(.headline)
                    .lineLimit(1)
                if previewedAction.isConfigured {
                    Text(previewedAction.detailText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(initialAction.isConfigured ? "Editing will replace this action" : "Pick a category below")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .frame(minHeight: 60, alignment: .leading)
    }

    private func sectionEyebrow(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    @ViewBuilder
    private var previewIcon: some View {
        if case .launchApp = previewedAction, let icon = previewedAction.appIcon() {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
        } else if previewedAction.isConfigured {
            Image(systemName: previewedAction.symbolName)
                .font(.system(size: 20))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.accentColor)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 20))
                .foregroundColor(.secondary)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Category selector

    @ViewBuilder
    private var categorySelector: some View {
        if glassEnabled {
            segmentRow
                .padding(3)
                .cardChrome(glass: true, colorScheme: colorScheme)
        } else {
            segmentRow
        }
    }

    private var segmentRow: some View {
        HStack(spacing: 2) {
            ForEach(ConfigCategory.allCases) { category in
                // Explicit tap target (not Button): the whole segment rect must
                // respond, including unselected segments with no background.
                VStack(spacing: 3) {
                    Image(systemName: category.symbolName)
                        .font(.system(size: 16))
                        .accessibilityHidden(true)
                    Text(category.title)
                        .font(.caption)
                        .fontWeight(selectedCategory == category ? .semibold : .medium)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .padding(.horizontal, 2)
                .foregroundColor(segmentForeground(for: category))
                .background {
                    if glassEnabled {
                        if #available(macOS 26, *), selectedCategory == category {
                            RoundedRectangle(cornerRadius: 9)
                                .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.30 : 0.16))
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(selectedOptionFill(selected: selectedCategory == category, colorScheme: colorScheme))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { selectedCategory = category }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAddTraits(selectedCategory == category ? .isSelected : [])
                .accessibilityAction { selectedCategory = category }
                .help(category.title)
            }
        }
    }

    private func segmentForeground(for category: ConfigCategory) -> Color {
        guard selectedCategory == category else {
            // Unselected recedes on glass; legacy keeps full primary.
            return glassEnabled ? .secondary : .primary
        }
        return .accentColor
    }

    // MARK: - Detail area

    @ViewBuilder
    private var detailView: some View {
        switch selectedCategory {
        case .app:
            appDetail
        case .quickLink:
            quickLinkDetail
        case .command:
            commandDetail
        case .window:
            windowDetail
        case .system:
            systemDetail
        }
    }

    // MARK: App detail (original behavior)

    private var appDetail: some View {
        VStack(spacing: 16) {
            if !selectedAppName.isEmpty {
                HStack(spacing: 12) {
                    if let icon = selectedAppIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 44, height: 44)
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
                    Text("Nothing chosen")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
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
            .help("Pick the application launched by the \(corner.displayName) corner")
        }
    }

    // MARK: Quick Link detail

    private var quickLinkDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Name (optional)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("My link", text: $linkName)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("URL")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("https://…, shortcuts://…, ~/path", text: $linkURL)
                    .textFieldStyle(.roundedBorder)
                    .help("URL, shortcut URL, or file path to open")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Open with (optional)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    Text(linkOpenWithName.isEmpty ? "Default app" : linkOpenWithName)
                        .font(.body)
                        .foregroundColor(linkOpenWithName.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer()
                    Button(linkOpenWithName.isEmpty ? "Choose..." : "Change...") {
                        selectOpenWithApp()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    if !linkOpenWithName.isEmpty {
                        Button("Clear") {
                            linkOpenWithBundleID = nil
                            linkOpenWithName = ""
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                    }
                }
                .padding(10)
            }
        }
        .detailChrome(glass: glassEnabled, colorScheme: colorScheme)
    }

    // MARK: Command detail

    private var commandDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Language")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Language", selection: $scriptLanguage) {
                    ForEach(ScriptLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.menu)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Script file")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    Text(scriptPath.isEmpty ? "No file chosen" : scriptPath)
                        .font(.caption)
                        .foregroundColor(scriptPath.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(scriptPath.isEmpty ? "Choose..." : "Change...") {
                        selectScript()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
                Text("Runs in the background; output goes to the log.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Description (optional)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("What does this script do?", text: $scriptDescription)
                    .textFieldStyle(.roundedBorder)
            }
            interpreterStatusLine(for: scriptLanguage)
        }
        .detailChrome(glass: glassEnabled, colorScheme: colorScheme)
    }

    @ViewBuilder
    private func interpreterStatusLine(for language: ScriptLanguage) -> some View {
        if let found = interpreterPath(for: language) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .accessibilityHidden(true)
                Text(found)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .accessibilityHidden(true)
                Text("Not installed — \(interpreterHint(for: language))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: Window detail

    private var windowDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(SnapPosition.allCases) { position in
                    HStack(spacing: 8) {
                        Image(systemName: position.symbolName)
                            .font(.system(size: 16))
                            .foregroundColor(snapPosition == position ? .accentColor : .secondary)
                            .accessibilityHidden(true)
                        Text(position.displayName)
                            .font(.body)
                            .fontWeight(snapPosition == position ? .semibold : .regular)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(10)
                    .background {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(selectedOptionFill(selected: snapPosition == position, colorScheme: colorScheme))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(snapPosition == position ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08),
                                    lineWidth: snapPosition == position ? 1.5 : 1)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        snapPosition = position
                        windowTouched = true
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAddTraits(snapPosition == position ? .isSelected : [])
                    .accessibilityAction {
                        snapPosition = position
                        windowTouched = true
                    }
                    .help(position.detailText)
                }
            }
            Text(snapPosition.detailText)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 2)
        }
        .detailChrome(glass: glassEnabled, colorScheme: colorScheme)
    }

    // MARK: System detail

    private var systemDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Type", selection: $systemMode) {
                Text("System Action").tag(0)
                Text("Screenshot").tag(1)
            }
            .pickerStyle(.segmented)
            .onChange(of: systemMode) { _, _ in systemTouched = true }

            if systemMode == 0 {
                VStack(spacing: 2) {
                    ForEach(Array(SystemAction.allCases.enumerated()), id: \.element) { index, action in
                        if index > 0 {
                            Divider()
                                .padding(.horizontal, 10)
                        }
                        HStack(spacing: 10) {
                            Image(systemName: action.symbolName)
                                .font(.system(size: 14))
                                .foregroundColor(selectedSystemAction == action ? .accentColor : .secondary)
                                .frame(width: 22)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(action.displayName)
                                    .font(.body)
                                    .fontWeight(selectedSystemAction == action ? .semibold : .regular)
                                    .foregroundColor(.primary)
                                Text(action.detailText)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if selectedSystemAction == action {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                                    .accessibilityHidden(true)
                            }
                        }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedOptionFill(selected: selectedSystemAction == action, colorScheme: colorScheme))
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedSystemAction = action
                                systemTouched = true
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAddTraits(selectedSystemAction == action ? .isSelected : [])
                            .accessibilityAction {
                                selectedSystemAction = action
                                systemTouched = true
                            }
                            .help(action.detailText)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Kind")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("Kind", selection: $screenshotKind) {
                            ForEach(ScreenshotKind.allCases) { kind in
                                Text(kind.displayName).tag(kind)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Destination")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("Destination", selection: $screenshotDestination) {
                            ForEach(ScreenshotDestination.allCases) { destination in
                                Text(destination.displayName).tag(destination)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text("Requires Screen Recording access (asked on first capture).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if screenshotDestination == .file {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Directory")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack {
                                Text(screenshotDirectory)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button("Choose...") {
                                    selectScreenshotDirectory()
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }
        }
        .detailChrome(glass: glassEnabled, colorScheme: colorScheme)
    }

    // MARK: - Draft model

    private var draftAction: CornerAction {
        switch selectedCategory {
        case .app:
            if selectedAppPath.isEmpty {
                return .none
            }
            return .launchApp(bundlePath: selectedAppPath, appName: selectedAppName)
        case .quickLink:
            if linkURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .none
            }
            return .quickLink(name: linkName, url: linkURL, openWithBundleID: linkOpenWithBundleID)
        case .command:
            if scriptPath.isEmpty {
                return .none
            }
            return .script(language: scriptLanguage, path: scriptPath, description: scriptDescription)
        case .window:
            // Untouched default must not count: merely peeking at the tab
            // must never arm an overwrite of the stored action.
            if !windowTouched {
                return .none
            }
            return .windowSnap(position: snapPosition)
        case .system:
            if !systemTouched {
                return .none
            }
            if systemMode == 0 {
                return .systemAction(selectedSystemAction)
            }
            return .screenshot(kind: screenshotKind, destination: screenshotDestination, directory: screenshotDirectory)
        }
    }

    private var isDirty: Bool {
        clearArmed
            || selectedCategory != initialCategory
            || draftAction != initialAction
    }

    /// First-time corners must acknowledge the macOS Hot Corners check.
    private var requiresHotCornerAck: Bool { initialAction == .none }

    private var isDraftValid: Bool {
        // First-time setup: the macOS corner must be set to — first.
        if requiresHotCornerAck && !hotCornerAck {
            return false
        }
        switch selectedCategory {
        case .app:
            // Empty app is only valid as an explicit clear (Clear button);
            // peeking at the App tab must never arm an overwrite with .none.
            return !selectedAppPath.isEmpty || clearArmed
        case .quickLink:
            return !linkURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .command:
            return !scriptPath.isEmpty
        case .window:
            return windowTouched
        case .system:
            return systemTouched
        }
    }

    private func interpreterPath(for language: ScriptLanguage) -> String? {
        ShellExecutor.resolveInterpreter(language)
    }

    private func interpreterHint(for language: ScriptLanguage) -> String {
        switch language {
        case .bash:
            return "built in"
        case .appleScript:
            return "built in (osascript)"
        case .python:
            return "install via Xcode Command Line Tools"
        case .javaScript:
            return "install node via brew: brew install node"
        case .typeScript:
            return "install tsx via brew: brew install tsx"
        case .go:
            return "install go via brew: brew install go"
        case .ruby:
            return "built in (/usr/bin/ruby)"
        case .csharp:
            return "install dotnet-script via brew"
        }
    }

    // MARK: - Load / save

    private func clearDraft() {
        selectedCategory = .app
        windowTouched = false
        systemTouched = false
        selectedAppPath = ""
        selectedAppName = ""
        selectedAppIcon = nil
        linkName = ""
        linkURL = ""
        linkOpenWithBundleID = nil
        linkOpenWithName = ""
        scriptLanguage = .bash
        scriptPath = ""
        scriptDescription = ""
        snapPosition = .left
        systemMode = 0
        selectedSystemAction = .spotlight
        screenshotKind = .full
        screenshotDestination = .clipboard
        screenshotDirectory = "~/Pictures"
    }

    private func loadCurrentConfig() {
        let config = configStore.cornerConfig(forScreenID: screenID)
        let action = config.action(for: corner)

        switch action {
        case .none:
            clearDraft()
        case .launchApp(let path, let name):
            clearDraft()
            selectedCategory = .app
            selectedAppPath = path
            selectedAppName = name
            selectedAppIcon = action.appIcon()
        case .quickLink(let name, let url, let openWithBundleID):
            clearDraft()
            selectedCategory = .quickLink
            linkName = name
            linkURL = url
            linkOpenWithBundleID = openWithBundleID
            linkOpenWithName = ""
            if let bundleID = openWithBundleID {
                let appURL: URL? = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                if let appURL {
                    linkOpenWithName = FileManager.default.displayName(atPath: appURL.path)
                } else {
                    linkOpenWithName = bundleID
                }
            }
        case .script(let language, let path, let description):
            clearDraft()
            selectedCategory = .command
            scriptLanguage = language
            scriptPath = path
            scriptDescription = description
        case .windowSnap(let position):
            clearDraft()
            selectedCategory = .window
            snapPosition = position
        case .systemAction(let systemAction):
            clearDraft()
            selectedCategory = .system
            systemMode = 0
            selectedSystemAction = systemAction
        case .screenshot(let kind, let destination, let directory):
            clearDraft()
            selectedCategory = .system
            systemMode = 1
            screenshotKind = kind
            screenshotDestination = destination
            screenshotDirectory = directory.isEmpty ? "~/Pictures" : directory
        }

        // Snapshot for dirty-tracking (Save/Clear arm only on real changes).
        // Touched flags stay false here: tapping is what arms window/system.
        initialAction = action
        switch action {
        case .none, .launchApp:
            initialCategory = .app
        case .quickLink:
            initialCategory = .quickLink
        case .script:
            initialCategory = .command
        case .windowSnap:
            initialCategory = .window
        case .systemAction, .screenshot:
            initialCategory = .system
        }
    }

    private func saveAction() {
        configStore.setCornerAction(draftAction, for: corner, screenID: screenID)
        configStore.save()
    }

    // MARK: - Pickers

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

    private func selectOpenWithApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            // Bundle identifier can be nil for non-bundle apps; the name is
            // still shown but saving falls back to the default handler.
            linkOpenWithBundleID = Bundle(url: url)?.bundleIdentifier
            linkOpenWithName = FileManager.default.displayName(atPath: url.path)
        }
    }

    private func selectScript() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            scriptPath = url.path
        }
    }

    private func selectScreenshotDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            screenshotDirectory = url.path
        }
    }
}
