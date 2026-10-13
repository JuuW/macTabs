import SwiftUI
import AppKit

struct TabBarView: View {
    @ObservedObject var manager: WindowManager
    @ObservedObject var settings: SettingsStore
    @StateObject private var overflow = OverflowState()

    var body: some View {
        Group {
            if !manager.accessibilityGranted {
                permissionPrompt
            } else if manager.windows.isEmpty {
                emptyState
            } else {
                tabs
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.82, green: 0.90, blue: 0.98))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            OverflowTabsLayout(count: manager.windows.count, reserve: 40, state: overflow) {
                ForEach(Array(manager.windows.enumerated()), id: \.element.id) { _, win in
                    chip(win: win)
                }
                OverflowMenuView(manager: manager, settings: settings, state: overflow)
                NewWindowButton { manager.newWindow() }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(win: ManagedWindow) -> some View {
        TabChip(
            title: truncate(win.title),
            icon: manager.frontAppIcon,
            isActive: win.id == manager.frontWindowID,
            onClose: { manager.close(win) }
        )
        .onTapGesture { manager.focus(win) }
        .help("\(win.title)\n单击切换")
    }

    /// 按设置的最大长度截断标题,超出用 "..." 代替。按字符数计。
    private func truncate(_ title: String) -> String {
        let n = settings.maxTitleLength
        return title.count > n ? String(title.prefix(n)) + "..." : title
    }

    private var emptyState: some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .foregroundStyle(.secondary)
            Text("没有打开的窗口")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var permissionPrompt: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.orange)
            Text("需要「辅助功能」权限")
                .font(.system(size: 12))
            Button("去授权") { manager.promptAccessibility() }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
    }
}

// CLT 工具链缺少 SwiftUIMacros 插件,@State 宏无法展开,改用 ObservableObject 承载悬停态
private final class HoverState: ObservableObject {
    @Published var on = false
}

/// 页签栏最右端的「+」按钮:新建当前 app 的一个窗口
struct NewWindowButton: View {
    let action: () -> Void
    @StateObject private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hover.on ? Color.white.opacity(0.9) : Color.white.opacity(0.6))
                )
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
        .help("新建窗口")
    }
}

struct TabChip: View {
    let title: String
    var icon: NSImage? = nil
    let isActive: Bool
    var onClose: (() -> Void)? = nil

    @StateObject private var hover = HoverState()

    var body: some View {
        let hovering = hover.on
        return HStack(spacing: 5) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            // 用隐藏粗体副本撑宽度,激活与否宽度恒定,分割线不右移
            ZStack {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .hidden()
                Text(title)
                    .font(.system(size: 13, weight: isActive ? .bold : .regular))
                    .foregroundStyle(Color.primary)
            }
            .lineLimit(1)
            // 为右上角关闭叉叉预留宽度,且所有页签恒定预留,焦点切换时宽度不跳动
            Spacer().frame(width: 12)
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 6, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: 6,
                style: .continuous
            )
            .fill(isActive ? Color.white : (hovering ? Color.white.opacity(0.4) : Color.clear))
        )
        .overlay(alignment: .topTrailing) {
            if isActive, let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(Color.secondary.opacity(0.75)))
                }
                .buttonStyle(.plain)
                .help("关闭此窗口")
                .padding(.top, 2)
                .padding(.trailing, 2)
            }
        }
        .contentShape(Rectangle())
        .onHover { hover.on = $0 }
    }
}

/// 共享:当前能放得下的页签数量(Layout 计算 → Menu 读取)
final class OverflowState: ObservableObject {
    @Published var visibleCount: Int = .max
    var updateToken: UInt64 = 0   // 非 @Published:仅用于防抖去重,不触发重绘
}

/// 单行溢出布局:子视图为 N 个页签 + 末尾 1 个溢出按钮。
/// 放得下时页签整体居中、溢出按钮尺寸归零;放不下时左对齐铺到临界点,
/// 其余页签不占空间,溢出按钮贴最右端。
struct OverflowTabsLayout: Layout {
    let count: Int
    let reserve: CGFloat
    let state: OverflowState

    init(count: Int, reserve: CGFloat, state: OverflowState) {
        self.count = count
        self.reserve = reserve
        self.state = state
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let h = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.width ?? 0, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        // 子视图布局:[0..<count] 页签,[count] 溢出菜单,[count+1] 新建「+」按钮
        guard count >= 0, subviews.count == count + 2 else { return }
        let menuIdx = count
        let plusIdx = count + 1
        guard bounds.width > reserve else {
            for i in 0..<count {
                subviews[i].place(at: CGPoint(x: bounds.minX, y: bounds.midY),
                                  anchor: .leading, proposal: ProposedViewSize(width: 0, height: 0))
            }
            subviews[menuIdx].place(at: CGPoint(x: bounds.minX, y: bounds.midY),
                                   anchor: .leading, proposal: ProposedViewSize(width: 0, height: 0))
            subviews[plusIdx].place(at: CGPoint(x: bounds.minX, y: bounds.midY),
                                    anchor: .leading, proposal: ProposedViewSize(width: 0, height: 0))
            return
        }
        let tabWidths = (0..<count).map { subviews[$0].sizeThatFits(.unspecified).width }
        let total = tabWidths.reduce(0, +)
        let plusWidth = subviews[plusIdx].sizeThatFits(.unspecified).width
        let avail = bounds.width
        let btnProposal = ProposedViewSize(width: reserve, height: bounds.height)
        let plusProposal = ProposedViewSize(width: plusWidth, height: bounds.height)

        // 全部放得下:页签 + 「+」整体居中,「+」紧跟最后一个页签
        if total + plusWidth <= avail {
            var x = bounds.minX + (avail - total - plusWidth) / 2
            for i in 0..<count {
                subviews[i].place(
                    at: CGPoint(x: x, y: bounds.midY),
                    anchor: .leading,
                    proposal: ProposedViewSize(width: tabWidths[i], height: bounds.height)
                )
                x += tabWidths[i]
            }
            subviews[plusIdx].place(at: CGPoint(x: x, y: bounds.midY),
                                    anchor: .leading, proposal: plusProposal)
            subviews[menuIdx].place(at: CGPoint(x: bounds.maxX + 2000, y: bounds.midY),
                                   anchor: .leading, proposal: btnProposal)
            setVisible(count)
            return
        }

        // 放不下:左对齐铺页签,给溢出菜单 + 「+」留出空间
        let budget = avail - reserve - plusWidth
        var used: CGFloat = 0
        var visible = 0
        for i in 0..<count {
            if used + tabWidths[i] <= budget {
                used += tabWidths[i]
                visible += 1
            } else {
                break
            }
        }
        visible = max(visible, count > 0 ? 1 : 0)

        var x = bounds.minX
        for i in 0..<count {
            if i < visible {
                subviews[i].place(
                    at: CGPoint(x: x, y: bounds.midY),
                    anchor: .leading,
                    proposal: ProposedViewSize(width: tabWidths[i], height: bounds.height)
                )
                x += tabWidths[i]
            } else {
                subviews[i].place(at: CGPoint(x: bounds.maxX + 2000, y: bounds.midY),
                                  anchor: .leading, proposal: ProposedViewSize(width: 0, height: 0))
            }
        }
        // 溢出菜单紧跟可见页签之后
        subviews[menuIdx].place(
            at: CGPoint(x: x, y: bounds.midY),
            anchor: .leading,
            proposal: btnProposal
        )
        x += reserve
        // 「+」再跟在溢出菜单之后
        subviews[plusIdx].place(
            at: CGPoint(x: x, y: bounds.midY),
            anchor: .leading,
            proposal: plusProposal
        )
        setVisible(visible)
    }

    private func setVisible(_ n: Int) {
        guard state.visibleCount != n else { return }
        let token = state.updateToken &+ 1
        state.updateToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            guard state.updateToken == token else { return }
            if state.visibleCount != n { state.visibleCount = n }
        }
    }
}

struct OverflowMenuView: View {
    @ObservedObject var manager: WindowManager
    @ObservedObject var settings: SettingsStore
    @ObservedObject var state: OverflowState

    private var overflow: [ManagedWindow] {
        let n = state.visibleCount
        guard n < manager.windows.count else { return [] }
        return Array(manager.windows.suffix(manager.windows.count - n))
    }

    private func truncate(_ title: String) -> String {
        let n = settings.maxTitleLength
        return title.count > n ? String(title.prefix(n)) + "..." : title
    }

    var body: some View {
        let items = overflow
        return ZStack {
            if !items.isEmpty {
                Menu {
                    ForEach(items) { win in
                        Button { manager.focus(win) } label: { Text(truncate(win.title)) }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                        Text("\(items.count)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.6))
                    )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("还有 \(items.count) 个页签放不下")
            }
        }
        .frame(width: 40, height: 24)
    }
}
