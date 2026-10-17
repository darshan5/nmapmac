import AppKit
import SwiftUI

/// An editable combo box (NSComboBox) — Zenmap's target entry with history.
struct ComboBox: NSViewRepresentable {
    @Binding var text: String
    var items: [String]
    var placeholder: String
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSComboBox {
        let box = NSComboBox()
        box.usesDataSource = false
        box.completes = true
        box.placeholderString = placeholder
        box.delegate = context.coordinator
        box.target = context.coordinator
        box.action = #selector(Coordinator.submit(_:))
        box.numberOfVisibleItems = 12
        return box
    }

    func updateNSView(_ box: NSComboBox, context: Context) {
        context.coordinator.parent = self
        if box.stringValue != text { box.stringValue = text }
        if (box.objectValues as? [String]) != items {
            box.removeAllItems()
            box.addItems(withObjectValues: items)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSComboBoxDelegate {
        var parent: ComboBox

        init(parent: ComboBox) {
            self.parent = parent
        }

        func controlTextDidChange(_ note: Notification) {
            guard let box = note.object as? NSComboBox else { return }
            parent.text = box.stringValue
        }

        func comboBoxSelectionDidChange(_ note: Notification) {
            guard let box = note.object as? NSComboBox,
                  let value = box.objectValueOfSelectedItem as? String else { return }
            parent.text = value
        }

        @objc func submit(_ sender: NSComboBox) {
            parent.text = sender.stringValue
            // The action also fires when the field loses focus; only scan on Return.
            if NSApp.currentEvent?.type == .keyDown {
                parent.onSubmit()
            }
        }
    }
}
