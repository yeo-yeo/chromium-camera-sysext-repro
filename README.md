# Chromium Feedback Reproducer: macOS Camera Extension Reinstall Leaves Chrome Stale

This is a minimal macOS CoreMediaIO Camera Extension repro for Chromium bug reports.

It shows that a Chromium-based app can keep a stale camera list after a Camera System Extension is deactivated and reactivated while the Chromium app stays open. A fresh AVFoundation observer sees the camera, but Chrome's `navigator.mediaDevices.enumerateDevices()` does not recover until Chrome is restarted.

## Quick Start

From this directory:

```bash
DEVELOPMENT_TEAM=ABC1234567 ./scripts/setup.sh
./scripts/build.sh
open /Applications/ChromiumFeedback.app
```

Replace `ABC1234567` with your Apple Developer Team ID. Approve the extension in System Settings when prompted.

macOS may also show a confirmation mentioning access to files elsewhere. This is expected: the host app and Camera Extension both declare a shared App Group (`group.<TEAM_ID>.com.example.ChromiumFeedback`). The CMIO category validator requires the extension Mach service name to be prefixed by an App Group, and this repro also uses that shared container for `logs.jsonl`.

## Files

```text
ChromiumFeedback/       SwiftUI host app with Install/Uninstall buttons
Extension/              Minimal CMIO Camera Extension
Shared/                 Shared bundle IDs and logger
Observer/               Fresh AVFoundation observer process
Web/                    Chrome enumerateDevices() test page
scripts/                xcodegen/build helpers
```

## Reproduce in Chrome

1. Build and open `/Applications/ChromiumFeedback.app`.
2. Click **Install / Replace Extension** and approve the Driver Extension in System Settings.
3. Serve the repro page from localhost:

   ```bash
   python3 -m http.server 8765
   ```

4. In Chrome, open `http://127.0.0.1:8765/Web/enumerate-devices.html`.
5. Click **Request camera permission**, select `Chromium Repro Camera`, and confirm `getUserMedia()` succeeds.
6. Click **Enumerate devices** and confirm `Chromium Repro Camera` appears.
7. Leave Chrome open.
8. In the host app, click **Uninstall Extension** and wait for completion.
9. Click **Install / Replace Extension** again and wait for completion.
10. In a terminal, run:

   ```bash
   swift Observer/probe-cameras.swift
   ```

   A fresh AVFoundation process should see `Chromium Repro Camera`.

11. Return to the already-open Chrome page and click **Enumerate devices** again.

Expected: Chrome sees `Chromium Repro Camera` again.

Actual: Chrome can keep returning a stale camera list that does not include `Chromium Repro Camera` until Chrome is quit and relaunched.

Do not open the HTML file directly as `file://...`. Chrome can show the camera picker from a file URL but still return blank `label`, `deviceId`, and `groupId` values from `enumerateDevices()`, which creates a misleading permission failure unrelated to this bug.

## Related Prior Art

- Chromium issue 40208664 fixed a different stale-list bug where `DeviceMonitorMac` and the video capture service enumerated inconsistent device lists: <https://issues.chromium.org/issues/40208664>
- This repro is different because a fresh AVFoundation process sees the reinstalled Camera Extension, while an already-running Chromium process can remain stale until restart.
- Apple-side reports describe a similar Camera Extension lifecycle gap for already-running clients: <https://developer.apple.com/forums/thread/734259>

## Cleanup

Click **Uninstall Extension** in the host app, or run:

```bash
systemextensionsctl uninstall <YOUR_TEAM_ID> com.example.ChromiumFeedback.Extension
```
