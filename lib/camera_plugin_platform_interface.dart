import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'camera_plugin_method_channel.dart';

abstract class CameraPluginPlatform extends PlatformInterface {
  /// Constructs a CameraPluginPlatform.
  CameraPluginPlatform() : super(token: _token);

  static final Object _token = Object();

  static CameraPluginPlatform _instance = MethodChannelCameraPlugin();

  /// The default instance of [CameraPluginPlatform] to use.
  ///
  /// Defaults to [MethodChannelCameraPlugin].
  static CameraPluginPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [CameraPluginPlatform] when
  /// they register themselves.
  static set instance(CameraPluginPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
