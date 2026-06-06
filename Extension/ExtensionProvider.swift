import CoreMedia
import CoreMediaIO
import CoreVideo
import Foundation
import IOKit.audio
import os.log

private let frameRate: Int32 = 30

@inline(__always)
private func hostTimeNanos() -> UInt64 {
    clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
}

final class ExtensionDeviceSource: NSObject, CMIOExtensionDeviceSource {
    private(set) var device: CMIOExtensionDevice!
    private var streamSource: ExtensionStreamSource!

    private let stateQueue = DispatchQueue(label: "com.example.chromium-feedback.device")
    private let timerQueue = DispatchQueue(label: "com.example.chromium-feedback.frames", qos: .userInteractive)
    private var frameTimer: DispatchSourceTimer?
    private var streamingClientCount = 0

    private let videoDescription: CMFormatDescription
    private let streamFormat: CMIOExtensionStreamFormat
    private let bufferPool: CVPixelBufferPool
    private let bufferAuxAttributes: NSDictionary = [kCVPixelBufferPoolAllocationThresholdKey: 5]

    override init() {
        let width = 1280
        let height = 720

        var description: CMFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCVPixelFormatType_32BGRA,
            width: Int32(width),
            height: Int32(height),
            extensions: nil,
            formatDescriptionOut: &description
        )
        guard formatStatus == noErr, let description else {
            fatalError("Failed to create video format description: \(formatStatus)")
        }
        self.videoDescription = description

        let pixelBufferAttributes: NSDictionary = [
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as NSDictionary,
        ]
        var pool: CVPixelBufferPool?
        let poolStatus = CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, pixelBufferAttributes, &pool)
        guard poolStatus == kCVReturnSuccess, let pool else {
            fatalError("Failed to create pixel buffer pool: \(poolStatus)")
        }
        self.bufferPool = pool

        let duration = CMTime(value: 1, timescale: frameRate)
        self.streamFormat = CMIOExtensionStreamFormat(
            formatDescription: description,
            maxFrameDuration: duration,
            minFrameDuration: duration,
            validFrameDurations: nil
        )

        super.init()

        let deviceID = UUID(uuidString: "E7D6D8BB-9F1D-4689-B291-A8F4F4C15B6E")!
        self.device = CMIOExtensionDevice(
            localizedName: ReproShared.deviceName,
            deviceID: deviceID,
            legacyDeviceID: deviceID.uuidString,
            source: self
        )

        let streamID = UUID(uuidString: "EB6B1888-6D92-4590-82F2-C6D1D6583D64")!
        self.streamSource = ExtensionStreamSource(
            localizedName: "\(ReproShared.deviceName).Video",
            streamID: streamID,
            streamFormat: streamFormat,
            device: device
        )

        do {
            try device.addStream(streamSource.stream)
        } catch {
            fatalError("Failed to add stream: \(error.localizedDescription)")
        }
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.deviceTransportType, .deviceModel]
    }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let deviceProperties = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) {
            deviceProperties.transportType = kIOAudioDeviceTransportTypeVirtual
        }
        if properties.contains(.deviceModel) {
            deviceProperties.model = "ChromiumFeedback"
        }
        return deviceProperties
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {
    }

    func startStreaming() {
        let alreadyStreaming = stateQueue.sync { () -> Bool in
            streamingClientCount += 1
            return streamingClientCount > 1
        }
        if alreadyStreaming {
            return
        }

        WebcamLogger.info("chromium-repro-stream-started")

        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: timerQueue)
        timer.schedule(deadline: .now(), repeating: 1.0 / Double(frameRate), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            self?.sendFrame()
        }
        frameTimer = timer
        timer.resume()
    }

    func stopStreaming() {
        let shouldStop = stateQueue.sync { () -> Bool in
            if streamingClientCount > 1 {
                streamingClientCount -= 1
                return false
            }
            streamingClientCount = 0
            return true
        }

        if shouldStop {
            WebcamLogger.info("chromium-repro-stream-stopped")
            frameTimer?.cancel()
            frameTimer = nil
        }
    }

    private func sendFrame() {
        var pixelBuffer: CVPixelBuffer?
        let bufferStatus = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
            kCFAllocatorDefault,
            bufferPool,
            bufferAuxAttributes,
            &pixelBuffer
        )
        guard bufferStatus == kCVReturnSuccess, let pixelBuffer else {
            WebcamLogger.error("chromium-repro-pixel-buffer-failed", payload: ["status": bufferStatus])
            return
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
            memset(baseAddress, 0, CVPixelBufferGetDataSize(pixelBuffer))
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        let now = hostTimeNanos()
        var timing = CMSampleTimingInfo()
        timing.presentationTimeStamp = CMTime(value: CMTimeValue(now), timescale: CMTimeScale(NSEC_PER_SEC))

        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: videoDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )

        guard sampleStatus == noErr, let sampleBuffer else {
            WebcamLogger.error("chromium-repro-sample-buffer-failed", payload: ["status": sampleStatus])
            return
        }

        streamSource.stream.send(sampleBuffer, discontinuity: [], hostTimeInNanoseconds: now)
    }
}

final class ExtensionStreamSource: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!

    private let device: CMIOExtensionDevice
    private let streamFormat: CMIOExtensionStreamFormat

    init(
        localizedName: String,
        streamID: UUID,
        streamFormat: CMIOExtensionStreamFormat,
        device: CMIOExtensionDevice
    ) {
        self.device = device
        self.streamFormat = streamFormat
        super.init()
        self.stream = CMIOExtensionStream(
            localizedName: localizedName,
            streamID: streamID,
            direction: .source,
            clockType: .hostTime,
            source: self
        )
    }

    var formats: [CMIOExtensionStreamFormat] {
        [streamFormat]
    }

    var activeFormatIndex: Int = 0

    var availableProperties: Set<CMIOExtensionProperty> {
        [.streamActiveFormatIndex, .streamFrameDuration]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let streamProperties = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            streamProperties.activeFormatIndex = activeFormatIndex
        }
        if properties.contains(.streamFrameDuration) {
            streamProperties.frameDuration = CMTime(value: 1, timescale: frameRate)
        }
        return streamProperties
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        if let activeFormatIndex = streamProperties.activeFormatIndex {
            guard activeFormatIndex == 0 else {
                throw NSError(
                    domain: "com.example.chromium-feedback",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid active format index \(activeFormatIndex)"]
                )
            }
            self.activeFormatIndex = activeFormatIndex
        }
    }

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        WebcamLogger.info("chromium-repro-client-authorized", payload: [
            "pid": client.pid,
            "signingID": client.signingID ?? "unknown",
        ])
        return true
    }

    func startStream() throws {
        guard let deviceSource = device.source as? ExtensionDeviceSource else {
            fatalError("Unexpected device source \(String(describing: device.source))")
        }
        deviceSource.startStreaming()
    }

    func stopStream() throws {
        guard let deviceSource = device.source as? ExtensionDeviceSource else {
            fatalError("Unexpected device source \(String(describing: device.source))")
        }
        deviceSource.stopStreaming()
    }
}

final class ExtensionProviderSource: NSObject, CMIOExtensionProviderSource {
    private(set) var provider: CMIOExtensionProvider!
    private let deviceSource = ExtensionDeviceSource()

    init?(clientQueue: DispatchQueue?) {
        super.init()

        provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)
        do {
            try provider.addDevice(deviceSource.device)
        } catch {
            WebcamLogger.error("chromium-repro-add-device-failed", payload: ["error": error.localizedDescription])
            return nil
        }

        WebcamLogger.info("chromium-repro-provider-ready")
    }

    func connect(to client: CMIOExtensionClient) throws {
        WebcamLogger.info("chromium-repro-provider-client-connected", payload: [
            "pid": client.pid,
            "signingID": client.signingID ?? "unknown",
        ])
    }

    func disconnect(from client: CMIOExtensionClient) {
        WebcamLogger.info("chromium-repro-provider-client-disconnected", payload: ["pid": client.pid])
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.providerManufacturer]
    }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let providerProperties = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) {
            providerProperties.manufacturer = "ChromiumFeedback"
        }
        return providerProperties
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {
    }
}
