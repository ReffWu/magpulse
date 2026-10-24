import Foundation
import Combine
import CoreGraphics
import AppKit
import SQLite3

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
    
    public func triggerTest(state: MagPulseState, duration: TimeInterval = 4.0) {
        isTesting = true
        testState = state
        HardwareController.shared.setState(state)
        DispatchQueue.main.async { [weak self] in
            self?.effectiveState = state
        }
        
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
        
        // D. Claude Code CLI 活跃检测
        if enabled.contains("claude_code") {
            let isClaudeRunning = isClaudeCodeActive()
            handleWatchdogLevel(toolId: "claude_code", isRunning: isClaudeRunning)
        }
        
        // E. ChatGPT 桌面版检测
        if enabled.contains("chatgpt_desktop") {
            let isChatGPTBusy = isChatGPTAppBusy()
            handleWatchdogLevel(toolId: "chatgpt_desktop", isRunning: isChatGPTBusy)
        }
    }
    
    /// ChatGPT 桌面版活跃计算检测 (CPU > 20% 时判定为深度执行)
    private func isChatGPTAppBusy() -> Bool {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", """
        for pid in $(pgrep -f "ChatGPT.app/Contents/MacOS/ChatGPT" 2>/dev/null); do
            cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null | tr -d ' ')
            is_busy=$(awk -v c="$cpu" 'BEGIN {print (c > 20.0) ? "1" : "0"}')
            if [ "$is_busy" = "1" ]; then
                exit 0
            fi
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
    
    /// Claude Code CLI 活跃检测
    private func isClaudeCodeActive() -> Bool {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", """
        for pid in $(pgrep -f "claude" 2>/dev/null); do
            cmd=$(ps -p $pid -o command= 2>/dev/null)
            case "$cmd" in
                *magsafe*|*MagPulse*|*grep*|*python*)
                    ;;
                *bin/claude*|*@anthropic-ai/claude-code*)
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
    
    /// Antigravity 官方原生状态检测 (毫秒级零延迟)：
    /// 1. 进程前置检测：确保 com.google.antigravity 正在运行
    /// 2. 官方真理源数据库：直接以只读模式查询 Antigravity 本地状态库 (~/.gemini/antigravity/conversation_summaries.db)
    ///    官方原生字段：status == 'CASCADE_RUN_STATUS_RUNNING' 或 not_fully_idle == 1 表示模型思考、工具执行或流式生成中
    ///    一旦回答完毕进入等待用户输入状态，官方瞬间切回 CASCADE_RUN_STATUS_IDLE 且 not_fully_idle = 0，实现 0 秒瞬时感知完成！
    private func isAntigravityActive() -> Bool {
        // A. 进程前置校验：如果 Antigravity 应用未启动，直接判定为非活跃
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.antigravity")
        guard !apps.isEmpty else { return false }
        
        // B. 官方 SQLite 状态库只读检索 (耗时 ~1ms，WAL 模式零锁竞争)
        let home = NSHomeDirectory()
        let dbPath = (home as NSString).appendingPathComponent(".gemini/antigravity/conversation_summaries.db")
        
        var db: OpaquePointer?
        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK {
            defer { sqlite3_close(db) }
            var stmt: OpaquePointer?
            let sql = """
            SELECT 1 FROM conversation_summaries 
            WHERE killed = 0 AND (not_fully_idle = 1 OR status = 'CASCADE_RUN_STATUS_RUNNING') 
            LIMIT 1;
            """
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                defer { sqlite3_finalize(stmt) }
                if sqlite3_step(stmt) == SQLITE_ROW {
                    return true
                }
            }
        }
        
        return false
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
    
    /// 智能已读与完成态消弭引擎：
    /// 精准仲裁“任务已完成 (DONE 绿灯)”何时平滑转入“日常待命 (IDLE)”
    private func checkDoneAcknowledgment() {
        let frontBundle = getFrontmostBundleId()
        let idleSec = getSystemIdleSeconds()
        let now = Date()
        
        for (toolId, state) in toolStates where state == .done {
            guard let enterTime = toolDoneEnterTime[toolId] else { continue }
            let elapsed = now.timeIntervalSince(enterTime)
            let wasAway = toolDoneWasAway[toolId] ?? false
            
            // 如果键盘鼠标空闲超过 8 秒，标记为用户处于离开/未关注状态
            if idleSec > 8.0 {
                toolDoneWasAway[toolId] = true
            }
            
            let isForeground = isToolForeground(toolId: toolId, bundleId: frontBundle)
            
            // 【条件 1：全局最大保底】最长闪烁提示 30 秒，无论是否切回均自动优雅归位待机，绝不无休止闪烁
            if elapsed >= 30.0 {
                internalSetToolState(toolId: toolId, state: .idle)
                continue
            }
            
            // 【条件 2：智能已阅消弭】若用户此前离开或切至其他应用，现在切回工作窗口并产生交互（键盘/鼠标活跃），阅读 1.5 秒后自动消除
            if wasAway {
                if isForeground && idleSec < 3.0 && elapsed >= 1.5 {
                    internalSetToolState(toolId: toolId, state: .idle)
                }
            } else {
                // 【条件 3：在场直面完成】用户一直在该工作窗口前盯着完成，充分提示 10 秒后自动平滑归位待机
                if elapsed >= 10.0 {
                    internalSetToolState(toolId: toolId, state: .idle)
                } else if !isForeground && idleSec < 2.0 {
                    // 若完成初期用户主动切离该窗口，转入离开关注模式
                    toolDoneWasAway[toolId] = true
                }
            }
        }
    }
    
    /// 前台关联窗口判定：
    /// 涵盖原生应用、IDE 编辑器及各种终端宿主（支持内置终端运行 CLI）
    private func isToolForeground(toolId: String, bundleId: String) -> Bool {
        let b = bundleId.lowercased()
        switch toolId {
        case "claude_desktop":
            return b == "com.anthropic.claudefordesktop"
        case "chatgpt_desktop":
            return b == "com.openai.codex" || b.contains("chatgpt")
        case "antigravity":
            return b == "com.google.antigravity"
        case "cursor":
            return b.contains("cursor")
        case "vscode":
            return b == "com.microsoft.vscode"
        case "xcode":
            return b.contains("xcode")
        case "terminal", "claude_code", "codex":
            // CLI 类工具：不仅支持原生终端/iTerm/Warp，也全面兼容在 Antigravity/VSCode/Cursor 内置终端中执行
            return b.contains("terminal") || b.contains("iterm") || b.contains("warp") ||
                   b.contains("ghostty") || b == "com.google.antigravity" ||
                   b.contains("cursor") || b == "com.microsoft.vscode"
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
