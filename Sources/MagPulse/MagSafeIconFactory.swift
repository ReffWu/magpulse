import AppKit
import IOKit.ps

public final class MagSafeIconFactory {
    /// 菜单栏 MagSafe 状态图标：
    /// 极简纯白外壳结构（左线缆 + 中方块 + 右磁吸端面），
    /// 中央彻底去除任何光晕与渐变，只保留一颗纯净、饱满、高对比度的纯色实心圆点。
    public static func makeIcon(colorState: String, isEnabled: Bool) -> NSImage {
        let size = NSSize(width: 16.0, height: 17.0)
        let image = NSImage(size: size, flipped: false) { rect in
            guard NSGraphicsContext.current != nil else { return false }
            
            // 纯粹菜单栏高亮纯白
            let monoColor = NSColor.white
            let midY: CGFloat = 8.5
            
            // 1. 左边：编织线缆 (宽 3.3 pt, 厚 3.0 pt, 垂直居中)
            let cableRect = NSRect(x: 0.5, y: midY - 1.5, width: 3.3, height: 3.0)
            monoColor.setFill()
            NSBezierPath(rect: cableRect).fill()
            
            // 2. 中间：主体方块 (宽 9.1 pt, 高 14.6 pt, 纯直角没有任何圆角)
            let bodyRect = NSRect(x: 3.8, y: midY - 7.3, width: 9.1, height: 14.6)
            monoColor.setFill()
            NSBezierPath(rect: bodyRect).fill()
            
            // 3. 右边：磁吸前端小方块 (宽 1.1 pt, 高 11.4 pt, 垂直居中)
            let tipRect = NSRect(x: 13.9, y: midY - 5.7, width: 1.1, height: 11.4)
            monoColor.setFill()
            NSBezierPath(roundedRect: tipRect, xRadius: 0.35, yRadius: 0.35).fill()
            
            // 4. 正中央指示灯 (中心在 x = 8.35 pt, y = 8.5 pt)
            // 纯实心平整圆点，稍微加大一点点（半径 1.9 pt，直径 3.8 pt），完全无光晕无暗影
            let center = CGPoint(x: 8.35, y: midY)
            let ledRadius: CGFloat = 1.9
            let ledRect = NSRect(x: center.x - ledRadius, y: center.y - ledRadius, width: ledRadius * 2, height: ledRadius * 2)
            
            if !isEnabled {
                // 停用状态：浅灰点 + 红色斜杠
                NSColor(white: 0.70, alpha: 1.0).setFill()
                NSBezierPath(ovalIn: ledRect).fill()
                
                let slashPath = NSBezierPath()
                slashPath.move(to: NSPoint(x: 1.5, y: 15.5))
                slashPath.line(to: NSPoint(x: 14.5, y: 1.5))
                slashPath.lineWidth = 1.2
                NSColor.systemRed.withAlphaComponent(0.95).setStroke()
                slashPath.stroke()
                return true
            }
            
            // 决定当前发光模式
            let activeColor: String
            if colorState == "system" {
                activeColor = getSystemBatteryLightMode()
            } else {
                activeColor = colorState
            }
            
            switch activeColor {
            case "green":
                // 纯正高亮苹果翠绿
                NSColor(red: 0.12, green: 0.90, blue: 0.38, alpha: 1.0).setFill()
                NSBezierPath(ovalIn: ledRect).fill()
                
            case "amber":
                // 纯正鲜艳琥珀金橙
                NSColor(red: 1.0, green: 0.58, blue: 0.0, alpha: 1.0).setFill()
                NSBezierPath(ovalIn: ledRect).fill()
                
            case "off":
                // 律动呼吸期间的暗态间歇：浅灰色微点
                NSColor(white: 0.82, alpha: 1.0).setFill()
                NSBezierPath(ovalIn: ledRect).fill()
                
            default:
                break
            }
            
            return true
        }
        
        image.isTemplate = false
        return image
    }
    
    /// 读取系统当前实际电源充电状态
    private static func getSystemBatteryLightMode() -> String {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return "green"
        }
        
        for source in sources {
            if let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] {
                let isCharging = desc[kIOPSIsChargingKey as String] as? Bool ?? false
                if isCharging {
                    return "amber"
                }
            }
        }
        return "green"
    }
}
