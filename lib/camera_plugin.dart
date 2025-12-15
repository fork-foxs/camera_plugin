import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraController {
  static const _method = MethodChannel('camera_control');
  static const _events = EventChannel('camera_stream');
  static bool _isInitialized = false;
  Stream<Uint8List>? _frameStream;

  /// Initialize camera controller and check permissions
  /// Throws [CameraPermissionException] if camera permission is not granted
  Future<void> initialize() async {
    final status = await Permission.camera.status;

    if (status.isDenied) {
      throw CameraPermissionException(
        'Camera permission is required to use this feature',
      );
    }

    if (status.isPermanentlyDenied) {
      throw CameraPermissionException(
        'Camera permission is permanently denied. Please enable it in app settings.',
      );
    }
    _isInitialized = true;
  }

  /// Starts listening to the native stream.
  Stream<Uint8List> get frames {
    if (!_isInitialized) {
      throw CameraPermissionException(
        'Camera must be initialized before accessing frames. Call initialize() first.',
      );
    }
    _frameStream ??= _events.receiveBroadcastStream().map(
      (event) => event as Uint8List,
    );
    return _frameStream!;
  }

  Future<void> turnOnFlash() => _method.invokeMethod('turnOnFlash');
  Future<void> turnOffFlash() => _method.invokeMethod('turnOffFlash');
  Future<void> disposeCamera() => _method.invokeMethod('disposeCamera');
  Future<void> changeResolution({
    required int width,
    required int height,
    required int quality,
    required bool useMax,
  }) => _method.invokeMethod('changeResolution', {
    'resolutionWidth': width,
    'resolutionHeight': height,
    'resolutionQuality': quality,
    'maxResolution': useMax,
  });
}

/// Exception thrown when camera permission is not granted
class CameraPermissionException implements Exception {
  final String message;

  CameraPermissionException(this.message);

  @override
  String toString() => 'CameraPermissionException: $message';
}

/// Enum to specify which camera to use
enum CameraType { macroBack, front }

/// Enum to specify frame format
enum FrameFormat { jpeg, yuv420888 }

class CameraPreview extends StatefulWidget {
  final CameraController controller;
  final int initialWidth, initialHeight, initialQuality;
  final bool useMaxResolution;
  final CameraType cameraType;
  final FrameFormat frameFormat;

  const CameraPreview({
    super.key,
    required this.controller,
    this.initialWidth = 720,
    this.initialHeight = 420,
    this.initialQuality = 100,
    this.useMaxResolution = false,
    this.cameraType = CameraType.macroBack,
    this.frameFormat = FrameFormat.jpeg,
  });

  @override
  State<CameraPreview> createState() => _CameraPreviewState();
}

class _CameraPreviewState extends State<CameraPreview> {
  @override
  Widget build(BuildContext context) {
    if (!CameraController._isInitialized) {
      return const Center(
        child: Text(
          'Camera must be initialized before accessing frames. Call init() first.',
        ),
      );
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      return PlatformViewLink(
        viewType: 'camera_preview',
        surfaceFactory: (
          BuildContext context,
          PlatformViewController controller,
        ) {
          return AndroidViewSurface(
            controller: controller as AndroidViewController,
            gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
          );
        },
        onCreatePlatformView: (PlatformViewCreationParams params) {
          final AndroidViewController controller =
              PlatformViewsService.initExpensiveAndroidView(
                id: params.id,
                viewType: 'camera_preview',
                creationParams: {
                  'resolutionWidth': widget.initialWidth,
                  'resolutionHeight': widget.initialHeight,
                  'resolutionQuality': widget.initialQuality,
                  'maxResolution': widget.useMaxResolution,
                  'cameraType': widget.cameraType.name,
                  'frameFormat': widget.frameFormat.name,
                },
                layoutDirection: TextDirection.ltr,
                creationParamsCodec: const StandardMessageCodec(),
                onFocus: () => params.onFocusChanged(true),
              );
          controller.addOnPlatformViewCreatedListener(
            params.onPlatformViewCreated,
          );

          return controller;
        },
      );
    }
    // iOS stub for later
    return const Center(child: Text('iOS not yet implemented'));
  }

  @override
  void dispose() {
    widget.controller.disposeCamera();
    super.dispose();
  }
}
