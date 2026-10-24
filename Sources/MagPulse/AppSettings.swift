import Foundation
import Combine

public struct MonitoredTool: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let group: String       // "桌面应用" 或 "命令行终端"
    public let iconName: String    // 对应 Resources/Icons/<iconName>.png
    public let fallbackSF: String  // 备用 SF Symbol
    public let detail: String
    
    public init(id: String, name: String, group: String, iconName: String, fallbackSF: String, detail: String) {
        self.id = id
        self.name = name
        self.group = group
        self.iconName = iconName
        self.fallbackSF = fallbackSF
        self.detail = detail
    }
}

public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()
    
    // 分组 1: 桌面应用 (Desktop Apps)
    public static let desktopApps: [MonitoredTool] = [
        MonitoredTool(id: "antigravity", name: "Antigravity", group: "桌面应用", iconName: "antigravity", fallbackSF: "wand.and.stars", detail: "Google DeepMind 编程助手"),
        MonitoredTool(id: "claude_desktop", name: "Claude Desktop", group: "桌面应用", iconName: "claude_desktop", fallbackSF: "sparkles", detail: "Anthropic Claude 桌面客户端"),
        MonitoredTool(id: "chatgpt_desktop", name: "ChatGPT (Code Mode)", group: "桌面应用", iconName: "chatgpt_desktop", fallbackSF: "bubble.left.and.text.bubble.right", detail: "OpenAI ChatGPT 桌面客户端"),
        MonitoredTool(id: "cursor", name: "Cursor", group: "桌面应用", iconName: "cursor", fallbackSF: "curlybraces", detail: "Cursor IDE 智能编程编辑器"),
        MonitoredTool(id: "vscode", name: "Visual Studio Code", group: "桌面应用", iconName: "vscode", fallbackSF: "doc.text.below.ecg", detail: "VS Code 构建与智能任务"),
        MonitoredTool(id: "xcode", name: "Xcode / xcodebuild", group: "桌面应用", iconName: "xcode", fallbackSF: "hammer", detail: "Apple 原生编译构建与打包")
    ]
    
    // 分组 2: 命令行与终端 (CLI / Terminal)
    public static let cliTools: [MonitoredTool] = [
        MonitoredTool(id: "claude_code", name: "Claude Code CLI", group: "命令行终端", iconName: "claude_code", fallbackSF: "terminal", detail: "终端 claude 命令行智能助手"),
        MonitoredTool(id: "codex", name: "CodeX CLI", group: "命令行终端", iconName: "codex", fallbackSF: "chevron.left.forwardslash.chevron.right", detail: "终端 codex 命令行智能助手"),
        MonitoredTool(id: "terminal", name: "Terminal & Shell Tasks", group: "命令行终端", iconName: "terminal", fallbackSF: "apple.terminal", detail: "系统终端耗时与编译任务")
    ]
    
    public static var allAvailableTools: [MonitoredTool] {
        return desktopApps + cliTools
    }
    
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
            // 默认勾选核心 AI 桌面与 CLI 工具
            self.enabledToolIds = ["antigravity", "claude_desktop", "chatgpt_desktop", "claude_code", "codex", "cursor", "vscode", "xcode"]
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
