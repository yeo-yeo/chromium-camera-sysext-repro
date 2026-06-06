import SwiftUI

struct ContentView: View {
    @State private var status = "Idle"
    @State private var log: [String] = []
    @State private var working = false

    private let extensionBundleIdentifier = "com.example.ChromiumFeedback.Extension"

    private var extensionVersion: String {
        let extensionURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/SystemExtensions")
            .appendingPathComponent("\(extensionBundleIdentifier).systemextension")
        guard let bundle = Bundle(url: extensionURL) else { return "unknown" }
        let short = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (build \(build))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Chromium Camera Extension Reproducer")
                .font(.title2)
                .bold()

            VStack(alignment: .leading, spacing: 4) {
                Text("Extension bundle ID: \(extensionBundleIdentifier)")
                Text("Embedded version: \(extensionVersion)")
                Text("Device name: \(ReproShared.deviceName)")
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(action: install) {
                    Label("Install / Replace Extension", systemImage: "tray.and.arrow.down")
                }
                .disabled(working)

                Button(role: .destructive, action: uninstall) {
                    Label("Uninstall Extension", systemImage: "tray.and.arrow.up")
                }
                .disabled(working)
            }

            Text("Status: \(status)")
                .font(.callout)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(log.indices, id: \.self) { index in
                        Text(log[index])
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: .infinity)
            .background(Color.black.opacity(0.05))

            Text(
                "Chromium repro: install the extension, open Web/enumerate-devices.html in Chrome, "
                    + "confirm the camera appears, then uninstall and reinstall here while Chrome stays open."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func install() {
        guard !working else { return }
        working = true
        appendLog("Submitting activationRequest")
        status = "Installing/replacing"
        InstallerDelegate.activate(bundleIdentifier: extensionBundleIdentifier) { event in
            DispatchQueue.main.async { handle(event, label: "install") }
        }
    }

    private func uninstall() {
        guard !working else { return }
        working = true
        appendLog("Submitting deactivationRequest")
        status = "Uninstalling"
        InstallerDelegate.deactivate(bundleIdentifier: extensionBundleIdentifier) { event in
            DispatchQueue.main.async { handle(event, label: "uninstall") }
        }
    }

    private func handle(_ event: InstallerDelegate.InstallEvent, label: String) {
        switch event {
        case .needsApproval:
            status = "Waiting for approval in System Settings"
            appendLog("[\(label)] needs user approval")
        case .completed(let result):
            working = false
            switch result {
            case .completed:
                status = "Completed"
                appendLog("[\(label)] didFinishWithResult: .completed")
            case .willCompleteAfterReboot:
                status = "Will complete after reboot"
                appendLog("[\(label)] didFinishWithResult: .willCompleteAfterReboot")
            @unknown default:
                status = "Unknown completion code"
                appendLog("[\(label)] didFinishWithResult: \(result.rawValue)")
            }
        case .failed(let message):
            working = false
            status = "Failed"
            appendLog("[\(label)] didFailWithError: \(message)")
        }
    }

    private func appendLog(_ line: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        log.append("[\(formatter.string(from: Date()))] \(line)")
    }
}
