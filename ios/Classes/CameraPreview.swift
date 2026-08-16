import Flutter
import UIKit
import AVFoundation

class CameraPreviewUIView: UIView {
    private var previewLayer: AVCaptureVideoPreviewLayer?

    func setSession(_ session: AVCaptureSession) {
        previewLayer?.removeFromSuperlayer()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        if let connection = layer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        self.layer.addSublayer(layer)
        self.previewLayer = layer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.frame = bounds
        CATransaction.commit()
    }
}

class CameraPreview: NSObject, FlutterPlatformView {
    private let _view: CameraPreviewUIView
    private weak var plugin: CameraPlugin?

    init(
        frame: CGRect,
        viewIdentifier viewId: Int,
        arguments args: Any?,
        plugin: CameraPlugin
    ) {
        self.plugin = plugin
        self._view = CameraPreviewUIView(frame: frame)
        super.init()

        self._view.backgroundColor = .black

        guard let params = args as? [String: Any] else { return }
        let width = params["resolutionWidth"] as? Int ?? 720
        let height = params["resolutionHeight"] as? Int ?? 420
        let quality = params["resolutionQuality"] as? Int ?? 100
        let useMax = params["maxResolution"] as? Bool ?? false
        let cameraType = params["cameraType"] as? String ?? "macroBack"
        let frameFormat = params["frameFormat"] as? String ?? "jpeg"

        plugin.startCamera(
            width: width,
            height: height,
            quality: quality,
            cameraType: cameraType,
            useMaxResolution: useMax,
            frameFormat: frameFormat,
            previewView: _view
        )
    }

    func view() -> UIView {
        return _view
    }
}
