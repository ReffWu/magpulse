import AppKit
import SwiftUI

/// Reff Wu 独立软件矩阵与作品宣传模型
/// 数据源统一直连: https://reffwu.github.io/apps/catalog.json
@MainActor
final class MoreApps: ObservableObject {
    static let shared = MoreApps()

    struct Entry: Decodable, Identifiable, Equatable {
        let id: String
        let bundleID: String
        let name: String
        let icon: URL
        let page: URL
        let tagline: [String: String]

        func taglineInChinese() -> String {
            tagline["zh-Hans"] ?? tagline["en"] ?? ""
        }
    }

    private struct Catalog: Decodable {
        let apps: [Entry]
    }

    static let catalogURL = URL(string: "https://reffwu.github.io/apps/catalog.json")!
    private static let freshFor: TimeInterval = 24 * 60 * 60

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var icons: [String: NSImage] = [:]

    private var isLoading = false
    private let directory: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.reffwu.magpulse")
            .appendingPathComponent("MoreApps")
        
        // 预设默认生态条目（即便无网也能立刻完整展示）
        self.entries = [
            Entry(
                id: "toknotch",
                bundleID: "com.reffwu.toknotch",
                name: "TokNotch",
                icon: URL(string: "https://reffwu.github.io/apps/icons/toknotch.png?v=2")!,
                page: URL(string: "https://reffwu.github.io/apps/toknotch/")!,
                tagline: ["zh-Hans": "你的每个 AI 套餐，到底回本了几倍？"]
            ),
            Entry(
                id: "softfold",
                bundleID: "com.reffwu.softfold",
                name: "Softfold",
                icon: URL(string: "https://reffwu.github.io/apps/icons/softfold.png?v=2")!,
                page: URL(string: "https://reffwu.github.io/apps/softfold/")!,
                tagline: ["zh-Hans": "合上屏幕，桌面温柔地折叠起来。"]
            ),
            Entry(
                id: "squeeze",
                bundleID: "com.reffwu.squeeze",
                name: "Squeeze",
                icon: URL(string: "https://reffwu.github.io/apps/icons/squeeze.png?v=2")!,
                page: URL(string: "https://reffwu.github.io/apps/squeeze/")!,
                tagline: ["zh-Hans": "画质几乎零损失的 macOS 极致视频压缩工具。"]
            ),
            Entry(
                id: "statustrio",
                bundleID: "com.lingsmbp.StatusTrio",
                name: "Status Trio",
                icon: URL(string: "https://reffwu.github.io/apps/icons/statustrio.png")!,
                page: URL(string: "https://reffwu.github.io/apps/statustrio/")!,
                tagline: ["zh-Hans": "三合一菜单栏状态环。开源精选（Reff 参与贡献）"]
            )
        ]
        
        showCached()
        refreshIfStale()
    }

    private var catalogFile: URL { directory.appendingPathComponent("catalog.json") }
    private func iconFile(for entry: Entry) -> URL {
        directory.appendingPathComponent("\(entry.id).png")
    }

    func refreshIfStale() {
        guard !isLoading else { return }
        let modified = (try? catalogFile.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        if let modified, Date().timeIntervalSince(modified) < Self.freshFor { return }

        isLoading = true
        Task {
            defer { isLoading = false }
            guard let (data, response) = try? await URLSession.shared.data(from: Self.catalogURL),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let catalog = try? JSONDecoder().decode(Catalog.self, from: data)
            else { return }

            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: catalogFile)
            for entry in catalog.apps where entry.bundleID != Bundle.main.bundleIdentifier {
                if let (icon, _) = try? await URLSession.shared.data(from: entry.icon),
                   NSImage(data: icon) != nil {
                    try? icon.write(to: iconFile(for: entry))
                }
            }
            showCached()
        }
    }

    private func showCached() {
        guard let data = try? Data(contentsOf: catalogFile),
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data)
        else { return }
        let currentID = Bundle.main.bundleIdentifier ?? "com.reffwu.magpulse"
        let others = catalog.apps.filter { $0.bundleID != currentID }
        if !others.isEmpty {
            entries = others
            icons = Dictionary(uniqueKeysWithValues: others.compactMap { entry in
                NSImage(contentsOf: iconFile(for: entry)).map { (entry.id, $0) }
            })
        }
    }

    static func installedURL(for entry: Entry) -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleID) {
            return url
        }
        let commonPaths = [
            "/Applications/\(entry.name).app",
            "\(NSHomeDirectory())/Applications/\(entry.name).app"
        ]
        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }
}
