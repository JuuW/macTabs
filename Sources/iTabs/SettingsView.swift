import SwiftUI
import AppKit

private final class SearchState: ObservableObject {
    @Published var text = ""
}

private final class AppsState: ObservableObject {
    @Published var apps: [InstalledApp] = []
}

/// 设置窗口内容:
///  上部——页签标题最大长度(数字输入 + 步进器)
///  下部——系统已安装 app 列表(搜索 + 勾选)。勾选即纳入受支持集合。
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @StateObject private var search = SearchState()
    @StateObject private var state = AppsState()

    private var filtered: [InstalledApp] {
        let q = search.text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return state.apps }
        return state.apps.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            $0.bundleID.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleLengthSection
            Divider()
            searchBar
            Divider()
            appList
        }
        .frame(width: 420, height: 520)
        .onAppear {
            if state.apps.isEmpty {
                state.apps = InstalledAppsScanner.scan()
            }
        }
    }

    private var titleLengthSection: some View {
        HStack(spacing: 10) {
            Text("页签标题最大长度")
                .font(.system(size: 13))
            Spacer()
            Stepper(
                value: Binding(
                    get: { settings.maxTitleLength },
                    set: { settings.maxTitleLength = $0 }
                ),
                in: SettingsStore.minTitleLength...SettingsStore.maxTitleLengthCap
            ) {
                Text("\(settings.maxTitleLength) 字符")
                    .font(.system(size: 13, weight: .medium))
                    .frame(minWidth: 56, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索应用", text: Binding(
                get: { search.text },
                set: { search.text = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 13))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var appList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filtered) { app in
                    row(app)
                    Divider().padding(.leading, 52)
                }
            }
        }
    }

    private func row(_ app: InstalledApp) -> some View {
        let on = settings.isSupported(app.bundleID)
        return HStack(spacing: 10) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(app.bundleID)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { on },
                set: { settings.setSupported(app.bundleID, $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { settings.toggle(app.bundleID) }
    }
}

/// 承载设置窗口的单例控制器,避免重复开窗
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func show() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView(settings: settings))
        let w = NSWindow(contentViewController: hosting)
        w.title = "iTabs 设置"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
