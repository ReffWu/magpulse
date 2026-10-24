import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var cancellables = Set<AnyCancellable>()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        setupPopover()
        setupStatusItem()
        bindState()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        HardwareController.shared.stopEngine()
    }
    
    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 460)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: PopoverView())
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = MagSafeIconFactory.makeIcon(
                colorState: HardwareController.shared.currentHardwareColor,
                isEnabled: AppSettings.shared.isEnabled
            )
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseDown])
        }
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
        .sink { [weak self] colorState, isEnabled in
            guard let self = self, let button = self.statusItem.button else { return }
            button.image = MagSafeIconFactory.makeIcon(
                colorState: colorState,
                isEnabled: isEnabled
            )
        }
        .store(in: &cancellables)
    }
}

// App 入口
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
