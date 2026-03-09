import AppKit
import CoreGraphics
import Foundation

actor WindowCatalog {
    private struct Signature: Equatable {
        let frame: CGRect
        let isMinimized: Bool
        let appIsHidden: Bool
        let isFullscreen: Bool
        let title: String?
        let isWindowlessApp: Bool
        let isOnCurrentSpace: Bool
        let isOnCurrentDisplay: Bool
        let canCaptureThumbnail: Bool
    }

    private var signaturesByWindowID: [UInt32: Signature] = [:]
    private var revisionByWindowID: [UInt32: UInt64] = [:]
    private var nextRevision: UInt64 = 1
    private var topologyVersion: UInt64 = 0

    func reconcile(rawSnapshots: [WindowSnapshot]) -> [WindowSnapshot] {
        let currentIDs = Set(rawSnapshots.map(\.windowId))
        if currentIDs != Set(signaturesByWindowID.keys) {
            topologyVersion &+= 1
        }

        var updatedSnapshots: [WindowSnapshot] = []
        updatedSnapshots.reserveCapacity(rawSnapshots.count)

        for raw in rawSnapshots {
            let tracked = track(raw)
            updatedSnapshots.append(tracked)
        }

        signaturesByWindowID = signaturesByWindowID.filter { currentIDs.contains($0.key) }
        revisionByWindowID = revisionByWindowID.filter { currentIDs.contains($0.key) }
        return updatedSnapshots
    }

    func markSystemTopologyChanged() {
        topologyVersion &+= 1
    }

    func currentTopologyVersion() -> UInt64 {
        topologyVersion
    }

    private func track(_ snapshot: WindowSnapshot) -> WindowSnapshot {
        let isOnCurrentSpace = !snapshot.isMinimized && !snapshot.appIsHidden
        let isOnCurrentDisplay = snapshot.frame.width > 1 && snapshot.frame.height > 1
            && CGDisplayBounds(CGMainDisplayID()).intersects(snapshot.frame)
        let canCaptureThumbnail = snapshot.canCaptureThumbnail
            && (!snapshot.isWindowlessApp || !SyntheticWindowID.matches(windowId: snapshot.windowId, pid: snapshot.pid))

        let signature = Signature(
            frame: snapshot.frame,
            isMinimized: snapshot.isMinimized,
            appIsHidden: snapshot.appIsHidden,
            isFullscreen: snapshot.isFullscreen,
            title: snapshot.title,
            isWindowlessApp: snapshot.isWindowlessApp,
            isOnCurrentSpace: isOnCurrentSpace,
            isOnCurrentDisplay: isOnCurrentDisplay,
            canCaptureThumbnail: canCaptureThumbnail
        )

        let revision: UInt64
        if signaturesByWindowID[snapshot.windowId] == signature,
           let existingRevision = revisionByWindowID[snapshot.windowId] {
            revision = existingRevision
        } else {
            revision = nextRevision
            nextRevision &+= 1
            revisionByWindowID[snapshot.windowId] = revision
        }

        signaturesByWindowID[snapshot.windowId] = signature
        return snapshot.withTrackingMetadata(
            isOnCurrentSpace: signature.isOnCurrentSpace,
            isOnCurrentDisplay: signature.isOnCurrentDisplay,
            canCaptureThumbnail: signature.canCaptureThumbnail,
            revision: revision
        )
    }
}

@MainActor
final class WindowCatalogMonitor {
    private let catalog: WindowCatalog
    private var observers: [NSObjectProtocol] = []

    init(catalog: WindowCatalog) {
        self.catalog = catalog
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ]

        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: OperationQueue.main) { [catalog] _ in
                Task {
                    await catalog.markSystemTopologyChanged()
                }
            }
        }
    }
}
