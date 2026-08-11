import AppKit
import Foundation

/// A full copy of the pasteboard's contents, so we can put the user's clipboard
/// back exactly as we found it.
///
/// We overwrite the clipboard twice per link-paste (once for the ⌘C selection
/// probe, once for the rich payload). Failing to restore would quietly destroy
/// whatever the user had copied — the single most damaging thing this app could
/// do — so restore runs from a `defer` on every path.
public struct PasteboardSnapshot {
    /// One entry per pasteboard item: every declared type and its data.
    public let items: [[NSPasteboard.PasteboardType: Data]]

    public init(items: [[NSPasteboard.PasteboardType: Data]]) {
        self.items = items
    }

    public static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let captured = (pasteboard.pasteboardItems ?? []).map { item in
            var types: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    types[type] = data
                }
            }
            return types
        }
        return PasteboardSnapshot(items: captured)
    }

    public func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }

        let rebuilt = items.map { types -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in types {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(rebuilt)
    }
}
