import Foundation
import Combine

public struct MonitoredTool: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let category: String
    public let icon: String
    public let detail: String
    
    public init(id: String, name: String, category: String, icon: String, detail: String) {
        self.id = id
        self.name = name
        self.category = category
        self.icon = icon
        self.detail = detail
    }
}

public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()
    
    public static let allAvailableTools: [MonitoredTool] = [
        MonitoredTool(id: "claude_desktop", name: "Claude Desktop", category: "AI 助手", icon: "sparkles", detail: "Claude Mac 桌面端应用"),
        MonitoredTool(id: "claude_code", name: "Claude Code CLI", category: "AI 编程", icon: "terminal", detail: "终端 claude 命令行"),
        MonitoredTool(id: "codex", name: "CodeX CLI", category: "AI 编程", icon: "chevron.left.forwardslash.chevron.right", detail: "OpenAI CodeX 命令行"),
        MonitoredTool(id: "antigravity", name: "Antigravity", category: "AI 编程", icon: "wand.and.stars", detail: "Antigravity 编程助手"),
        MonitoredTool(id: "cursor", name: "Cursor", category: "编辑器", icon: "curlybraces", detail: "Cursor IDE 活跃执行"),
        MonitoredTool(id: "vscode", name: "Visual Studio Code", category: "编辑器", icon: "doc.text.below.ecg", detail: "VS Code 构建/任务"),
        MonitoredTool(id: "xcode", name: "Xcode / xcodebuild", category: "开发工具", icon: "hammer", detail: "原生编译与归档打包"),
        MonitoredTool(id: "terminal", name: "Terminal.app", category: "终端", icon: "apple.terminal", detail: "系统终端耗时任务")
    ]
    
    private let defaults = UserDefaults.standard
    private let kIsEnabled = "MagPulse_IsEnabled"
    private let kEnabledTools = "MagPulse_EnabledTools"
    private let kLaunchAtLogin = "MagPulse_LaunchAtLogin"
    
    @Published public var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: kIsEnabled)
        }
    }
    
    @Published public var enabledToolIds: Set<String> {
        didSet {
            defaults.set(Array(enabledToolIds), forKey: kEnabledTools)
        }
    }
    
    @Published public var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: kLaunchAtLogin)
            updateLaunchAtLogin(launchAtLogin)
        }
    }
    
    private init() {
        if defaults.object(forKey: kIsEnabled) == nil {
            self.isEnabled = true
        } else {
            self.isEnabled = defaults.bool(forKey: kIsEnabled)
        }
        
        if let saved = defaults.stringArray(forKey: kEnabledTools) {
            self.enabledToolIds = Set(saved)
        } else {
            // 默认勾选核心 AI 工具与 Xcode
            self.enabledToolIds = ["claude_desktop", "claude_code", "codex", "antigravity", "cursor", "vscode", "xcode"]
        }
        
        self.launchAtLogin = defaults.bool(forKey: kLaunchAtLogin)
    }
    
    public func isToolEnabled(_ id: String) -> Bool {
        return enabledToolIds.contains(id)
    }
    
    public func toggleTool(_ id: String) {
        if enabledToolIds.contains(id) {
            enabledToolIds.remove(id)
        } else {
            enabledToolIds.insert(id)
        }
    }
    
    private func updateLaunchAtLogin(_ enable: Bool) {
        // LaunchAgent plist 管理
        let agentsDir = ("~/Library/LaunchAgents" as NSString).expandingTildeInPath
        let agentPath = ("~/Library/LaunchAgents/com.reff.MagPulse.plist" as NSString).expandingTildeInPath
        if enable {
            try? FileManager.default.createDirectory(atPath: agentsDir, withIntermediateDirectories: true)
            let appPath = ("~/Applications/MagPulse.app/Contents/MacOS/MagPulse" as NSString).expandingTildeInPath
            let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.reff.MagPulse</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(appPath)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>KeepAlive</key>
                <true/>
            </dict>
            </plist>
            """
            try? plistContent.write(toFile: agentPath, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(atPath: agentPath)
        }
    }
}
