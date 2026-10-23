/// InstantSpacesManager.swift

import Cocoa

/// Replaces the animated trackpad swipe between Spaces with an instant switch.
/// The gesture interception lives in ISS.c, adapted from InstantSpaceSwitcher.
class InstantSpacesManager {
    private var spaceChangeObserver: NSObjectProtocol?

    init() {
        toggleListening()
        Notification.Name.instantSpaceSwitching.onPost { notification in
            self.toggleListening()
        }
        Notification.Name.configImported.onPost { notification in
            self.toggleListening()
        }
    }

    private func toggleListening() {
        if Defaults.instantSpaceSwitching.enabled {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard iss_init() else {
            Logger.log("Instant space switching: unable to create the event tap")
            return
        }
        // Lets swipes pass through untouched while App Exposé is open
        iss_set_overlay_detection_enabled(true)
        iss_set_swipe_override(true)

        if spaceChangeObserver == nil {
            spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { _ in
                iss_reset_predictions()
            }
        }
    }

    private func stop() {
        iss_set_swipe_override(false)
        iss_destroy()

        if let observer = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            spaceChangeObserver = nil
        }
    }
}
