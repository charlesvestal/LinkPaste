import LinkPasteCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var permissions: PermissionsMonitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PermissionsSection(permissions: permissions)
                Divider().accessibilityHidden(true)
                BehaviorSection(settings: settings)
                Divider().accessibilityHidden(true)
                DenylistSection(settings: settings)
                Divider().accessibilityHidden(true)
                LastPasteSection(settings: settings)
            }
            .padding(20)
        }
        .frame(minWidth: 460, idealWidth: 480, minHeight: 380, idealHeight: 560)
    }
}

// MARK: - Permissions

private struct PermissionsSection: View {
    @ObservedObject var permissions: PermissionsMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status is carried by the text, not only by the icon's color, so it
            // survives both VoiceOver and color-blind viewing.
            Label(
                permissions.isTrusted ? "Accessibility access granted" : "Accessibility access required",
                systemImage: permissions.isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .font(.headline)
            .foregroundStyle(permissions.isTrusted ? Color.green : Color.orange)

            if !permissions.isTrusted {
                Explanation("LinkPaste can't see ⌘V without it. macOS also revokes this every time the app is updated — if link pasting stops working, check here first.")

                HStack {
                    Button("Open Privacy Settings") { permissions.openSettings() }
                    Button("Request Access") { permissions.requestAccess() }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Permissions")
    }
}

// MARK: - Behavior

private struct BehaviorSection: View {
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enable link pasting", isOn: $settings.isEnabled)
                .font(.headline)

            launchAtLogin

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Use ⌘C fallback to detect selection", isOn: $settings.allowsCopyProbe)
                Explanation("Required for browsers, Slack, and Notion — they don't report the selection any other way. Turn it off if you'd rather no synthetic ⌘C is ever sent.")
            }

            restoreDelay
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Behavior")
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

    @State private var newEntry = ""
    @State private var showsBuiltIns = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Never link-paste in these apps")
                .font(.headline)
            Explanation("Terminals, code editors, and password managers are excluded automatically. Add bundle identifiers here for anything else.")

            ForEach(settings.userDenylist, id: \.self) { entry in
                HStack {
                    Text(entry).font(.system(.body, design: .monospaced))
                    Spacer()
                    Button {
                        settings.removeFromDenylist(entry)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    // An unlabeled icon button announces as "minus circle" or
                    // nothing at all.
                    .accessibilityLabel("Remove \(entry)")
                }
                .accessibilityElement(children: .combine)
            }

            HStack {
                TextField("com.example.App", text: $newEntry)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Bundle identifier to exclude")
                    .onSubmit(add)  // Return should work; reaching for the mouse shouldn't be required
                Button("Add", action: add)
                    .disabled(trimmedEntry.isEmpty)
            }

            DisclosureGroup("Excluded automatically (\(settings.builtInDenylist.count))", isExpanded: $showsBuiltIns) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(settings.builtInDenylist, id: \.self) { entry in
                        Text(entry)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
            .font(.caption)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Excluded apps")
    }

    private var trimmedEntry: String {
        newEntry.trimmingCharacters(in: .whitespaces)
    }

    private func add() {
        guard !trimmedEntry.isEmpty else { return }
        settings.addToDenylist(trimmedEntry)
        newEntry = ""
    }
}

// MARK: - Last paste

private struct LastPasteSection: View {
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last paste").font(.headline)
            Text(settings.lastOutcomeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Last paste: \(settings.lastOutcomeDescription)")
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
