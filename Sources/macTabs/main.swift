import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private lazy var manager = WindowManager(settings: settings)
    private lazy var settingsWindow = SettingsWindowController(settings: settings)
    private var panel: NSPanel!
    private var statusItem: NSStatusItem!

    // 用户是否通过菜单手动隐藏了面板(手动隐藏时不自动弹出)
    private var manuallyHidden = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupPanel()
        setupStatusItem()
        manager.start()
        if !manager.accessibilityGranted {
            manager.promptAccessibility()
        }

        // 监听前台 app 切换,决定面板显隐
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self,
                       selector: #selector(activeAppChanged(_:)),
                       name: NSWorkspace.didActivateApplicationNotification,
                       object: nil)
        updatePanelVisibility()
    }

    @objc private func activeAppChanged(_ note: Notification) {
        // 前台 app 变了,立刻刷新窗口列表再决定显隐
        manager.refresh()
        updatePanelVisibility()
    }

    /// 当前前台 app 属于受支持集合时显示面板,否则隐藏
    private func updatePanelVisibility() {
        guard !manuallyHidden else { return }
        let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let frontID, settings.isSupported(frontID) {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    private func setupPanel() {
        let hosting = NSHostingView(rootView: TabBarView(manager: manager, settings: settings))

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 28),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.isMovable = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentView = hosting
        panel.hidesOnDeactivate = false

        positionPanel(panel)
        self.panel = panel

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            if let p = self?.panel { self?.positionPanel(p) }
        }
    }

    // 固定:当前屏幕可见宽度的 90%、水平居中、紧贴顶部;高度 28
    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        let w = f.width * 0.9
        let h: CGFloat = 28
        panel.setFrame(
            NSRect(x: f.midX - w / 2, y: f.maxY - h, width: w, height: h),
            display: true
        )
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "macTabs")
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "启用 / 停用自动显示", action: #selector(togglePanel), keyEquivalent: "t").target = self
        menu.addItem(withTitle: "刷新", action: #selector(refreshNow), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 macTabs", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func togglePanel() {
        manuallyHidden.toggle()
        if manuallyHidden {
            panel.orderOut(nil)
        } else {
            updatePanelVisibility()
        }
    }

    @objc private func refreshNow() { manager.refresh() }

    @objc private func quit() {
        manager.stop()
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // 菜单栏模式,不占 Dock
app.run()
