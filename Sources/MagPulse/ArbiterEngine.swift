import Foundation
import Combine
import CoreGraphics
import AppKit

public final class ArbiterEngine: ObservableObject {
    public static let shared = ArbiterEngine()
    
    @Published public private(set) var effectiveState: MagPulseState = .idle
    @Published public private(set) var toolStates: [String: MagPulseState] = [:]
    
    // 专用高性能后台队列，彻底隔离主线程，杜绝任何 UI 卡顿
    private let bgQueue = DispatchQueue(label: "com.reff.magpulse.engine", qos: .utility)
    private var bgTimer: DispatchSourceTimer?
    
    private var testTimer: Timer?
    private var isTesting = false
    private var testState: MagPulseState = .idle
    
    private var lastStateFileMtime: Date = .distantPast
    private var lastAgentFileMtime: Date = .distantPast
    
    // 跟踪正在被看门狗监控的活跃工具
    private var activeWatchdogTools: Set<String> = []
    
    // 跟踪各个工具进入 DONE 的时间与前台上下文
    private var toolDoneEnterTime: [String: Date] = [:]
    private var toolDoneWasAway: [String: Bool] = [:]
    
    private let stateFilePath = "/tmp/claude_magsafe_state"
    private let agentFilePath = "/tmp/magsafe_agent_state"
    
    private init() {
        // 初始化默认待命状态
        for tool in AppSettings.allAvailableTools {
            toolStates[tool.id] = .idle
        }
        
        startMonitoring()
    }
    
    public func startMonitoring() {
        bgQueue.async { [weak self] in
            guard let self = self else { return }
            self.bgTimer?.cancel()
            let timer = DispatchSource.makeTimerSource(queue: self.bgQueue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(700), leeway: .milliseconds(100))
            timer.setEventHandler { [weak self] in
                self?.bgTick()
            }
            self.bgTimer = timer
            timer.resume()
        }
    }
    
    public func stopMonitoring() {
        bgQueue.async { [weak self] in
            self?.bgTimer?.cancel()
            self?.bgTimer = nil
            HardwareController.shared.setState(.idle)
            DispatchQueue.main.async {
                self?.effectiveState = .idle
            }
        }
    }
    
    public func triggerTest(state: MagPulseState, duration: TimeInterval = 5.0) {
        isTesting = true
        testState = state
        HardwareController.shared.setState(state)
        
        testTimer?.invalidate()
        testTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.isTesting = false
            self?.bgQueue.async {
                self?.recalculateEffectiveState()
            }
        }
    }
    
    public func setToolState(toolId: String, state: MagPulseState) {
        bgQueue.async { [weak self] in
            guard let self = self else { return }
            self.internalSetToolState(toolId: toolId, state: state)
            self.recalculateEffectiveState()
        }
    }
    
    private func internalSetToolState(toolId: String, state: MagPulseState) {
        toolStates[toolId] = state
        if state == .done {
            toolDoneEnterTime[toolId] = Date()
            let idleSec = getSystemIdleSeconds()
            let frontBundle = getFrontmostBundleId()
            let isForeground = isToolForeground(toolId: toolId, bundleId: frontBundle)
            toolDoneWasAway[toolId] = (idleSec > 10.0 || !isForeground)
        }
        
        let snapshot = toolStates
        DispatchQueue.main.async { [weak self] in
            self?.toolStates = snapshot
        }
    }
    
    // 全部后台运行，毫秒级轻快，绝对不碰主线程
    private func bgTick() {
        guard AppSettings.shared.isEnabled else {
            if effectiveState != .idle {
                HardwareController.shared.setState(.idle)
                DispatchQueue.main.async { [weak self] in
                    self?.effectiveState = .idle
                }
            }
            return
        }
        
        // 1. 检查临时文件信号总线
        checkFileSignals()
        
        // 2. 检查系统进程看门狗
        checkProcessWatchdog()
        
        // 3. 检查智能已读解除
        checkDoneAcknowledgment()
        
        // 4. 计算仲裁结果
        if !isTesting {
            recalculateEffectiveState()
        }
    }
    
    private func recalculateEffectiveState() {
        guard AppSettings.shared.isEnabled else {
            HardwareController.shared.setState(.idle)
            DispatchQueue.main.async { [weak self] in
                self?.effectiveState = .idle
            }
            return
        }
        
        let enabled = AppSettings.shared.enabledToolIds
        let activeStates = toolStates.filter { enabled.contains($0.key) }.values
        
        let newEffective: MagPulseState
        if activeStates.contains(.permission) {
            newEffective = .permission
        } else if activeStates.contains(.busy) {
            newEffective = .busy
        } else if activeStates.contains(.done) {
            newEffective = .done
        } else {
            newEffective = .idle
        }
        
        HardwareController.shared.setState(newEffective)
        DispatchQueue.main.async { [weak self] in
            if self?.effectiveState != newEffective {
                self?.effectiveState = newEffective
            }
        }
    }
    
    private func checkFileSignals() {
        // 检查 /tmp/claude_magsafe_state
        if let attrs = try? FileManager.default.attributesOfItem(atPath: stateFilePath),
           let mtime = attrs[.modificationDate] as? Date,
           mtime > lastStateFileMtime {
            lastStateFileMtime = mtime
            if let content = try? String(contentsOfFile: stateFilePath, encoding: .utf8) {
                let raw = content.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if let st = MagPulseState(rawValue: raw) {
                    internalSetToolState(toolId: "claude_code", state: st)
                    internalSetToolState(toolId: "claude_desktop", state: st)
                }
            }
        }
        
        // 检查 /tmp/magsafe_agent_state (格式: toolId:STATE 或 直接 STATE)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: agentFilePath),
           let mtime = attrs[.modificationDate] as? Date,
           mtime > lastAgentFileMtime {
            lastAgentFileMtime = mtime
            if let content = try? String(contentsOfFile: agentFilePath, encoding: .utf8) {
                let lines = content.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.contains(":") {
                        let parts = trimmed.split(separator: ":", maxSplits: 1)
                        if parts.count == 2 {
                            let tid = String(parts[0]).lowercased()
                            let sRaw = String(parts[1]).uppercased()
                            if let st = MagPulseState(rawValue: sRaw) {
                                internalSetToolState(toolId: tid, state: st)
                            }
                        }
                    } else if let st = MagPulseState(rawValue: trimmed.uppercased()) {
                        internalSetToolState(toolId: "antigravity", state: st)
                    }
                }
            }
        }
    }
    
    private func checkProcessWatchdog() {
        let enabled = AppSettings.shared.enabledToolIds
        
        // A. CodeX CLI 检测 (排除 ChatGPT.app 自带的后台常驻 host 进程)
        if enabled.contains("codex") {
            let isCodexRunning = isCodexProcessActive()
            handleWatchdogLevel(toolId: "codex", isRunning: isCodexRunning)
        }
        
        // B. Xcode / xcodebuild 检测 (真正编译构建工具链活动)
        if enabled.contains("xcode") {
            let isXcodeBuilding = isXcodeBuildingActive()
            handleWatchdogLevel(toolId: "xcode", isRunning: isXcodeBuilding)
        }
        
        // C. Antigravity 深度联动检测 (排除 6 个常驻 MCP，检测真实任务与高负荷生成)
        if enabled.contains("antigravity") {
            let isAntigravityRunning = isAntigravityActive()
            handleWatchdogLevel(toolId: "antigravity", isRunning: isAntigravityRunning)
        }
    }
    
    /// Antigravity 活跃检测：
    /// 1. 进程是否开启
    /// 2. 是否有除常驻 MCP 外的命令子进程 (如正在执行 run_command, git, 脚本等)
    /// 3. language_server 是否处于高 CPU 密集推理/流式输出 (> 15%)
    private func isAntigravityActive() -> Bool {
        let apps = NSWorkspace.shared.runningApplications
        let hasAntigravityApp = apps.contains { $0.bundleIdentifier == "com.google.antigravity" }
        if !hasAntigravityApp {
            return false
        }
        
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", """
        ps -ax -o pid,%cpu,command | while read -r pid cpu cmd; do
            case "$cmd" in
                *Antigravity.app*language_server*)
                    # 1. 检查 CPU 是否密集生成 (> 15.0)
                    is_busy=$(awk -v c="$cpu" 'BEGIN {print (c > 15.0) ? "1" : "0"}')
                    if [ "$is_busy" = "1" ]; then
                        exit 0
                    fi
                    
                    # 2. 检查是否有执行外部命令的子进程 (排除常驻 MCP)
                    for cp in $(pgrep -P "$pid" 2>/dev/null); do
                        c_cmd=$(ps -p "$cp" -o command= 2>/dev/null)
                        case "$c_cmd" in
                            *workspace-mcp*|*perplexica-mcp*|*rea-agents*|*open-computer-use*|*mcp-searxng*|*" mcp"*)
                                ;;
                            *)
                                if [ -n "$c_cmd" ]; then
                                    exit 0
                                fi
                                ;;
                        esac
                    done
                    ;;
            esac
        done
        exit 1
        """]
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    /// CodeX CLI 活跃检测：
    /// 必须绝对排除 /Applications/ChatGPT.app/ 内部的所有常驻服务与辅助进程！
    private func isCodexProcessActive() -> Bool {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", """
        for pid in $(pgrep -f "codex" 2>/dev/null); do
            cmd=$(ps -p $pid -o command= 2>/dev/null)
            case "$cmd" in
                *ChatGPT.app*|*codex-code-mode-host*|*codex.system*|*mcp-searxng*|*rea-agents*|*magsafe*|*MagPulse*)
                    ;;
                *@openai/codex*|*bin/codex*|"codex "*)
                    exit 0
                    ;;
            esac
        done
        exit 1
        """]
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    /// Xcode 构建检测：
    /// 仅在发生实际编译构建打包时触发 (xcodebuild 或派生编译器工具链)
    private func isXcodeBuildingActive() -> Bool {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", """
        if pgrep -f "xcodebuild" >/dev/null 2>&1; then
            exit 0
        fi
        for pid in $(pgrep -f "swiftc|swift-frontend|clang|actool|ibtool" 2>/dev/null); do
            cmd=$(ps -p "$pid" -o command= 2>/dev/null)
            case "$cmd" in
                *Xcode.app*|*Developer/Toolchains*)
                    exit 0
                    ;;
            esac
        done
        exit 1
        """]
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
    

    /// 电平优先、具备自愈纠偏能力的看门狗状态转换
    private func handleWatchdogLevel(toolId: String, isRunning: Bool) {
        let currentState = toolStates[toolId] ?? .idle
        let wasActive = activeWatchdogTools.contains(toolId)
        
        if isRunning {
            if !wasActive || currentState != .busy {
                activeWatchdogTools.insert(toolId)
                internalSetToolState(toolId: toolId, state: .busy)
            }
        } else {
            if wasActive {
                // 刚由活跃变为停止：提示已完成
                activeWatchdogTools.remove(toolId)
                internalSetToolState(toolId: toolId, state: .done)
            } else if currentState == .busy {
                // 自愈纠偏：明明没有在运行，状态机却被错误设为 busy，坚决修正回 idle！
                internalSetToolState(toolId: toolId, state: .idle)
            }
        }
    }
    
    private func checkDoneAcknowledgment() {
        let frontBundle = getFrontmostBundleId()
        let idleSec = getSystemIdleSeconds()
        let now = Date()
        
        for (toolId, state) in toolStates where state == .done {
            guard let enterTime = toolDoneEnterTime[toolId] else { continue }
            let elapsed = now.timeIntervalSince(enterTime)
            let wasAway = toolDoneWasAway[toolId] ?? false
            
            if idleSec > 10.0 {
                toolDoneWasAway[toolId] = true
            }
            
            let isForeground = isToolForeground(toolId: toolId, bundleId: frontBundle)
            
            if wasAway {
                if isForeground && idleSec < 3.0 && elapsed >= 1.5 {
                    internalSetToolState(toolId: toolId, state: .idle)
                }
            } else {
                if elapsed >= 15.0 {
                    internalSetToolState(toolId: toolId, state: .idle)
                } else if !isForeground && idleSec < 2.0 {
                    toolDoneWasAway[toolId] = true
                }
            }
        }
    }
    
    private func isToolForeground(toolId: String, bundleId: String) -> Bool {
        switch toolId {
        case "claude_desktop":
            return bundleId == "com.anthropic.claudefordesktop"
        case "antigravity":
            return bundleId == "com.google.antigravity"
        case "cursor":
            return bundleId.contains("cursor")
        case "vscode":
            return bundleId == "com.microsoft.VSCode"
        case "xcode":
            return bundleId == "com.apple.dt.Xcode"
        case "terminal", "claude_code", "codex":
            return bundleId == "com.apple.Terminal" || bundleId.contains("iterm") || bundleId.contains("terminal")
        default:
            return false
        }
    }
    
    private func getSystemIdleSeconds() -> Double {
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0) ?? .null)
    }
    
    private func getFrontmostBundleId() -> String {
        if Thread.isMainThread {
            return NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        } else {
            var bid = ""
            DispatchQueue.main.sync {
                bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
            }
            return bid
        }
    }
}
