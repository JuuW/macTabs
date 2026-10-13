import Foundation
import Combine

/// 统一管理用户配置:受支持 app 的 bundle id 集合 + 页签标题最大长度。
/// 持久化到 ~/.mactabs_settings.json。作为 ObservableObject 供 UI 观察,
/// 任一配置变更即发布,页签栏/设置窗口随之刷新。
final class SettingsStore: ObservableObject {
    /// 受支持 app 的 bundle id 集合。只有前台 app 的 bundle id 在此集合中,页签栏才显示。
    @Published private(set) var supportedApps: Set<String> = []

    /// 页签标题最大显示字符数,超出用 "..." 截断。合法范围 [minTitleLength, maxTitleLengthCap]。
    @Published var maxTitleLength: Int = defaultTitleLength {
        didSet {
            let clamped = Self.clampTitleLength(maxTitleLength)
            if clamped != maxTitleLength {
                maxTitleLength = clamped   // 触发再次 didSet,但 clamp 后幂等,立即收敛
                return
            }
            if oldValue != maxTitleLength { save() }
        }
    }

    static let defaultTitleLength = 20
    static let minTitleLength = 5
    static let maxTitleLengthCap = 100

    private let fileURL: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        fileURL = home.appendingPathComponent(".mactabs_settings.json")
        load()
    }

    static func clampTitleLength(_ n: Int) -> Int {
        min(max(n, minTitleLength), maxTitleLengthCap)
    }

    // MARK: - 受支持 app 增删

    func isSupported(_ bundleID: String) -> Bool {
        supportedApps.contains(bundleID)
    }

    func setSupported(_ bundleID: String, _ on: Bool) {
        if on { supportedApps.insert(bundleID) } else { supportedApps.remove(bundleID) }
        save()
    }

    func toggle(_ bundleID: String) {
        setSupported(bundleID, !isSupported(bundleID))
    }

    // MARK: - 持久化

    private struct Payload: Codable {
        var supportedApps: [String]
        var maxTitleLength: Int
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return
        }
        supportedApps = Set(payload.supportedApps)
        maxTitleLength = Self.clampTitleLength(payload.maxTitleLength)
    }

    private func save() {
        let payload = Payload(supportedApps: Array(supportedApps).sorted(),
                              maxTitleLength: maxTitleLength)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: fileURL)
    }
}
