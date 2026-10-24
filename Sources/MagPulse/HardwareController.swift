import Foundation
import Combine

public enum MagPulseState: String, CaseIterable, Identifiable {
    case idle = "IDLE"
    case busy = "BUSY"
    case done = "DONE"
    case permission = "PERMISSION"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .idle: return "日常待命"
        case .busy: return "深度运算中"
        case .done: return "任务已完成"
        case .permission: return "等待决策/授权"
        }
    }
    
    public var rhythmDescription: String {
        switch self {
        case .idle: return "系统默认充电指示"
        case .busy: return "橙色慢呼吸 (1.2s 亮 / 0.8s 灭)"
        case .done: return "绿色舒缓慢闪 (1.5s 亮 / 0.5s 灭)"
        case .permission: return "橙 ↔ 绿 交替跳动 (0.6s / 0.6s)"
        }
    }
}

public final class HardwareController: ObservableObject {
    public static let shared = HardwareController()
    
    @Published public private(set) var currentHardwareColor: String = "system"
    
    private let configPath = "/Library/Application Support/MagHue/config.json"
    private let triggerPath = "/Library/Application Support/MagHue/.reload"
    
    private let condition = NSCondition()
    private var isRunning = false
    private var currentState: MagPulseState = .idle
    private var pulseThread: Thread?
    
    private var lastHardwareColor: String? = nil
    
    private init() {
        startEngine()
    }
    
    deinit {
        stopEngine()
    }
    
    public func setState(_ newState: MagPulseState) {
        condition.lock()
        if currentState != newState {
            currentState = newState
            condition.broadcast()
        }
        condition.unlock()
    }
    
    public func startEngine() {
        condition.lock()
        guard !isRunning else {
            condition.unlock()
            return
        }
        isRunning = true
        pulseThread = Thread(block: { [weak self] in
            self?.pulseLoop()
        })
        pulseThread?.name = "com.reff.magpulse.hardware"
        pulseThread?.qualityOfService = .userInteractive
        pulseThread?.start()
        condition.unlock()
    }
    
    public func stopEngine() {
        condition.lock()
        isRunning = false
        currentState = .idle
        condition.broadcast()
        condition.unlock()
        setHardwareColor("system")
    }
    
    // 毫秒级可中断睡眠：如果被状态改变唤醒返回 true，超时返回 false
    private func sleepInterruptible(_ seconds: Double) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        let targetState = currentState
        while Date() < deadline && isRunning && currentState == targetState {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { break }
            condition.wait(until: deadline)
            if currentState != targetState || !isRunning {
                return true
            }
        }
        return currentState != targetState || !isRunning
    }
    
    private func pulseLoop() {
        while true {
            condition.lock()
            if !isRunning {
                condition.unlock()
                break
            }
            let active = currentState
            condition.unlock()
            
            switch active {
            case .busy:
                // 持续橙色慢呼吸 (1.2s 亮 / 0.8s 灭)
                setHardwareColor("amber")
                condition.lock()
                if sleepInterruptible(1.2) { condition.unlock(); continue }
                condition.unlock()
                
                setHardwareColor("off")
                condition.lock()
                if sleepInterruptible(0.8) { condition.unlock(); continue }
                condition.unlock()
                
            case .done:
                // 持续纯绿舒缓慢闪 (1.5s 亮 / 0.5s 灭)
                setHardwareColor("green")
                condition.lock()
                if sleepInterruptible(1.5) { condition.unlock(); continue }
                condition.unlock()
                
                setHardwareColor("off")
                condition.lock()
                if sleepInterruptible(0.5) { condition.unlock(); continue }
                condition.unlock()
                
            case .permission:
                // 橙绿交替持续跳动 (0.6s / 0.6s)
                setHardwareColor("amber")
                condition.lock()
                if sleepInterruptible(0.6) { condition.unlock(); continue }
                condition.unlock()
                
                setHardwareColor("green")
                condition.lock()
                if sleepInterruptible(0.6) { condition.unlock(); continue }
                condition.unlock()
                
            case .idle:
                setHardwareColor("system")
                condition.lock()
                _ = sleepInterruptible(2.0)
                condition.unlock()
            }
        }
        setHardwareColor("system")
    }
    
    public func setHardwareColor(_ color: String) {
        if lastHardwareColor == color {
            return
        }
        
        let cfg: [String: Any]
        switch color {
        case "green":
            cfg = ["chargeToFull": false, "mode": "auto", "schedules": [], "threshold": 0]
        case "amber":
            cfg = ["chargeToFull": false, "mode": "auto", "schedules": [], "threshold": 101]
        case "off":
            cfg = ["chargeToFull": false, "mode": "off", "schedules": [], "threshold": 80]
        default: // "system"
            cfg = ["chargeToFull": false, "mode": "system", "schedules": [], "threshold": 80]
        }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: cfg, options: [])
            try data.write(to: URL(fileURLWithPath: configPath))
            
            // 触发目录监听器
            FileManager.default.createFile(atPath: triggerPath, contents: nil)
            try? FileManager.default.removeItem(atPath: triggerPath)
            lastHardwareColor = color
            
            DispatchQueue.main.async { [weak self] in
                self?.currentHardwareColor = color
            }
        } catch {
            // 容错处理
        }
    }
}
