import Flutter
import UIKit

class CameraPreviewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger
    private let plugin: CustomCameraPlugin

    init(messenger: FlutterBinaryMessenger, plugin: CustomCameraPlugin) {
        self.messenger = messenger
        self.plugin = plugin
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return CameraPreview(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            plugin: plugin
        )
    }

    public func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}
