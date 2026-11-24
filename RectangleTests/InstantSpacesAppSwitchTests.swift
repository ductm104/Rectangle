import Cocoa

// Only app integration dependencies are stubbed; the production manager is compiled unchanged.
enum Defaults {
    static let instantSpaceSwitching = Setting()
    struct Setting {
        let enabled = false
    }
}

enum Logger {
    static func log(_ message: String) {}
}

extension Notification.Name {
    static let instantSpaceSwitching = Notification.Name("instantSpaceSwitching")
    static let configImported = Notification.Name("configImported")

    func onPost(_ callback: @escaping (Notification) -> Void) {}
}

@main
struct InstantSpacesAppSwitchTests {
    static func main() {
        let a: pid_t = 101
        let b: pid_t = 102
        let c: pid_t = 103
        let transitions: [(pid_t, [pid_t], pid_t)] = [
            (a, [a, c], c),
            (c, [c, a], a),
            (a, [a, c], c),
            (a, [a, c, b], c),
            (b, [b, a, c], a),
            (c, [c, b, a], b),
            (b, [b, c, a], c)
        ]
        for (frontmost, recent, expected) in transitions {
            var dockRead = false
            let target = InstantSpacesManager.appSwitchTarget(
                forwardTabs: 1, recentPIDs: recent, frontmostPID: frontmost
            ) {
                dockRead = true
                return a
            }
            precondition(target == expected)
            precondition(!dockRead, "Quick Cmd+Tab must not use a stale Dock selection")
        }

        for (recent, frontmost) in [([a], a), ([b, a], a), ([], a)] {
            let target = InstantSpacesManager.appSwitchTarget(
                forwardTabs: 1, recentPIDs: recent, frontmostPID: frontmost
            ) { c }
            precondition(target == c, "Unknown history must fall back to the native selection")
        }
        var dockRead = false
        precondition(InstantSpacesManager.appSwitchTarget(
            forwardTabs: 2, recentPIDs: [b, a, c], frontmostPID: b
        ) { dockRead = true; return a } == c)
        precondition(!dockRead, "Quick repeated Tab must resolve the third application without Dock")
        precondition(InstantSpacesManager.appSwitchTarget(
            forwardTabs: 3, recentPIDs: [a, b, c], frontmostPID: a
        ) { b } == b, "Selection beyond known history must use Dock, not wrap the partial history")
        precondition(InstantSpacesManager.appSwitchTarget(
            forwardTabs: 0, recentPIDs: [a, b, c], frontmostPID: a
        ) { c } == c, "Shift+Tab and arrow keys must honor the native selection")
        precondition(InstantSpacesManager.appSwitchTarget(
            forwardTabs: 0, recentPIDs: [a, b], frontmostPID: a
        ) { nil } == nil)
        print("Instant Spaces app switch tests passed")
    }
}
