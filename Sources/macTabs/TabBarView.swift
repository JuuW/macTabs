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
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(win: ManagedWindow) -> some View {
        TabChip(
            title: truncate(win.title),
            icon: manager.frontAppIcon,
            isActive: win.id == manager.frontWindowID
        )
        .onTapGesture { manager.focus(win) }
        .contextMenu {
            Button(role: .destructive) { manager.close(win) } label: {
                Label("关闭", systemImage: "xmark")
            }
        }
        .help("\(win.title)\n单击切换 · 右键关闭")
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

struct TabChip: View {
    let title: String
    var icon: NSImage? = nil
    let isActive: Bool

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
        guard count > 0, subviews.count == count + 1 else { return }
        guard bounds.width > reserve else {
            for i in 0..<count {
                subviews[i].place(at: CGPoint(x: bounds.minX, y: bounds.midY),
                                  anchor: .leading, proposal: ProposedViewSize(width: 0, height: 0))
            }
            subviews[count].place(at: CGPoint(x: bounds.minX, y: bounds.midY),
                                   anchor: .leading, proposal: ProposedViewSize(width: 0, height: 0))
            return
        }
        let tabWidths = (0..<count).map { subviews[$0].sizeThatFits(.unspecified).width }
        let total = tabWidths.reduce(0, +)
        let avail = bounds.width
        let btnProposal = ProposedViewSize(width: reserve, height: bounds.height)

        if total <= avail {
            var x = bounds.minX + (avail - total) / 2
            for i in 0..<count {
                subviews[i].place(
                    at: CGPoint(x: x, y: bounds.midY),
                    anchor: .leading,
                    proposal: ProposedViewSize(width: tabWidths[i], height: bounds.height)
                )
                x += tabWidths[i]
            }
            subviews[count].place(at: CGPoint(x: bounds.maxX + 2000, y: bounds.midY),
                                   anchor: .leading, proposal: btnProposal)
            setVisible(count)
            return
        }

        let budget = avail - reserve
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
        visible = max(visible, 1)

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
        subviews[count].place(
            at: CGPoint(x: bounds.maxX, y: bounds.midY),
            anchor: .trailing,
            proposal: btnProposal
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
