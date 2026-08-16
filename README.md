# camera_plugin

A Flutter camera plugin supporting high-performance camera preview and image frame streaming on Android and iOS.

## iOS Setup

### 1. Permissions (`Info.plist`)
Add the following keys to `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>This app requires camera access to preview and capture photos.</string>
<key>NSMicrophoneUsageDescription</key>
<string>This app requires microphone access for video recording.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>This app requires photo library access to save captured photos.</string>
```

### 2. CocoaPods Configuration (`Podfile`)
Add the permission preprocessor macros in your `ios/Podfile` inside the `post_install` block:

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',
        ## dart: PermissionGroup.camera
        'PERMISSION_CAMERA=1',
        ## dart: PermissionGroup.microphone
        'PERMISSION_MICROPHONE=1',
        ## dart: PermissionGroup.photos
        'PERMISSION_PHOTOS=1',
      ]
    end
  end
end
```

## Android Setup

Ensure camera permissions are added to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

## Usage

```dart
import 'package:camera_plugin/camera_plugin.dart';

final controller = CameraController();

// Request permission and initialize
await controller.initialize();

// Listen to stream frames
controller.frames.listen((Uint8List imageBytes) {
  // Process JPEG frames
});

// Display preview
CameraPreview(
  controller: controller,
  cameraType: CameraType.front, // or CameraType.macroBack
)
```
