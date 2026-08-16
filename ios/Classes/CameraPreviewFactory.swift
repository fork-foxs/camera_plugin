import Flutter
import UIKit

class CameraPreviewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger
    private let plugin: CameraPlugin

    init(messenger: FlutterBinaryMessenger, plugin: CameraPlugin) {
        self.messenger = messenger
        self.plugin = plugin
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return CameraPreview(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            plugin: plugin
        )
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}
