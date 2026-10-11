#if os(macOS)
import AppKit

@MainActor
final class AppLifecycle: NSObject, NSApplicationDelegate {
    var persistence: LibraryPersistence?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let persistence else { return .terminateNow }
        persistence.flushState()
        guard persistence.hasUnsavedChanges else { return .terminateNow }
        Task {
            await persistence.flush()
            if persistence.hasUnsavedChanges {
                let alert = NSAlert()
                alert.messageText = "The library could not be saved."
                alert.informativeText = (persistence.errorMessage ?? "")
                    + "\nQuit without saving your latest changes?"
                alert.addButton(withTitle: "Cancel")
                alert.addButton(withTitle: "Quit Without Saving")
                sender.reply(toApplicationShouldTerminate: alert.runModal() == .alertSecondButtonReturn)
            } else {
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }
}
#endif
