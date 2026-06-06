#!/usr/bin/env swift

import AVFoundation
import Foundation

private let targetName = "Chromium Repro Camera"

private func now() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter.string(from: Date())
}

private func cameraDevices() -> [AVCaptureDevice] {
    var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
    if #available(macOS 14.0, *) {
        deviceTypes.append(.external)
        deviceTypes.append(.continuityCamera)
    } else {
        deviceTypes.append(.externalUnknown)
    }

    let session = AVCaptureDevice.DiscoverySession(
        deviceTypes: deviceTypes,
        mediaType: .video,
        position: .unspecified
    )
    return session.devices
}

private func snapshot(_ reason: String) {
    let devices = cameraDevices()
    let containsTarget = devices.contains { $0.localizedName == targetName }

    print("[\(now())] \(reason) count=\(devices.count) containsTarget=\(containsTarget)")
    for device in devices {
        print("  - name=\(device.localizedName) uid=\(device.uniqueID)")
    }
    fflush(stdout)
}

let center = NotificationCenter.default

let connectedToken = center.addObserver(
    forName: AVCaptureDevice.wasConnectedNotification,
    object: nil,
    queue: nil
) { note in
    let device = note.object as? AVCaptureDevice
    print("[\(now())] WasConnected name=\(device?.localizedName ?? "?") uid=\(device?.uniqueID ?? "?")")
    snapshot("after connected")
}

let disconnectedToken = center.addObserver(
    forName: AVCaptureDevice.wasDisconnectedNotification,
    object: nil,
    queue: nil
) { note in
    let device = note.object as? AVCaptureDevice
    print("[\(now())] WasDisconnected name=\(device?.localizedName ?? "?") uid=\(device?.uniqueID ?? "?")")
    snapshot("after disconnected")
}

print("Watching AVFoundation camera notifications. Press Ctrl-C to exit.")
snapshot("initial")

withExtendedLifetime([connectedToken, disconnectedToken]) {
    RunLoop.main.run()
}
