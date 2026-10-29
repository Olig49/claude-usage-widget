import AppKit
import SwiftUI
import UsageCore

/// The Settings window: a normal, resizable window with tabs. Edits preview live in the menu bar;
/// OK / Apply keep them, Cancel (or Esc, or the close button) undoes them.
@MainActor
final class SettingsController: NSObject, NSWindowDelegate {
    private let store: UsageStore
    private let loginItem: LoginItem
    private var window: NSWindow?

    init(store: UsageStore, loginItem: LoginItem) {
        self.store = store
        self.loginItem = loginItem
    }

    func show() {
        if let window, window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        store.beginEditing()
        let view = SettingsView(
            store: store,
            loginItem: loginItem,
            onOK: { [weak self] in self?.close(save: true) },
            onCancel: { [weak self] in self?.close(save: false) },
            onApply: { [weak self] in self?.store.applyDraft() }
        )
        let hosting = NSHostingController(rootView: view)
        // The window keeps its own size; switching tabs never resizes it.
        hosting.sizingOptions = []
        let w = NSWindow(contentViewController: hosting)
        w.title = "Claude Usage Settings"
        w.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        w.setContentSize(NSSize(width: 700, height: 540))
        w.contentMinSize = NSSize(width: 620, height: 480)
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private func close(save: Bool) {
        store.endEditing(save: save)
        window?.orderOut(nil)
        window = nil
    }

    /// The close button counts as Cancel.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        close(save: false)
        return false
    }
}
