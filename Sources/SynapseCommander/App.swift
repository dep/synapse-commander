import SwiftUI
import AppKit

@main
struct SynapseCommanderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var updater = UpdaterViewModel()

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                UpdateBanner(updater: updater)
                ContentView()
            }
            .frame(minWidth: 900, minHeight: 500)
            .preferredColorScheme(.dark)
            .onAppear { updater.checkInBackground() }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
