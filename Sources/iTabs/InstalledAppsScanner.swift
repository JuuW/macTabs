import AppKit

/// 系统中一个已安装的应用
struct InstalledApp: Identifiable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let url: URL
    let icon: NSImage
}

/// 枚举系统已安装的应用,供设置窗口勾选。
/// 扫描标准应用目录,读取每个 .app 的 bundle id、显示名与图标。
enum InstalledAppsScanner {
    private static let searchPaths: [String] = [
        "/Applications",
        "/System/Applications",
        "/System/Applications/Utilities",
        "\(NSHomeDirectory())/Applications"
    ]

    /// 返回按名称排序、去重(按 bundle id)的已安装应用列表
    static func scan() -> [InstalledApp] {
        let fm = FileManager.default
        var seen = Set<String>()
        var result: [InstalledApp] = []

        for path in searchPaths {
            guard let entries = try? fm.contentsOfDirectory(atPath: path) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let appURL = URL(fileURLWithPath: path).appendingPathComponent(entry)
                guard let bundle = Bundle(url: appURL),
                      let bundleID = bundle.bundleIdentifier,
                      !seen.contains(bundleID) else { continue }
                seen.insert(bundleID)

                let name = displayName(for: appURL, bundle: bundle, fallback: entry)
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                icon.size = NSSize(width: 32, height: 32)
                result.append(InstalledApp(bundleID: bundleID, name: name, url: appURL, icon: icon))
            }
        }

        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func displayName(for url: URL, bundle: Bundle, fallback: String) -> String {
        if let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !name.isEmpty {
            return name
        }
        if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String, !name.isEmpty {
            return name
        }
        return fallback.replacingOccurrences(of: ".app", with: "")
    }
}
