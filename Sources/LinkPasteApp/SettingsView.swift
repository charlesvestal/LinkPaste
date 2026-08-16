import LinkPasteCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var permissions: PermissionsMonitor

    var body: some View {
        Form {
            PermissionsSection(permissions: permissions)
            BehaviorSection(settings: settings)
            DenylistSection(settings: settings)
            MarkdownListSection(settings: settings)
            LastPasteSection(settings: settings)
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, idealWidth: 480, minHeight: 380, idealHeight: 560)
    }
}

// MARK: - Permissions

private struct PermissionsSection: View {
    @ObservedObject var permissions: PermissionsMonitor

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                // Status is carried by the text, not only by the icon's color, so it
                // survives both VoiceOver and color-blind viewing.
                Label(
                    permissions.isTrusted ? "Accessibility access granted" : "Accessibility access required",
                    systemImage: permissions.isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(permissions.isTrusted ? Color.green : Color.orange)

                if !permissions.isTrusted {
                    Explanation("LinkPaste can't see ⌘V without it. If link pasting stops working, check here first — macOS drops this permission when an app's signing identity changes.")

                    HStack {
                        Button("Open Privacy Settings") { permissions.openSettings() }
                        Button("Request Access") { permissions.requestAccess() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Permissions")
        } header: {
            Text("Permissions")
        }
    }
}

// MARK: - Behavior

private struct BehaviorSection: View {
    @ObservedObject var settings: Settings

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable link pasting", isOn: $settings.isEnabled)

                launchAtLogin

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Use ⌘C fallback to detect selection", isOn: $settings.allowsCopyProbe)
                    Explanation("Required for browsers, Slack, and Notion — they don't report the selection any other way. Turn it off if you'd rather no synthetic ⌘C is ever sent.")
                }

                restoreDelay
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Behavior")
        } header: {
            Text("Behavior")
        }
    }

    private var launchAtLogin: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Launch at login", isOn: Binding(
                get: { settings.launchesAtLogin },
                set: { settings.setLaunchAtLogin($0) }
            ))
            if let failure = settings.launchAtLoginFailure {
                Label("Couldn't change this: \(failure)", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var restoreDelay: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Clipboard restore delay")

            HStack(spacing: 12) {
                // The label is hidden visually (it's shown above, where it has
                // room) but `labelsHidden` keeps it for VoiceOver, so the slider
                // still announces what it adjusts.
                Slider(
                    value: Binding(
                        get: { Double(settings.restoreDelayMilliseconds) },
                        set: { settings.restoreDelayMilliseconds = Int($0) }
                    ),
                    in: Double(Settings.delayRange.lowerBound)...Double(Settings.delayRange.upperBound),
                    step: 25
                ) {
                    Text("Clipboard restore delay")
                }
                .labelsHidden()
                // Without this VoiceOver reads a bare percentage, which says
                // nothing about what is actually being set.
                .accessibilityValue("\(settings.restoreDelayMilliseconds) milliseconds")

                Text("\(settings.restoreDelayMilliseconds) ms")
                    .monospacedDigit()
                    .frame(width: 64, alignment: .trailing)
                    .accessibilityHidden(true)  // the slider already announces it
            }

            Explanation("How long to wait before restoring your clipboard. If a slow app pastes your previous clipboard instead of the link, raise this.")
        }
    }
}

// MARK: - Denylist

private struct DenylistSection: View {
    @ObservedObject var settings: Settings

    @State private var showsBuiltIns = false
    @State private var runningApps: [AppInfo] = []

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Explanation("Terminals, code editors, and password managers are excluded automatically. Add anything else here.")

                ForEach(settings.userDenylist, id: \.self) { bundleID in
                    DenylistRow(bundleID: bundleID) { settings.removeFromDenylist(bundleID) }
                }

                addControls

                DisclosureGroup(isExpanded: $showsBuiltIns) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(settings.builtInDenylist, id: \.self) { entry in
                            Text(entry)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                } label: {
                    Text("Excluded automatically (\(settings.builtInDenylist.count))")
                        .font(.subheadline)
                }
            }
            .onAppear { refreshRunningApps() }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Excluded apps")
        } header: {
            Text("Never link-paste in these apps")
        }
    }

    private var addControls: some View {
        HStack {
            // Refreshed when the menu is opened rather than on a timer: the list
            // is only ever looked at in the instant before something is picked.
            Menu("Add Running App…") {
                if selectableRunningApps.isEmpty {
                    Text("No other apps running")
                } else {
                    ForEach(selectableRunningApps) { app in
                        Button {
                            settings.addToDenylist(app.bundleID)
                        } label: {
                            if let icon = app.icon {
                                Label { Text(app.name) } icon: { Image(nsImage: icon) }
                            } else {
                                Text(app.name)
                            }
                        }
                    }
                }
            }
            .menuStyle(.button)
            .fixedSize()
            .onTapGesture { refreshRunningApps() }

            Button("Choose App…") {
                if let app = AppCatalog.chooseApplication() {
                    settings.addToDenylist(app.bundleID)
                }
            }
            .buttonStyle(.bordered)

            Spacer()
        }
    }

    /// Hides apps already excluded, so picking one twice isn't offered.
    private var selectableRunningApps: [AppInfo] {
        let excluded = Set(settings.userDenylist)
        return runningApps.filter { !excluded.contains($0.bundleID) }
    }

    private func refreshRunningApps() {
        runningApps = AppCatalog.runningApps()
    }
}

/// One excluded app: icon, name, and the identifier it actually matches on.
private struct DenylistRow: View {
    let bundleID: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let icon = AppCatalog.icon(forBundleID: bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(AppCatalog.displayName(forBundleID: bundleID))
                // Kept visible: it's what the matching actually uses, and it
                // disambiguates apps that share a display name.
                Text(bundleID)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: remove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            // An unlabeled icon button announces as "minus circle", or nothing.
            .accessibilityLabel("Remove \(AppCatalog.displayName(forBundleID: bundleID))")
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Markdown list

private struct MarkdownListSection: View {
    @ObservedObject var settings: Settings

    @State private var runningApps: [AppInfo] = []

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Explanation("For apps whose rich-text paste doesn't work — e.g. Slack with \"Format messages with markup\" on. Adds [text](url) as plain text instead. This overrides an app's denylist entry, built-in or not.")

                ForEach(settings.userMarkdownList, id: \.self) { bundleID in
                    DenylistRow(bundleID: bundleID) { settings.removeFromMarkdownList(bundleID) }
                }

                addControls
            }
            .onAppear { refreshRunningApps() }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Markdown apps")
        } header: {
            Text("Use markdown links in")
        }
    }

    private var addControls: some View {
        HStack {
            Menu("Add Running App…") {
                if selectableRunningApps.isEmpty {
                    Text("No other apps running")
                } else {
                    ForEach(selectableRunningApps) { app in
                        Button {
                            settings.addToMarkdownList(app.bundleID)
                        } label: {
                            if let icon = app.icon {
                                Label { Text(app.name) } icon: { Image(nsImage: icon) }
                            } else {
                                Text(app.name)
                            }
                        }
                    }
                }
            }
            .menuStyle(.button)
            .fixedSize()
            .onTapGesture { refreshRunningApps() }

            Button("Choose App…") {
                if let app = AppCatalog.chooseApplication() {
                    settings.addToMarkdownList(app.bundleID)
                }
            }
            .buttonStyle(.bordered)

            Spacer()
        }
    }

    private var selectableRunningApps: [AppInfo] {
        let selected = Set(settings.userMarkdownList)
        return runningApps.filter { !selected.contains($0.bundleID) }
    }

    private func refreshRunningApps() {
        runningApps = AppCatalog.runningApps()
    }
}

// MARK: - Last paste

private struct LastPasteSection: View {
    @ObservedObject var settings: Settings

    var body: some View {
        Section {
            Text(settings.lastOutcomeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Last paste: \(settings.lastOutcomeDescription)")
        } header: {
            Text("Last paste")
        }
    }
}

// MARK: - Shared

/// The explanatory caption used throughout Settings. Every one of these was the
/// same four modifiers repeated, which buried the text they were describing.
private struct Explanation: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
