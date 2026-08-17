import AppKit
import ApplicationServices
import Foundation
import LinkPasteCore

/// Works out *what* the ⌘V is about to land in, so the ledger has something to
/// key a verdict on.
///
/// Cheap by construction: a role, a subrole, and a bounded walk up to the
/// enclosing web area. It runs on the paste queue alongside `SelectionReader`,
/// never on the event tap thread.
enum DestinationInspector {

    /// How far up the AX tree to look for a web area before giving up. Deep DOMs
    /// are common and each hop is an IPC round-trip into another process.
    private static let maxParentHops = 8

    static func inspect(bundleID: String?) -> DestinationContext? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        // Also wakes Electron's accessibility tree, which is what makes role and
        // AXSelectedText answerable in Slack and friends at all.
        guard let element = SelectionReader.focusedElement() else { return nil }

        let role = string(element, kAXRoleAttribute) ?? ""
        guard !role.isEmpty else { return nil }

        let host = webHost(startingAt: element, role: role) ?? ""

        return DestinationContext(
            bundleID: bundleID,
            role: role,
            subrole: string(element, kAXSubroleAttribute) ?? "",
            host: host,
            // Only for desktop content: a browser's window title churns with the
            // page and would fragment what `host` already scopes correctly.
            window: host.isEmpty ? (windowIdentity(startingAt: element, role: role) ?? "") : ""
        )
    }

    /// Walks up to the enclosing `AXWebArea` and reads the page URL's host.
    private static func webHost(startingAt element: AXUIElement, role: String) -> String? {
        var current = element
        var currentRole = role

        for _ in 0..<maxParentHops {
            if currentRole == "AXWebArea" {
                return url(current, kAXURLAttribute)?.host
            }
            // Past the window there is no page to find.
            if currentRole == kAXWindowRole as String || currentRole == kAXApplicationRole as String {
                return nil
            }
            guard let parent = self.element(current, kAXParentAttribute) else { return nil }
            current = parent
            currentRole = string(parent, kAXRoleAttribute) ?? ""
        }
        return nil
    }

    /// Walks up to the enclosing window and reads something that tells it apart
    /// from the app's other windows: the represented document's path if it has
    /// one, otherwise the window title (still distinct per window even for an
    /// unsaved document — TextEdit numbers them "Untitled 1", "Untitled 2", ...).
    private static func windowIdentity(startingAt element: AXUIElement, role: String) -> String? {
        var current = element
        var currentRole = role

        for _ in 0..<maxParentHops {
            if currentRole == kAXWindowRole as String {
                return string(current, kAXDocumentAttribute) ?? string(current, kAXTitleAttribute)
            }
            if currentRole == kAXApplicationRole as String { return nil }
            guard let parent = self.element(current, kAXParentAttribute) else { return nil }
            current = parent
            currentRole = string(parent, kAXRoleAttribute) ?? ""
        }
        return nil
    }

    // MARK: - AX plumbing

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func url(_ element: AXUIElement, _ attribute: String) -> URL? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSURL) as URL?
    }
}
