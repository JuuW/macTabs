import AppKit
import ApplicationServices

/// 代表一个受支持 app 的窗口
struct ManagedWindow: Identifiable, Equatable {
    let id: String          // 稳定标识:pid-title@位置#区分号
    let title: String       // 原始窗口标题,用于显示/身份
    let axElement: AXUIElement
    let pid: pid_t

    // 身份只看 id,不比标题,避免同标题窗口焦点混淆
    static func == (lhs: ManagedWindow, rhs: ManagedWindow) -> Bool {
        lhs.id == rhs.id
    }

    func displayEquals(_ other: ManagedWindow) -> Bool {
        id == other.id && title == other.title
    }
}

/// 枚举「当前前台受支持 app」的窗口、读取标题、切换聚焦、关闭。
/// 不含任何 SAP 特有逻辑:无分组、无事务码、无标题正则。
final class WindowManager: ObservableObject {
    @Published var windows: [ManagedWindow] = []
    @Published var frontWindowID: String? = nil
    @Published var accessibilityGranted: Bool = false
    /// 当前前台受支持 app 的图标(用于页签前显示);前台不受支持时为 nil
    @Published var frontAppIcon: NSImage? = nil

    private let settings: SettingsStore
    private var timer: Timer?

    // 记录每个窗口 id 首次出现序号,保证页签顺序稳定、不随 z-order 重排
    private var orderSeen: [String: Int] = [:]
    private var nextOrder: Int = 0

    // 同 (标题@位置) 撞车时,锚定到 AX 元素身份的稳定区分号
    private var elementDiscriminators: [(element: AXUIElement, key: String, disc: Int)] = []

    init(settings: SettingsStore) {
        self.settings = settings
        checkAccessibility()
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - 权限

    func checkAccessibility() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - 枚举

    func refresh() {
        checkAccessibility()
        guard accessibilityGranted else {
            if !windows.isEmpty { windows = [] }
            if frontAppIcon != nil { frontAppIcon = nil }
            return
        }

        // 只处理当前前台 app;且它必须在受支持集合里
        guard let front = NSWorkspace.shared.frontmostApplication,
              let bundleID = front.bundleIdentifier,
              settings.isSupported(bundleID) else {
            if !windows.isEmpty { windows = [] }
            if frontWindowID != nil { frontWindowID = nil }
            if frontAppIcon != nil { frontAppIcon = nil }
            return
        }

        let icon = front.icon
        if frontAppIcon !== icon { frontAppIcon = icon }

        let appElement = AXUIElementCreateApplication(front.processIdentifier)

        // 当前聚焦窗口(用于高亮),按 AX 元素身份比较
        var focusedElement: AXUIElement? = nil
        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
           let focusedWin = focusedRef {
            focusedElement = (focusedWin as! AXUIElement)
        }

        var windowsRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard err == .success, let axWindows = windowsRef as? [AXUIElement] else {
            if !windows.isEmpty { windows = [] }
            return
        }

        var result: [ManagedWindow] = []
        var frontID: String? = nil
        var liveDiscIdx = Set<Int>()

        for win in axWindows {
            // 只保留标准文档窗口,排除工具面板、浮窗、无标题辅助窗口
            guard isStandardWindow(win) else { continue }
            let title = copyStringAttribute(win, kAXTitleAttribute) ?? "(未命名)"

            let baseKey = "\(front.processIdentifier)-\(title)"
            var wid: String
            if let p = windowPosition(win) {
                wid = "\(baseKey)@\(Int(p.x.rounded())),\(Int(p.y.rounded()))"
            } else {
                wid = baseKey
            }
            let (disc, idx) = discriminator(for: win, key: wid)
            liveDiscIdx.insert(idx)
            if disc > 0 { wid = "\(wid)#\(disc)" }

            result.append(ManagedWindow(id: wid, title: title, axElement: win, pid: front.processIdentifier))

            if let fe = focusedElement, CFEqual(fe, win), frontID == nil {
                frontID = wid
            }
        }

        elementDiscriminators = liveDiscIdx.sorted().map { elementDiscriminators[$0] }

        // 稳定排序:按窗口首次出现(打开)顺序,不随 z-order 漂移
        let liveIDs = Set(result.map(\.id))
        orderSeen = orderSeen.filter { liveIDs.contains($0.key) }
        for w in result where orderSeen[w.id] == nil {
            orderSeen[w.id] = nextOrder
            nextOrder += 1
        }
        result.sort { (orderSeen[$0.id] ?? 0) < (orderSeen[$1.id] ?? 0) }

        if !sameWindows(windows, result) { windows = result }
        if frontWindowID != frontID { frontWindowID = frontID }
    }

    private func sameWindows(_ a: [ManagedWindow], _ b: [ManagedWindow]) -> Bool {
        guard a.count == b.count else { return false }
        for (x, y) in zip(a, b) where !x.displayEquals(y) { return false }
        return true
    }

    private func discriminator(for element: AXUIElement, key: String) -> (disc: Int, index: Int) {
        if let i = elementDiscriminators.firstIndex(where: { $0.key == key && CFEqual($0.element, element) }) {
            return (elementDiscriminators[i].disc, i)
        }
        let used = Set(elementDiscriminators.filter { $0.key == key }.map(\.disc))
        var d = 0
        while used.contains(d) { d += 1 }
        elementDiscriminators.append((element: element, key: key, disc: d))
        return (d, elementDiscriminators.count - 1)
    }

    /// 判定是否为标准文档窗口:role=AXWindow 且 subrole=AXStandardWindow。
    /// 据此过滤掉工具面板(AXFloatingWindow)、无 subrole 的辅助窗口等。
    private func isStandardWindow(_ win: AXUIElement) -> Bool {
        let role = copyStringAttribute(win, kAXRoleAttribute)
        guard role == (kAXWindowRole as String) else { return false }
        let subrole = copyStringAttribute(win, kAXSubroleAttribute)
        return subrole == (kAXStandardWindowSubrole as String)
    }

    // MARK: - 切换 / 关闭

    func focus(_ window: ManagedWindow) {
        frontWindowID = window.id
        AXUIElementPerformAction(window.axElement, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window.axElement, kAXMainAttribute as CFString, kCFBooleanTrue)
        if let app = NSRunningApplication(processIdentifier: window.pid) {
            app.activate()
        }
    }

    func close(_ window: ManagedWindow) {
        var btnRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window.axElement, kAXCloseButtonAttribute as CFString, &btnRef) == .success,
           let btn = btnRef {
            AXUIElementPerformAction(btn as! AXUIElement, kAXPressAction as CFString)
        }
        refresh()
    }

    // MARK: - 辅助

    private func copyStringAttribute(_ element: AXUIElement, _ attr: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private func windowPosition(_ element: AXUIElement) -> CGPoint? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &ref) == .success,
              let value = ref else { return nil }
        var point = CGPoint.zero
        if AXValueGetValue(value as! AXValue, .cgPoint, &point) { return point }
        return nil
    }
}
