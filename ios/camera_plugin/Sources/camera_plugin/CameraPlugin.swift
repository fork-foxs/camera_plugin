import Flutter
import UIKit
import AVFoundation
import CoreImage
import ImageIO

public class CustomCameraPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?

    var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var currentCamera: AVCaptureDevice?
    private var delegateHandler: VideoOutputDelegate?
    private let captureQueue = DispatchQueue(label: "camera.capture.queue")

    // MARK: - FlutterPlugin Registration

    public static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(
            name: "camera_control",
            binaryMessenger: registrar.messenger()
        )
        let eventChannel = FlutterEventChannel(
            name: "camera_stream",
            binaryMessenger: registrar.messenger()
        )
        let instance = CustomCameraPlugin()
        instance.methodChannel = methodChannel
        instance.eventChannel = eventChannel
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        eventChannel.setStreamHandler(instance)

        let factory = CameraPreviewFactory(messenger: registrar.messenger(), plugin: instance)
        registrar.register(factory, withId: "camera_preview")

        instance.setupLifecycleObservers()
    }

    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func appDidEnterBackground() {
        let session = self.captureSession
        captureQueue.async {
            session?.stopRunning()
        }
    }

    @objc private func appWillEnterForeground() {
        let session = self.captureSession
        captureQueue.async {
            guard let session = session else { return }
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    // MARK: - FlutterPlugin Method Calls

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
        case "checkPermission":
            checkCameraPermission(result: result)
        case "requestPermission":
            requestCameraPermission(result: result)
        case "turnOnFlash":
            toggleTorch(on: true)
            result(nil)
        case "turnOffFlash":
            toggleTorch(on: false)
            result(nil)
        case "disposeCamera":
            disposeCamera()
            result(nil)
        case "changeResolution":
            guard let args = call.arguments as? [String: Any] else { result(nil); return }
            let width = args["resolutionWidth"] as? Int ?? 720
            let height = args["resolutionHeight"] as? Int ?? 420
            let quality = args["resolutionQuality"] as? Int ?? 80
            let useMax = args["maxResolution"] as? Bool ?? false
            changeResolution(width: width, height: height, quality: quality, useMax: useMax)
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - FlutterStreamHandler

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }

    // MARK: - Permission Handling

    private func checkCameraPermission(result: @escaping FlutterResult) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            result("granted")
        case .notDetermined:
            result("undetermined")
        case .denied:
            result("denied")
        case .restricted:
            result("restricted")
        @unknown default:
            result("undetermined")
        }
    }

    private func requestCameraPermission(result: @escaping FlutterResult) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized {
            result("granted")
            return
        }
        if status == .denied || status == .restricted {
            result("denied")
            return
        }
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                result(granted ? "granted" : "denied")
            }
        }
    }

    // MARK: - Camera Session Management

    func startCamera(
        width: Int,
        height: Int,
        quality: Int,
        cameraType: String,
        useMaxResolution: Bool,
        frameFormat: String,
        previewView: UIView
    ) {
        disposeCamera()

        let session = AVCaptureSession()
        session.beginConfiguration()

        let position: AVCaptureDevice.Position = (cameraType == "front") ? .front : .back
        var selectedDevice: AVCaptureDevice?

        if #available(iOS 10.0, *) {
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTrueDepthCamera],
                mediaType: .video,
                position: position
            )
            selectedDevice = discovery.devices.first
        }
        if selectedDevice == nil {
            selectedDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
        }

        guard let device = selectedDevice else {
            print("CustomCameraPlugin: Failed to get camera device for position \(position.rawValue)")
            session.commitConfiguration()
            return
        }
        self.currentCamera = device

        guard let input = try? AVCaptureDeviceInput(device: device) else {
            print("CustomCameraPlugin: Failed to create device input")
            session.commitConfiguration()
            return
        }
        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        if frameFormat == "nv21" {
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        } else {
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        }

        let isFront = (position == .front)
        let handler = VideoOutputDelegate(plugin: self, frameFormat: frameFormat, quality: quality, isFront: isFront)
        output.setSampleBufferDelegate(handler, queue: captureQueue)
        if session.canAddOutput(output) {
            session.addOutput(output)
            if let connection = output.connection(with: .video), connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
                if isFront && connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = true
                }
            }
        }
        self.videoOutput = output
        self.delegateHandler = handler

        applyResolution(width: width, height: height, useMax: useMaxResolution, session: session)

        session.commitConfiguration()
        self.captureSession = session

        captureQueue.async {
            session.startRunning()
        }

        DispatchQueue.main.async { [weak self, weak previewView] in
            guard let self = self, let previewView = previewView else { return }
            self.attachPreviewLayer(session: session, to: previewView)
        }
    }

    private func attachPreviewLayer(session: AVCaptureSession, to view: UIView) {
        if let previewContainer = view as? CameraPreviewUIView {
            previewContainer.setSession(session)
        } else {
            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = view.bounds
            previewLayer.name = "cameraPreviewLayer"
            view.layer.addSublayer(previewLayer)
        }
    }

    // MARK: - Flash / Torch

    private func toggleTorch(on: Bool) {
        guard let device = currentCamera, device.hasTorch, device.isTorchAvailable else { return }
        do {
            try device.lockForConfiguration()
            if on {
                if device.isTorchModeSupported(.on) {
                    try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                }
            } else {
                if device.isTorchModeSupported(.off) {
                    device.torchMode = .off
                }
            }
            device.unlockForConfiguration()
        } catch {
            print("CustomCameraPlugin: Failed to toggle torch: \(error)")
        }
    }

    // MARK: - Resolution

    private func changeResolution(width: Int, height: Int, quality: Int, useMax: Bool) {
        guard let session = captureSession else { return }
        session.beginConfiguration()
        applyResolution(width: width, height: height, useMax: useMax, session: session)
        session.commitConfiguration()
        delegateHandler?.updateQuality(quality)
    }

    private func applyResolution(width: Int, height: Int, useMax: Bool, session: AVCaptureSession) {
        if useMax && session.canSetSessionPreset(.hd4K3840x2160) {
            session.sessionPreset = .hd4K3840x2160
            return
        }
        let target = width * height
        if target >= 3840 * 2160 && session.canSetSessionPreset(.hd4K3840x2160) {
            session.sessionPreset = .hd4K3840x2160
        } else if target >= 1920 * 1080 && session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        } else if target >= 1280 * 720 && session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        } else if session.canSetSessionPreset(.vga640x480) {
            session.sessionPreset = .vga640x480
        } else if session.canSetSessionPreset(.medium) {
            session.sessionPreset = .medium
        }
    }

    // MARK: - Frame Sending

    func sendFrame(_ frameData: Data) {
        DispatchQueue.main.async { [weak self] in
            guard let sink = self?.eventSink else { return }
            sink(FlutterStandardTypedData(bytes: frameData))
        }
    }

    // MARK: - Dispose

    func disposeCamera() {
        let session = self.captureSession
        self.captureSession = nil
        captureQueue.async {
            session?.stopRunning()
        }

        videoOutput?.setSampleBufferDelegate(nil, queue: nil)
        videoOutput = nil

        delegateHandler = nil
        currentCamera = nil

        // Do NOT null out eventSink here.
        // The Dart EventChannel stream subscription remains active across
        // camera rebuilds (e.g. switching front/back). Only onCancel sets
        // eventSink = nil when the Dart side actually unsubscribes.
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Video Output Delegate (Frame Capture)

class VideoOutputDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private weak var plugin: CustomCameraPlugin?
    private let frameFormat: String
    private let isFront: Bool
    private let lock = NSLock()
    private var _quality: Int
    private let ciContext = CIContext(options: [CIContextOption.useSoftwareRenderer: false])

    private var frameCount = 0

    init(plugin: CustomCameraPlugin, frameFormat: String, quality: Int, isFront: Bool) {
        self.plugin = plugin
        self.frameFormat = frameFormat
        self._quality = quality
        self.isFront = isFront
        super.init()
        print("[KYC_DEBUG] [CameraPlugin iOS] VideoOutputDelegate initialized with frameFormat=\(frameFormat), isFront=\(isFront)")
    }

    var quality: Int {
        get { lock.lock(); defer { lock.unlock() }; return _quality }
        set { lock.lock(); defer { lock.unlock() }; _quality = newValue }
    }

    func updateQuality(_ newQuality: Int) {
        quality = newQuality
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let plugin = plugin else {
            print("[KYC_DEBUG] [CameraPlugin iOS] captureOutput dropped: plugin is NIL")
            return
        }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("[KYC_DEBUG] [CameraPlugin iOS] captureOutput dropped: CMSampleBufferGetImageBuffer returned NIL")
            return
        }

        frameCount += 1
        let shouldLog = frameCount <= 5 || frameCount % 30 == 0
        if shouldLog {
            print("[KYC_DEBUG] [CameraPlugin iOS] captureOutput #\(frameCount): format=\(frameFormat)")
        }

        if let jpegData = pixelBufferToJPEG(imageBuffer, quality: quality, isFront: isFront) {
            if shouldLog {
                print("[KYC_DEBUG] [CameraPlugin iOS] Successfully generated JPEG frame #\(frameCount) (\(jpegData.count) bytes)")
            }
            plugin.sendFrame(jpegData)
        } else {
            print("[KYC_DEBUG] [CameraPlugin iOS] ERROR: pixelBufferToJPEG returned NIL for frame #\(frameCount)")
        }
    }

    private func pixelBufferToJPEG(_ pixelBuffer: CVPixelBuffer, quality: Int, isFront: Bool) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        let uiImage = UIImage(cgImage: cgImage)
        let compression = quality > 0 ? CGFloat(quality) / 100.0 : 0.8
        return uiImage.jpegData(compressionQuality: compression)
    }
}
