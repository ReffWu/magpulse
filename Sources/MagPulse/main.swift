import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var cancellables = Set<AnyCancellable>()
    private var batteryTimer: Timer?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        setupPopover()
        setupStatusItem()
        bindState()
        observeSystemTheme()
        startBatteryPolling()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        batteryTimer?.invalidate()
        HardwareController.shared.stopEngine()
    }
    
    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 330, height: 510)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: PopoverView())
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            refreshButtonImage()
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseDown])
        }
    }
    
    private func refreshButtonImage() {
        guard let button = statusItem?.button else { return }
        button.image = MagSafeIconFactory.makeIcon(
            colorState: HardwareController.shared.currentHardwareColor,
            isEnabled: AppSettings.shared.isEnabled
        )
    }
    
    @objc private func statusItemClicked() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    
    private func bindState() {
        // 双向联动：无论是硬件颜色改变（呼吸/跳动），还是主开关切换，瞬间刷新菜单栏图标
        Publishers.CombineLatest(
            HardwareController.shared.$currentHardwareColor,
            AppSettings.shared.$isEnabled
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _ in
            self?.refreshButtonImage()
        }
        .store(in: &cancellables)
    }
    
    private func observeSystemTheme() {
        // 监听系统深浅外观切换，瞬间刷新菜单栏自适应色
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshButtonImage()
        }
    }
    
    private func startBatteryPolling() {
        // 在待命状态下，低频感知系统电源插拔与充满状态，确保灯光 100% 实时同步
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            if HardwareController.shared.currentHardwareColor == "system" {
                self?.refreshButtonImage()
            }
        }
    }
}

// App 入口
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
