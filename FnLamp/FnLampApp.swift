// FnLampApp.swift
// Entry point for FnLamp. Delegates all app logic to AppDelegate;
// the Settings scene is declared to satisfy SwiftUI's App protocol
// while keeping the app as a menu-bar-only accessory (no Dock icon).

import SwiftUI

@main
struct FnLampApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Empty Settings scene — required by SwiftUI App protocol,
    // but UI is managed entirely by AppDelegate via NSStatusItem.
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
