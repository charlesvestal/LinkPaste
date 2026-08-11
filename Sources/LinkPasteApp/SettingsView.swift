import LinkPasteCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var permissions: PermissionsMonitor

    @State private var newDenylistEntry: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            permissionsSection
            Divider()
            behaviorSection
            Divider()
            denylistSection
            Divider()
            statusSection
        }
        .padding(20)
        .frame(width: 460)
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                permissions.isTrusted ? "Accessibility access granted" : "Accessibility access required",
                systemImage: permissions.isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(permissions.isTrusted ? .green : .orange)
            .font(.headline)

            if !permissions.isTrusted {
                Text("LinkPaste can't see ⌘V without it. macOS also revokes this every time the app is updated — if link-pasting stops working, check here first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button("Open Privacy Settings") { permissions.openSettings() }
                    Button("Request Access") { permissions.requestAccess() }
                }
            }
        }
    }

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Enable link pasting", isOn: Binding(
                get: { settings.isEnabled },
                set: { settings.isEnabled = $0 }
            ))
            .font(.headline)

            Toggle("Launch at login", isOn: Binding(
                get: { settings.launchesAtLogin },
                set: { settings.launchesAtLogin = $0 }
            ))

            Toggle("Use ⌘C fallback to detect selection", isOn: Binding(
                get: { settings.allowsCopyProbe },
                set: { settings.allowsCopyProbe = $0 }
            ))
            Text("Needed for browsers, Slack, and Notion, which often won't report the selection any other way. Turn it off if you'd rather no synthetic ⌘C is ever sent.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Clipboard restore delay")
                Slider(
                    value: Binding(
                        get: { Double(settings.restoreDelayMilliseconds) },
                        set: { settings.restoreDelayMilliseconds = Int($0) }
                    ),
                    in: 50...1000,
                    step: 25
                )
                Text("\(settings.restoreDelayMilliseconds) ms")
                    .monospacedDigit()
                    .frame(width: 60, alignment: .trailing)
            }
            Text("How long to wait before restoring your clipboard. If a slow app pastes your *previous* clipboard instead of the link, raise this.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var denylistSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Never link-paste in these apps")
                .font(.headline)
            Text("Terminals, code editors, and password managers are excluded automatically. Add bundle IDs here for anything else.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !settings.userDenylist.isEmpty {
                ForEach(settings.userDenylist, id: \.self) { entry in
                    HStack {
                        Text(entry).font(.system(.body, design: .monospaced))
                        Spacer()
                        Button {
                            settings.userDenylist.removeAll { $0 == entry }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            HStack {
                TextField("com.example.App", text: $newDenylistEntry)
                    .textFieldStyle(.roundedBorder)
                Button("Add") { addDenylistEntry() }
                    .disabled(newDenylistEntry.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last paste").font(.headline)
            Text(settings.lastOutcomeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func addDenylistEntry() {
        let entry = newDenylistEntry.trimmingCharacters(in: .whitespaces)
        guard !entry.isEmpty, !settings.userDenylist.contains(entry) else { return }
        settings.userDenylist.append(entry)
        newDenylistEntry = ""
    }
}
