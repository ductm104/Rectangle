/// InstantSpacesManager.swift

import Cocoa

/// Switches Spaces without the slide animation, both for trackpad swipes and
/// for the Switch to Space shortcuts. The switching itself lives in ISS.c,
/// adapted from InstantSpaceSwitcher.
class InstantSpacesManager {
    private struct SpaceHistory {
        var current: UInt32
        var last: UInt32?
    }

    /// Keyed by display UUID, since every display has its own Spaces
    private static var spaceHistories = [String: SpaceHistory]()

    private var spaceChangeObserver: NSObjectProtocol?

    init() {
        iss_set_switch_callback { newSpaceIndex in
            DispatchQueue.main.async {
                InstantSpacesManager.didSwitch(to: newSpaceIndex)
            }
        }

        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            iss_reset_predictions()
            // Our own switches report every Space they pass through. The switch
            // callback has already recorded where they land.
            guard !iss_switch_in_progress() else { return }
            InstantSpacesManager.recordCurrentSpace()
        }
        Self.recordCurrentSpace()

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
            guard Self.prepare() else { return }
            iss_set_swipe_override(true)
        } else {
            iss_set_swipe_override(false)
            // The Switch to Space shortcuts set the tap up again when they're used
            iss_destroy()
        }
    }

    @discardableResult
    private static func prepare() -> Bool {
        guard iss_init() else {
            Logger.log("Instant space switching: unable to create the event tap")
            return false
        }
        // Lets swipes pass through untouched while App Exposé is open, and keeps
        // the Space number out of Mission Control
        iss_set_overlay_detection_enabled(true)
        return true
    }

    static func execute(parameters: ExecutionParameters) -> Bool {
        let action = parameters.action
        guard [.spaceLeft, .spaceRight, .lastSpace].contains(action) || action.spaceIndex != nil else {
            return false
        }

        // Without the tap, quick repeats can't be tracked and overshoot the last Space
        prepare()

        let switched: Bool
        switch action {
        case .spaceLeft:
            switched = iss_switch(ISSDirectionLeft)
        case .spaceRight:
            switched = iss_switch(ISSDirectionRight)
        case .lastSpace:
            switched = switchToLastSpace()
        default:
            switched = iss_switch_to_index(UInt32(action.spaceIndex ?? 0))
        }

        if !switched {
            NSSound.beep()
        }
        return true
    }

    private static func switchToLastSpace() -> Bool {
        guard let displayID = cursorDisplaySpace()?.displayID,
              let history = spaceHistories[displayID],
              let last = history.last,
              last != history.current
        else { return false }

        return iss_switch_to_index(last)
    }

    private static func didSwitch(to spaceIndex: UInt32) {
        if let displayID = cursorDisplaySpace()?.displayID {
            record(spaceIndex, on: displayID)
        }
        SpaceNumberOSD.shared.show(spaceNumber: Int(spaceIndex) + 1)
    }

    private static func recordCurrentSpace() {
        guard let space = cursorDisplaySpace() else { return }
        record(space.index, on: space.displayID)
    }

    private static func record(_ spaceIndex: UInt32, on displayID: String) {
        guard let history = spaceHistories[displayID] else {
            spaceHistories[displayID] = SpaceHistory(current: spaceIndex)
            return
        }
        guard history.current != spaceIndex else { return }
        spaceHistories[displayID] = SpaceHistory(current: spaceIndex, last: history.current)
    }

    /// The display under the cursor is the one ISS switches
    private static func cursorDisplaySpace() -> (displayID: String, index: UInt32)? {
        var info = ISSSpaceInfo()
        guard iss_get_space_info(&info) else { return nil }
        let displayID = withUnsafeBytes(of: info.displayID) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        return (displayID, info.currentIndex)
    }
}
