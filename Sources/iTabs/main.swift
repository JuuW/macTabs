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
            button.image = Self.makeStatusIcon()
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "启用 / 停用自动显示", action: #selector(togglePanel), keyEquivalent: "t").target = self
        menu.addItem(withTitle: "刷新", action: #selector(refreshNow), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 iTabs", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    /// 画一个 2x2 四色圆角方块作菜单栏图标,表示"多 app"。
    /// 彩色图标须关掉模板渲染(isTemplate=false),否则会被系统强制单色化。
    private static func makeStatusIcon() -> NSImage {
        let size: CGFloat = 18          // 菜单栏推荐图标点数
        let gap: CGFloat = 2            // 四块之间的间隙
        let cell = (size - gap) / 2     // 单块边长
        let radius: CGFloat = 2.5
        let colors: [NSColor] = [
            NSColor(red: 0.90, green: 0.26, blue: 0.21, alpha: 1), // 红(左上)
            NSColor(red: 0.20, green: 0.60, blue: 0.86, alpha: 1), // 蓝(右上)
            NSColor(red: 0.18, green: 0.74, blue: 0.42, alpha: 1), // 绿(左下)
            NSColor(red: 0.95, green: 0.77, blue: 0.06, alpha: 1), // 黄(右下)
        ]
        // 左上、右上、左下、右下 的原点(AppKit 坐标系原点在左下,故上排 y 较大)
        let origins = [
            CGPoint(x: 0, y: cell + gap),
            CGPoint(x: cell + gap, y: cell + gap),
            CGPoint(x: 0, y: 0),
            CGPoint(x: cell + gap, y: 0),
        ]

        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            for (i, origin) in origins.enumerated() {
                let rect = NSRect(x: origin.x, y: origin.y, width: cell, height: cell)
                let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
                colors[i].setFill()
                path.fill()
            }
            return true
        }
        image.isTemplate = false        // 保留彩色,不被系统单色化
        return image
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
