import SwiftUI

public struct PopoverView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var arbiter = ArbiterEngine.shared
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // 1. 顶部状态卡片
            headerCard
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
            
            Divider()
                .opacity(0.15)
            
            // 2. 工具选择列表
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    sectionTitle("联动监控目标", icon: "target")
                    
                    VStack(spacing: 6) {
                        ForEach(AppSettings.allAvailableTools) { tool in
                            toolRow(tool)
                        }
                    }
                    
                    Divider()
                        .opacity(0.12)
                        .padding(.vertical, 4)
                    
                    sectionTitle("物理灯效速测", icon: "sparkle")
                    
                    testButtonGroup
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .frame(maxHeight: 330)
            
            Divider()
                .opacity(0.15)
            
            // 3. 底部操作栏
            footerBar
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .frame(width: 320, height: 460)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
    }
    
    // MARK: - Components
    
    private var headerCard: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(stateAccentColor)
                    
                    Text("MagPulse")
                        .font(.system(size: 15, weight: .semibold))
                }
                
                Spacer()
                
                Toggle("", isOn: $settings.isEnabled)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
            }
            
            // 当前硬件律动状态提示
            HStack(spacing: 8) {
                Circle()
                    .fill(stateAccentColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: stateAccentColor.opacity(0.6), radius: 3)
                
                Text(settings.isEnabled ? arbiter.effectiveState.displayName : "联动已暂停 (系统充电中)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(settings.isEnabled ? arbiter.effectiveState.rhythmDescription : "原生默认")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        }
    }
    
    private func sectionTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            Spacer()
        }
    }
    
    private func toolRow(_ tool: MonitoredTool) -> some View {
        let isChecked = settings.isToolEnabled(tool.id)
        let toolState = arbiter.toolStates[tool.id] ?? .idle
        
        return Button(action: {
            settings.toggleTool(tool.id)
        }) {
            HStack(spacing: 10) {
                Image(systemName: tool.icon)
                    .font(.system(size: 13))
                    .foregroundColor(isChecked ? .primary : .secondary.opacity(0.5))
                    .frame(width: 18)
                
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(tool.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(isChecked ? .primary : .secondary)
                        
                        if isChecked && toolState != .idle {
                            Text(toolState.rawValue)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(toolStateBadgeColor(toolState).opacity(0.2))
                                .foregroundColor(toolStateBadgeColor(toolState))
                                .cornerRadius(4)
                        }
                    }
                    
                    Text(tool.detail)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                
                Spacer()
                
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(isChecked ? .accentColor : .secondary.opacity(0.4))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(isChecked ? Color.primary.opacity(0.03) : Color.clear))
        }
        .buttonStyle(.plain)
    }
    
    private var testButtonGroup: some View {
        HStack(spacing: 6) {
            testButton(title: "橙色呼吸", color: .orange) {
                arbiter.triggerTest(state: .busy, duration: 4.0)
            }
            testButton(title: "绿色慢闪", color: .green) {
                arbiter.triggerTest(state: .done, duration: 4.0)
            }
            testButton(title: "黄绿跳动", color: .yellow) {
                arbiter.triggerTest(state: .permission, duration: 4.0)
            }
            testButton(title: "系统默认", color: .gray) {
                arbiter.triggerTest(state: .idle, duration: 1.0)
            }
        }
    }
    
    private func testButton(title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(color.opacity(0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
    
    private var footerBar: some View {
        HStack {
            Toggle("开机自启", isOn: $settings.launchAtLogin)
                .font(.system(size: 11))
                .toggleStyle(CheckboxToggleStyle())
            
            Spacer()
            
            Button("退出") {
                NSApp.terminate(nil)
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Helpers
    
    private var stateAccentColor: Color {
        guard settings.isEnabled else { return .secondary }
        switch arbiter.effectiveState {
        case .idle: return .secondary
        case .busy: return .orange
        case .done: return .green
        case .permission: return .yellow
        }
    }
    
    private func toolStateBadgeColor(_ state: MagPulseState) -> Color {
        switch state {
        case .busy: return .orange
        case .done: return .green
        case .permission: return .yellow
        case .idle: return .secondary
        }
    }
}

// macOS 经典原生毛玻璃容器
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }
    
    func updateNSView(_ visualEffectView: NSVisualEffectView, context: Context) {
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
    }
}
