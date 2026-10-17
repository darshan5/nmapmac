#if DEBUG
import AppKit

/// Development aid: with NMAPMAC_SNAPSHOT=/path/prefix set, renders the main
/// window to PNGs, one per tab, so the UI can be checked without screen
/// recording permission.
@MainActor
enum DebugSnapshot {
    static func scheduleIfRequested() {
        guard let prefix = ProcessInfo.processInfo.environment["NMAPMAC_SNAPSHOT"] else { return }
        let tabs = ProcessInfo.processInfo.environment["NMAPMAC_SNAPSHOT_TABS"]?
            .split(separator: ",").map(String.init) ?? []
        // Files to load, passed this way so a running copy of the app doesn't receive them.
        if let files = ProcessInfo.processInfo.environment["NMAPMAC_SNAPSHOT_OPEN"] {
            PendingFiles.shared.urls += files.split(separator: ":").map { URL(fileURLWithPath: String($0)) }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if let target = ProcessInfo.processInfo.environment["NMAPMAC_SNAPSHOT_SCAN"] {
                NotificationCenter.default.post(name: .debugScan, object: target)
                try? await Task.sleep(for: .seconds(25))
            }
            if tabs.isEmpty {
                capture(to: "\(prefix).png")
            }
            for tab in tabs {
                NotificationCenter.default.post(name: .debugSelectTab, object: tab)
                try? await Task.sleep(for: .seconds(1))
                capture(to: "\(prefix)-\(tab.filter { $0.isLetter }).png")
            }
            if ProcessInfo.processInfo.environment["NMAPMAC_SNAPSHOT_QUIT"] != nil {
                NSApp.terminate(nil)
            }
        }
    }

    static func capture(to path: String) {
        // Popovers live in their own windows; save them alongside.
        for (i, window) in NSApp.windows.enumerated()
        where window.isVisible && String(describing: type(of: window)).contains("Popover") {
            if let view = window.contentView?.superview ?? window.contentView,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: path.replacingOccurrences(of: ".png", with: "-popover\(i).png")))
            }
        }
        guard let main = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }),
              case let window = main.attachedSheet ?? main,
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}

extension Notification.Name {
    static let debugSelectTab = Notification.Name("NMapMacDebugSelectTab")
    static let debugScan = Notification.Name("NMapMacDebugScan")
}
#endif
