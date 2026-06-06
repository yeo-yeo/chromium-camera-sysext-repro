import Foundation
import SystemExtensions

final class InstallerDelegate: NSObject, OSSystemExtensionRequestDelegate {
    enum InstallEvent: Sendable {
        case needsApproval
        case completed(OSSystemExtensionRequest.Result)
        case failed(String)
    }

    typealias Handler = @Sendable (InstallEvent) -> Void

    private let onEvent: Handler
    private static var active: Set<InstallerDelegate> = []
    private static let lock = NSLock()

    init(onEvent: @escaping Handler) {
        self.onEvent = onEvent
        super.init()
    }

    static func activate(bundleIdentifier: String, onEvent: @escaping Handler) {
        let delegate = InstallerDelegate(onEvent: onEvent)
        retain(delegate)

        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: bundleIdentifier,
            queue: .main
        )
        request.delegate = delegate
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    static func deactivate(bundleIdentifier: String, onEvent: @escaping Handler) {
        let delegate = InstallerDelegate(onEvent: onEvent)
        retain(delegate)

        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: bundleIdentifier,
            queue: .main
        )
        request.delegate = delegate
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    private static func retain(_ delegate: InstallerDelegate) {
        lock.lock()
        active.insert(delegate)
        lock.unlock()
    }

    private func release() {
        Self.lock.lock()
        Self.active.remove(self)
        Self.lock.unlock()
    }

    func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        return .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        onEvent(.needsApproval)
    }

    func request(
        _ request: OSSystemExtensionRequest,
        didFinishWithResult result: OSSystemExtensionRequest.Result
    ) {
        onEvent(.completed(result))
        release()
    }

    func request(
        _ request: OSSystemExtensionRequest,
        didFailWithError error: any Error
    ) {
        onEvent(.failed(error.localizedDescription))
        release()
    }
}
