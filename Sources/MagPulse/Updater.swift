import Foundation
import Sparkle

/// 管理 MagPulse 的 Sparkle 2 自动更新与手动检查更新
@MainActor
final class Updater: NSObject, ObservableObject {
    static let shared = Updater()
    
    enum Outcome: Equatable {
        case idle
        case checking
        case upToDate(Date)
        case found(String)
        case unreachable
        case failed(String)
        case unconfigured
    }
    
    @Published private(set) var outcome: Outcome = .idle
    @Published var installsAutomatically: Bool = true {
        didSet {
            controller?.updater.automaticallyDownloadsUpdates = installsAutomatically
        }
    }
    
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.1"
    }
    
    var lastChecked: Date? {
        controller?.updater.lastUpdateCheckDate
    }
    
    static var isConfigured: Bool {
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = info["SUFeedURL"] as? String ?? ""
        let key = info["SUPublicEDKey"] as? String ?? ""
        return !feed.isEmpty && !key.isEmpty
    }
    
    private var controller: SPUStandardUpdaterController?
    
    func start() {
        guard Self.isConfigured else {
            outcome = .unconfigured
            return
        }
        
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        controller?.updater.automaticallyChecksForUpdates = true
        installsAutomatically = controller?.updater.automaticallyDownloadsUpdates ?? true
    }
    
    func checkForUpdates() {
        guard let controller else {
            outcome = .unconfigured
            return
        }
        outcome = .checking
        controller.updater.checkForUpdates()
    }
}

extension Updater: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        Task { @MainActor in
            self.outcome = .upToDate(Date())
        }
    }
    
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in
            self.outcome = .found(item.displayVersionString)
        }
    }
    
    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        Task { @MainActor in
            self.outcome = .upToDate(Date())
        }
    }
    
    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        Task { @MainActor in
            self.outcome = .failed(error.localizedDescription)
        }
    }
}
