import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'camera_plugin_platform_interface.dart';

/// An implementation of [CameraPluginPlatform] that uses method channels.
class MethodChannelCameraPlugin extends CameraPluginPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('camera_plugin');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
