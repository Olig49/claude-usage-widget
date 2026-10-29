import AppKit
import UsageCore

/// Right-click > Uninstall: removes the login item, the tokens this app saved, its settings and
/// the app itself (moved to the Trash). Claude Code logins are never touched.
@MainActor
enum Uninstaller {
    static func confirmAndRun(store: UsageStore, loginItem: LoginItem) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Uninstall Claude Usage?"
        alert.informativeText = """
            This removes the app (to the Trash), its settings, its login item and any tokens it saved \
            in your Keychain. Your Claude Code logins aren't touched.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        loginItem.setEnabled(false)
        for a in store.config.accounts where a.sourceKind == .token {
            TokenStore.delete(account: a.name)
        }
        try? FileManager.default.removeItem(at: store.configStore.directory)
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")

        let bundle = Bundle.main.bundleURL
        if bundle.pathExtension == "app" {
            NSWorkspace.shared.recycle([bundle]) { _, _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        } else {
            NSApp.terminate(nil)
        }
    }
}
