import CoreMediaIO
import Foundation

WebcamLogger.shared.mode = .file

guard let providerSource = ExtensionProviderSource(clientQueue: nil) else {
    WebcamLogger.error("chromium-repro-provider-init-failed")
    fputs("Failed to initialize ExtensionProviderSource.\n", stderr)
    exit(EXIT_FAILURE)
}

WebcamLogger.info("chromium-repro-extension-started")

CMIOExtensionProvider.startService(provider: providerSource.provider)
CFRunLoopRun()
