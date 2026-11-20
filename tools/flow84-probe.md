# Flow84 Bluetooth idle probe

This standalone macOS probe is not part of the Rectangle app and does not install anything at login. It tests whether a Caps Lock LED update delays the Flow84's Bluetooth disconnect. It observes the matching Bluetooth LE HID service, not the keyboard's internal sleep state.

## Run the experiment

From the repository root:

```sh
probe_dir=$(mktemp -d)
xcrun swiftc -warnings-as-errors tools/flow84-probe.swift -o "$probe_dir/flow84-probe"
"$probe_dir/flow84-probe" status
"$probe_dir/flow84-probe" pulse-check
caffeinate -i "$probe_dir/flow84-probe" baseline | tee "$probe_dir/baseline.log"
caffeinate -i "$probe_dir/flow84-probe" pulse-trial | tee "$probe_dir/pulse-trial.log"
```

- Connect one `Flow84@Lofree` over Bluetooth. For `pulse-check`, keep it awake and look for a brief Caps Lock LED blink. The probe changes the system Caps Lock state for 250 ms and restores it; avoid typing during this check. No keypress is injected. macOS may update other connected keyboards' LEDs too. An accepted system call does not establish that the Flow84 received the update.
- Run each trial separately. At its prompt, press Return on the Flow84, then do not touch the Flow84 or toggle Caps Lock until the trial ends. Wake and reconnect it between trials. Leave the Mac awake and do not close its lid. Logs remain in `$probe_dir`.
- Expect the baseline HID service to disappear around 600 seconds. The pulse trial sends its update around 480 seconds; disappearance around 1,080 seconds (baseline plus ~480 seconds) would support a timer reset. A disconnect at roughly the baseline time after a visible blink means this update did not reset the timer. If the LED did not blink, the pulse failed, the service was replaced, or the baseline never disappeared, do not interpret the result as a timer reset. The baseline and pulse trials stop after 14 and 22 minutes, respectively.

On the development Mac, the Flow84 HID service was detected. Direct device access returned `kIOReturnExclusiveAccess`; writing without opening returned `kIOReturnNotOpen`. macOS accepted the system-level Caps Lock toggle and restore. Physical LED delivery and the two timed trial results are not yet verified.

## Rectangle integration plan (conditional)

1. Repeat the paired trial before changing Rectangle. If there is no reproducible delay, stop. An LED blink or successful API return alone is insufficient.
2. If it works, find a way to update only the Flow84 without changing system Caps Lock. Do not ship the probe's global toggle as a background keepalive. Stop if there is no acceptable way to send the update on a normal paired Mac.
3. Add an isolated Swift controller, independent of window and display management. Detect the supported Bluetooth keyboard and track activity from that device only, without retaining key codes. Verify any macOS Input Monitoring requirement separately. Do not seize the keyboard or inject keys.
4. Base the schedule on the most recent real input using a monotonic clock: for a confirmed ten-minute device timeout, send at idle minutes 8, 16, and 20, then stop so the keyboard can disconnect at about minute 30. Restart the schedule on real input and cancel it on disconnect, system sleep, disable, or unrecoverable HID error. Never replay missed pulses or try to write to an already disconnected device.
5. Add an opt-in setting in `Rectangle/SettingsWindow/AppSettingsView.swift`, persisted in `Rectangle/Defaults.swift`, and manage the controller from `Rectangle/AppDelegate.swift`. Reuse Rectangle's existing **Launch on login** setting (`Rectangle/LaunchOnLogin.swift`); no separate login agent. On another Mac, install the same Rectangle build and enable the option after pairing.
6. Verify timing and cancellation with a test clock, then measure the actual 30-minute behavior and reconnect on a paired Mac; confirm the disabled setting makes no HID writes and normal typing is unaffected.
