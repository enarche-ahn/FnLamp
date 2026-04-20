// AppDelegate.swift
// Core application controller for FnLamp.
// Manages the menu bar status item, fn key state polling, popover notifications,
// and wires up HotKeyManager for the global toggle shortcut.

import Cocoa
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu?
    private var timer: Timer?
    private var hostingView: NSHostingView<LampStackView>?

    private let fnKey = "com.apple.keyboard.fnState"
    private let itemWidth: CGFloat = 16
    private let itemHeight: CGFloat = 22

    private let popover = NSPopover()
    private var popoverDismissWorkItem: DispatchWorkItem?

    private var lastKnownFnState: Bool?
    private var hasFinishedInitialSync = false

    private var hotKeyManager: HotKeyManager?
    private var shortcutWindowController: ShortcutWindowController?

    // Sets up the status item, popover, menu, hotkey, and starts the 1-second polling timer.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: itemWidth)
        configureMenu()
        configureStatusButton()
        configurePopover()
        syncFnState(showPopoverOnChange: false)

        hotKeyManager = HotKeyManager(onTrigger: { [weak self] in self?.toggleFn() })
        hotKeyManager?.register()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.syncFnState(showPopoverOnChange: true)
            }
        }
    }

    // Embeds a SwiftUI LampStackView inside the status item button
    // and registers click/right-click handling.
    private func configureStatusButton() {
        guard let button = statusItem.button else { return }

        button.title = ""
        button.image = nil
        button.frame = NSRect(x: 0, y: 0, width: itemWidth, height: itemHeight)
        button.toolTip = "Fn mode indicator"
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let view = NSHostingView(rootView: LampStackView(isFnMode: currentFnState()))
        view.frame = NSRect(x: 0, y: 0, width: itemWidth, height: itemHeight)
        view.translatesAutoresizingMaskIntoConstraints = false
        hostingView = view

        button.subviews.forEach { $0.removeFromSuperview() }
        button.addSubview(view)

        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            view.topAnchor.constraint(equalTo: button.topAnchor),
            view.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])
    }

    // Builds the right-click context menu with toggle, refresh, shortcut settings, and quit items.
    private func configureMenu() {
        let menu = NSMenu()

        let toggleItem = NSMenuItem(title: "Toggle fn Key", action: #selector(toggleFn), keyEquivalent: "t")
        toggleItem.target = self
        menu.addItem(toggleItem)

        let refreshItem = NSMenuItem(title: "Refresh State", action: #selector(refreshState), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        let shortcutItem = NSMenuItem(title: "Shortcut Settings…", action: #selector(openShortcutSettings), keyEquivalent: "")
        shortcutItem.target = self
        menu.addItem(shortcutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusMenu = menu
    }

    // Configures the transient popover used for mode-change notifications.
    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 300, height: 66)
    }

    // Reads the current fn key state directly from the global user defaults domain.
    // Returns true when Standard Function Keys mode (F1, F2 …) is active.
    private func currentFnState() -> Bool {
        let domain = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        return domain?[fnKey] as? Bool ?? false
    }

    // Reads the current fn state and updates the menu bar indicator and tooltip.
    // When showPopoverOnChange is true, also shows the mode-change popover
    // if the state differs from the last known value.
    private func syncFnState(showPopoverOnChange: Bool) {
        let isFnMode = currentFnState()

        hostingView?.rootView = LampStackView(isFnMode: isFnMode)
        statusItem.button?.toolTip = isFnMode
            ? "Standard Function Keys (F1, F2 ...)"
            : "Special Function Keys (Brightness, Volume, etc.)"

        defer {
            lastKnownFnState = isFnMode
            hasFinishedInitialSync = true
        }

        guard hasFinishedInitialSync else { return }

        if lastKnownFnState != isFnMode, showPopoverOnChange {
            showModePopover(isFnMode: isFnMode)
        }
    }

    // Presents a brief popover below the status item describing the new mode,
    // then auto-dismisses it after 1 second.
    private func showModePopover(isFnMode: Bool) {
        guard let button = statusItem.button else { return }

        popoverDismissWorkItem?.cancel()

        let title = isFnMode
            ? "Switched to Standard Function Keys"
            : "Switched to Special Function Keys"

        let subtitle = isFnMode
            ? "F1, F2 and other function keys work directly"
            : "Hardware controls (brightness, volume) take priority"

        popover.contentViewController = NSHostingController(
            rootView: ModePopoverView(
                title: title,
                subtitle: subtitle,
                color: isFnMode ? Color.green : Color.orange
            )
        )

        if popover.isShown {
            popover.performClose(nil)
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        let work = DispatchWorkItem { [weak self] in
            self?.popover.performClose(nil)
        }
        popoverDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    // Routes left-click to toggleFn() and right-click (or Ctrl+click) to the context menu.
    @objc
    private func handleStatusItemClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            toggleFn()
            return
        }

        let isRightClick = event.type == .rightMouseUp
            || (event.type == .leftMouseUp && event.modifierFlags.contains(.control))

        if isRightClick {
            if popover.isShown {
                popover.performClose(nil)
            }

            guard let menu = statusMenu, let button = statusItem.button else { return }

            statusItem.menu = menu
            button.performClick(nil)
            statusItem.menu = nil
        } else {
            toggleFn()
        }
    }
    
    @objc
    private func refreshState() {
        syncFnState(showPopoverOnChange: true)
    }

    // Flips the fn key mode by writing to CFPreferences and calling activateSettings
    // so the change takes effect immediately without a logout/restart.
    // Plays a distinct system sound for each direction of the toggle.
    @objc
    private func toggleFn() {
        let newValue = !currentFnState()

        CFPreferencesSetValue(
            fnKey as CFString,
            (newValue ? kCFBooleanTrue : kCFBooleanFalse),
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings")
        proc.arguments = ["-u"]
        try? proc.run()
        proc.waitUntilExit()
        
        if newValue {
            NSSound(named: "Blow")?.play()
        } else {
            NSSound(named: "Frog")?.play()
        }

        syncFnState(showPopoverOnChange: true)
    }

    // Opens the shortcut settings panel, creating the window controller lazily on first use.
    @objc
    private func openShortcutSettings() {
        if shortcutWindowController == nil, let hkm = hotKeyManager {
            shortcutWindowController = ShortcutWindowController(hotKeyManager: hkm)
        }
        shortcutWindowController?.showWindow()
    }

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }
}

struct LampStackView: View {
    let isFnMode: Bool

    var body: some View {
        VStack(spacing: 0) {
            LampRowView(
                label: .fnText,
                lampColor: isFnMode ? .green : .gray,
                iconColor: isFnMode ? .white : .secondary
            )

            LampRowView(
                label: .brightnessSymbol,
                lampColor: isFnMode ? .gray : .orange,
                iconColor: isFnMode ? .secondary : .white
            )
        }
        .frame(width: 16, height: 22)
        .padding(.trailing, 1)
        .contentShape(Rectangle())
    }
}

struct LampRowView: View {
    enum LabelKind {
        case fnText
        case brightnessSymbol
    }

    let label: LabelKind
    let lampColor: Color
    let iconColor: Color

    var body: some View {
        HStack(spacing: 1) {
            iconView
                .frame(width: 7, alignment: .leading)

            Spacer(minLength: 0)

            Circle()
                .fill(lampColor)
                .frame(width: 5, height: 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private var iconView: some View {
        switch label {
        case .fnText:
            Text("fn")
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(iconColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

        case .brightnessSymbol:
            Image(systemName: "sun.max.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 8, height: 8)
                .foregroundColor(iconColor)
        }
    }
}

struct ModePopoverView: View {
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 300, height: 66, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }
}
