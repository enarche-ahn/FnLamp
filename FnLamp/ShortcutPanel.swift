// ShortcutPanel.swift
// UI and state management for the global shortcut settings panel.
// ShortcutRecorderState handles live key capture; ShortcutSettingsView renders the form;
// ShortcutWindowController owns the floating NSPanel lifecycle.

import AppKit
import SwiftUI
import Carbon
import Combine

// MARK: - Recorder State

@MainActor
final class ShortcutRecorderState: ObservableObject {
    @Published var displayText: String = ""
    @Published var isRecording: Bool = false
    var pendingKeyCode: Int? = nil
    var pendingModifiers: Int? = nil

    private var localMonitor: Any?

    init(currentKeyCode: Int, currentModifiers: Int) {
        displayText = shortcutDisplayString(keyCode: currentKeyCode, modifiers: currentModifiers)
    }

    // Begins listening for a key-down event via a local event monitor.
    // Esc without modifiers cancels; any other key+modifier combination is captured.
    func startRecording() {
        isRecording = true
        displayText = "키를 입력하세요…"
        pendingKeyCode = nil
        pendingModifiers = nil

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])

            // Esc without modifier → cancel
            if event.keyCode == UInt16(kVK_Escape) && flags.isEmpty {
                self.cancelRecording()
                return nil
            }

            guard !flags.isEmpty else { return event }

            let kc = Int(event.keyCode)
            let mod = carbonModifiers(from: flags)
            self.pendingKeyCode = kc
            self.pendingModifiers = mod
            self.displayText = shortcutDisplayString(keyCode: kc, modifiers: mod)
            self.stopMonitor()
            self.isRecording = false
            return nil
        }
    }

    // Cancels an in-progress recording, removes the event monitor,
    // and optionally restores the display text to the original shortcut.
    func cancelRecording(originalKeyCode: Int? = nil, originalModifiers: Int? = nil) {
        stopMonitor()
        isRecording = false
        pendingKeyCode = nil
        pendingModifiers = nil
        if let kc = originalKeyCode, let mod = originalModifiers {
            displayText = shortcutDisplayString(keyCode: kc, modifiers: mod)
        }
    }

    private func stopMonitor() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }
}

// MARK: - Settings View

struct ShortcutSettingsView: View {
    @ObservedObject var state: ShortcutRecorderState
    let originalKeyCode: Int
    let originalModifiers: Int
    let onSave: (Int, Int) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("전역 단축키 설정")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("단축키")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button(action: toggleRecording) {
                    Text(state.displayText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(state.isRecording ? .orange : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(state.isRecording ? Color.orange : Color.secondary.opacity(0.4), lineWidth: 1)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                )

                if state.isRecording {
                    Text("Esc 키로 취소")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("취소") {
                    state.cancelRecording(originalKeyCode: originalKeyCode, originalModifiers: originalModifiers)
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("저장") {
                    let kc  = state.pendingKeyCode  ?? originalKeyCode
                    let mod = state.pendingModifiers ?? originalModifiers
                    onSave(kc, mod)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(state.isRecording)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func toggleRecording() {
        if state.isRecording {
            state.cancelRecording(originalKeyCode: originalKeyCode, originalModifiers: originalModifiers)
        } else {
            state.startRecording()
        }
    }
}

// MARK: - Window Controller

@MainActor
final class ShortcutWindowController: NSObject, NSWindowDelegate {
    private weak var window: NSPanel?
    private let hotKeyManager: HotKeyManager

    init(hotKeyManager: HotKeyManager) {
        self.hotKeyManager = hotKeyManager
    }

    // Shows the shortcut settings panel, bringing it to front if already open.
    // Calls hotKeyManager.update on save; rolls back and shows an alert if the shortcut is taken.
    func showWindow() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let kc  = hotKeyManager.keyCode
        let mod = hotKeyManager.modifiers
        let state = ShortcutRecorderState(currentKeyCode: kc, currentModifiers: mod)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
            styleMask: [.titled, .closable, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "단축키 설정"
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.center()
        panel.delegate = self

        panel.contentView = NSHostingView(
            rootView: ShortcutSettingsView(
                state: state,
                originalKeyCode: kc,
                originalModifiers: mod,
                onSave: { [weak self, weak panel] newKc, newMod in
                    guard let self else { return }
                    let ok = self.hotKeyManager.update(keyCode: newKc, modifiers: newMod)
                    if ok {
                        panel?.close()
                    } else {
                        let alert = NSAlert()
                        alert.messageText = "단축키 등록 실패"
                        alert.informativeText = "해당 단축키가 다른 앱에 의해 이미 사용 중입니다. 다른 조합을 선택해 주세요."
                        alert.alertStyle = .warning
                        if let w = panel { alert.beginSheetModal(for: w) }
                    }
                },
                onCancel: { [weak panel] in
                    panel?.close()
                }
            )
        )

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = panel
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
