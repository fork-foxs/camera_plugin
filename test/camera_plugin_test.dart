import 'package:flutter_test/flutter_test.dart';
import 'package:camera_plugin/camera_plugin.dart';
import 'package:camera_plugin/camera_plugin_platform_interface.dart';
import 'package:camera_plugin/camera_plugin_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockCameraPluginPlatform
    with MockPlatformInterfaceMixin
    implements CameraPluginPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final CameraPluginPlatform initialPlatform = CameraPluginPlatform.instance;

  test('$MethodChannelCameraPlugin is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelCameraPlugin>());
  });

  test('getPlatformVersion', () async {
    CameraPlugin cameraPlugin = CameraPlugin();
    MockCameraPluginPlatform fakePlatform = MockCameraPluginPlatform();
    CameraPluginPlatform.instance = fakePlatform;

    expect(await cameraPlugin.getPlatformVersion(), '42');
  });
}
