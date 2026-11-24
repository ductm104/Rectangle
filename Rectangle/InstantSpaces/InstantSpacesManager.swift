/// InstantSpacesManager.swift

import Cocoa

/// Accelerates Space changes from trackpad swipes, keyboard shortcuts, and Cmd+Tab.
/// The gesture interception lives in ISS.c, adapted from InstantSpaceSwitcher.
class InstantSpacesManager {
    private static weak var activeManager: InstantSpacesManager?
    private var spaceChangeObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var recentApplications: [NSRunningApplication] = []
    private var appSwitchGeneration = 0

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
        Self.activeManager = self
        iss_set_app_switch_callback { forwardTabs in
            InstantSpacesManager.activeManager?.prepareAppSwitch(forwardTabs: forwardTabs) ?? false
        }
        rememberApplication(NSWorkspace.shared.frontmostApplication)
        if activationObserver == nil {
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] notification in
                self?.rememberApplication(notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
            }
        }

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

    private func rememberApplication(_ app: NSRunningApplication?) {
        guard let app = app, app.activationPolicy == .regular else { return }
        recentApplications.removeAll { $0.isTerminated || $0.processIdentifier == app.processIdentifier }
        recentApplications.insert(app, at: 0)
    }

    private func selectedApplicationName() -> String? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let dockElement = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(dockElement, 0.02)
        guard let children = attribute(dockElement, kAXChildrenAttribute) as? [AXUIElement],
              let switcher = children.first(where: { attribute($0, kAXSubroleAttribute) as? String == "AXProcessSwitcherList" }),
              let selected = attribute(switcher, kAXSelectedChildrenAttribute) as? [AXUIElement], selected.count == 1 else { return nil }
        return attribute(selected[0], kAXTitleAttribute) as? String
    }

    static func appSwitchTarget(forwardTabs: UInt32, recentPIDs: [pid_t], frontmostPID: pid_t?,
                                selectedPID: () -> pid_t?) -> pid_t? {
        // Dock may not expose the current selection before a quick Cmd+Tab commits.
        if forwardTabs > 0, Int(forwardTabs) < recentPIDs.count, recentPIDs[0] == frontmostPID {
            return recentPIDs[Int(forwardTabs)]
        }
        return selectedPID()
    }

    private func prepareAppSwitch(forwardTabs: UInt32) -> Bool {
        appSwitchGeneration += 1
        let frontmost = NSWorkspace.shared.frontmostApplication
        rememberApplication(frontmost)
        recentApplications.removeAll { $0.isTerminated }
        let targetPID = Self.appSwitchTarget(
            forwardTabs: forwardTabs,
            recentPIDs: recentApplications.map { $0.processIdentifier },
            frontmostPID: frontmost?.processIdentifier
        ) {
            guard let name = self.selectedApplicationName() else { return nil }
            let matches = NSWorkspace.shared.runningApplications.filter {
                $0.activationPolicy == .regular && $0.localizedName == name && !$0.isTerminated
            }
            return matches.count == 1 ? matches.first?.processIdentifier : nil
        }
        guard let targetPID = targetPID,
              let app = NSRunningApplication(processIdentifier: targetPID), !app.isTerminated else { return false }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.02)
        guard let value = attribute(appElement, kAXFocusedWindowAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return false }
        let window = value as! AXUIElement
        guard attribute(window, kAXMinimizedAttribute) as? Bool == false else { return false }
        var windowID: CGWindowID = 0
        var info = ISSSpaceInfo()
        var target: UInt32 = 0
        guard _AXUIElementGetWindow(window, &windowID) == .success,
              iss_get_window_space_target(windowID, &info, &target) else { return false }

        Logger.log("Instant space switching: Cmd+Tab from Space \(info.currentIndex) to \(target)")
        let generation = appSwitchGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self = self, generation == self.appSwitchGeneration else { return }
            var current = ISSSpaceInfo()
            guard iss_get_space_info(&current), self.sameDisplay(current, info),
                  current.currentIndex == info.currentIndex, current.spaceCount == info.spaceCount,
                  iss_switch_to_index(target) else {
                app.activate(options: [])
                return
            }
            self.activate(app, on: info, target: target, generation: generation,
                          deadline: ProcessInfo.processInfo.systemUptime + 0.35)
        }
        return true
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func sameDisplay(_ lhs: ISSSpaceInfo, _ rhs: ISSSpaceInfo) -> Bool {
        var lhs = lhs
        var rhs = rhs
        return withUnsafePointer(to: &lhs.displayID) { left in
            withUnsafePointer(to: &rhs.displayID) { right in
                strcmp(UnsafeRawPointer(left).assumingMemoryBound(to: CChar.self),
                       UnsafeRawPointer(right).assumingMemoryBound(to: CChar.self)) == 0
            }
        }
    }

    private func activate(_ app: NSRunningApplication, on display: ISSSpaceInfo, target: UInt32,
                          generation: Int, deadline: TimeInterval) {
        guard generation == appSwitchGeneration else { return }
        var current = ISSSpaceInfo()
        let arrived = iss_get_space_info(&current) && sameDisplay(current, display) && current.currentIndex == target
        if arrived || ProcessInfo.processInfo.systemUptime >= deadline {
            if !arrived { Logger.log("Instant space switching: Cmd+Tab timed out; using native activation") }
            app.activate(options: [])
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            self?.activate(app, on: display, target: target, generation: generation, deadline: deadline)
        }
    }

    private func stop() {
        appSwitchGeneration += 1
        Self.activeManager = nil
        iss_set_app_switch_callback(nil)
        iss_set_swipe_override(false)
        iss_destroy()

        if let observer = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            spaceChangeObserver = nil
        }
        if let observer = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            activationObserver = nil
        }
        recentApplications.removeAll()
    }
}
