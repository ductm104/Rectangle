import Darwin
import Foundation
import IOKit.hid
import IOKit.hidsystem

private let product = "Flow84@Lofree"
private let transport = "Bluetooth Low Energy"

private enum ProbeError: LocalizedError {
    case message(String)
    case hid(String, IOReturn)

    var errorDescription: String? {
        switch self {
        case .message(let message): return message
        case .hid(let operation, let code):
            return "\(operation) failed (\(String(format: "0x%08x", UInt32(bitPattern: code))))."
        }
    }
}

private func matchingServices() throws -> [io_service_t] {
    let matching = IOServiceMatching("IOHIDDevice") as NSMutableDictionary
    matching[kIOPropertyMatchKey] = [kIOHIDProductKey: product, kIOHIDTransportKey: transport]
    var iterator: io_iterator_t = 0
    let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
    guard result == kIOReturnSuccess else { throw ProbeError.hid("IORegistry lookup", result) }
    defer { IOObjectRelease(iterator) }

    var services: [io_service_t] = []
    while case let service = IOIteratorNext(iterator), service != 0 {
        services.append(service)
    }
    return services
}

private func withFlow84<T>(_ use: (io_service_t) throws -> T) throws -> T? {
    let services = try matchingServices()
    defer { services.forEach { IOObjectRelease($0) } }
    guard services.count <= 1 else { throw ProbeError.message("More than one matching HID service; disconnect the other Flow84 and retry.") }
    guard let service = services.first else { return nil }
    return try use(service)
}

private func connectedID() throws -> UInt64? {
    try withFlow84 { service in
        var id: UInt64 = 0
        let result = IORegistryEntryGetRegistryEntryID(service, &id)
        guard result == kIOReturnSuccess else { throw ProbeError.hid("Read HID service ID", result) }
        return id
    }
}

private func pulse() throws {
    guard try connectedID() != nil else { throw ProbeError.message("Flow84 is not connected.") }
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
    guard service != 0 else { throw ProbeError.message("No macOS HID system service found.") }
    defer { IOObjectRelease(service) }
    var connection: io_connect_t = 0
    let result = IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connection)
    guard result == kIOReturnSuccess else { throw ProbeError.hid("Open macOS HID system", result) }
    defer { IOServiceClose(connection) }

    let selector = Int32(kIOHIDCapsLockState)
    var capsLock = false
    let read = IOHIDGetModifierLockState(connection, selector, &capsLock)
    guard read == kIOReturnSuccess else { throw ProbeError.hid("Read Caps Lock state", read) }
    let toggle = IOHIDSetModifierLockState(connection, selector, !capsLock)
    guard toggle == kIOReturnSuccess else { throw ProbeError.hid("Toggle Caps Lock state", toggle) }
    Thread.sleep(forTimeInterval: 0.25)
    let restore = IOHIDSetModifierLockState(connection, selector, capsLock)
    guard restore == kIOReturnSuccess else { throw ProbeError.hid("Restore Caps Lock state; check it manually", restore) }
}

private func log(_ message: String) {
    print(message)
    fflush(stdout)
}

private func measure(sendPulse: Bool) throws {
    guard try connectedID() != nil else { throw ProbeError.message("Connect \(product) over Bluetooth first.") }
    log("Press Return on the Flow84 to start; do not touch it again during this trial.")
    guard readLine() != nil else { throw ProbeError.message("No start input received.") }
    guard let id = try connectedID() else { throw ProbeError.message("Flow84 disconnected before the trial started.") }

    let start = ProcessInfo.processInfo.systemUptime
    let pulseAt = 8.0 * 60
    let timeout = (sendPulse ? 22.0 : 14.0) * 60
    var didPulse = false
    log(sendPulse ? "Pulse trial started; LED pulse at 8 minutes." : "Baseline trial started (no HID writes).")
    while true {
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let current = try connectedID()
        if current != id {
            log(String(format: "Flow84 HID service %@ at %.1f seconds.", current == nil ? "disappeared" : "was replaced", elapsed))
            if sendPulse && !didPulse { log("The trial ended before any pulse was sent.") }
            return
        }
        if elapsed >= timeout {
            log(String(format: "No HID service change after %.1f seconds. This trial did not measure a disconnect.", elapsed))
            return
        }
        if sendPulse && !didPulse && elapsed >= pulseAt {
            try pulse()
            didPulse = true
            log(String(format: "macOS accepted the Caps Lock pulse at %.1f seconds; keyboard delivery and timer reset are unconfirmed.", elapsed))
        }
        Thread.sleep(forTimeInterval: 2)
    }
}

do {
    switch Array(CommandLine.arguments.dropFirst()) {
    case ["status"]:
        if let id = try connectedID() { log("\(product) HID service present (\(id)).") }
        else { log("\(product) HID service not present.") }
    case ["pulse-check"]:
        try pulse()
        log("macOS accepted the Caps Lock pulse; check whether the Flow84 LED blinked.")
    case ["baseline"]: try measure(sendPulse: false)
    case ["pulse-trial"]: try measure(sendPulse: true)
    case ["--help"], []:
        log("Usage: flow84-probe status | pulse-check | baseline | pulse-trial")
    default:
        throw ProbeError.message("Usage: flow84-probe status | pulse-check | baseline | pulse-trial")
    }
} catch {
    FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
