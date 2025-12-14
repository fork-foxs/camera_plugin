import 'dart:typed_data';

import 'package:camera_plugin/camera_plugin.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  // --- Camera State ---
  bool _hasCameraPermission = false;
  bool _isFlashOn = false;
  String _selectedResolution = '1920x1080';
  String _selectedQuality = 'High';
  bool _useMaxQuality = false;
  CameraType _selectedCameraType = CameraType.front;

  // --- Image Preview State ---
  Uint8List? _currentImageBytes;
  bool _isShowingPreview = false;
  bool _isProcessingImages = false;

  // --- Camera Options ---
  final List<String> _resolutions = [
    '640x480',
    '1280x720',
    '1920x1080',
    '3840x2160',
  ];
  final List<String> _qualities = [
    'Low',
    'Medium',
    'High',
    'Excellent',
    'Maximum',
  ];
  final List<int> _qualityValues = [25, 50, 75, 100, 100];

  final controller = CameraController();

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await controller.initialize();
      controller.frames.listen((imageBytes) async {
        // بدء معالجة الصور إذا لم تكن قيد المعالجة

        _processImageQueue(imageBytes);
      });
    });
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    setState(() {
      _hasCameraPermission = status.isGranted;
    });
    if (!status.isGranted) {
      _showPermissionDeniedDialog();
    }
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Permission Required'),
          content: Text('The app needs camera permission to work properly.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              child: Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

  void _processImageQueue(Uint8List imageBytes) async {
    if (_isProcessingImages) return;

    _isProcessingImages = true;

    setState(() {
      print('imageQueue: ${imageBytes.length / 1024 / 1024} MB');
      _currentImageBytes = imageBytes;
      _isShowingPreview = true;
    });

    // انتظار ثانيتين قبل عرض الصورة التالية
    await Future.delayed(Duration(seconds: 2));

    setState(() {
      _isShowingPreview = false;

      _isProcessingImages = false;
    });
  }

  void _toggleFlash() {
    setState(() {
      _isFlashOn = !_isFlashOn;
    });
    if (_isFlashOn) {
      controller.turnOnFlash();
    } else {
      controller.turnOffFlash();
    }
  }

  void _switchCamera() {
    setState(() {
      _selectedCameraType =
          _selectedCameraType == CameraType.macroBack
              ? CameraType.front
              : CameraType.macroBack;
    });
  }

  void _showSettingsBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return CameraSettingsSheet(
          resolutions: _resolutions,
          qualities: _qualities,
          qualityValues: _qualityValues,
          selectedResolution: _selectedResolution,
          selectedQuality: _selectedQuality,
          selectedCameraType: _selectedCameraType,
          onResolutionChanged:
              (res) => setState(() => _selectedResolution = res),
          onQualityChanged:
              (q) => setState(() {
                _selectedQuality = q;
                _useMaxQuality = q == 'Maximum';
              }),
          onCameraTypeChanged:
              (type) => setState(() => _selectedCameraType = type),
          onApply: () {
            controller.changeResolution(
              width: int.parse(_selectedResolution.split('x')[0]),
              height: int.parse(_selectedResolution.split('x')[1]),
              quality: _qualityValues[_qualities.indexOf(_selectedQuality)],
              useMax: _useMaxQuality,
            );
            Navigator.pop(context);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: Icon(Icons.delete_outline),
            tooltip: 'Dispose Camera',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder:
                    (context) => AlertDialog(
                      title: Text('Dispose Camera'),
                      content: Text(
                        'Are you sure you want to dispose the camera controller?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text('Yes'),
                        ),
                      ],
                    ),
              );
              if (confirm == true) {
                await controller.disposeCamera();
                setState(() {});
              }
            },
          ),
        ],
      ),
      body:
          _hasCameraPermission
              ? Stack(
                children: [
                  // عرض معاينة الكاميرا
                  CameraPreview(
                    controller: controller,
                    cameraType: _selectedCameraType,
                  ),

                  // عرض الصورة في الزاوية العلوية اليسرى
                  if (_currentImageBytes != null)
                    Positioned(
                      top: 20,
                      left: 20,
                      child: Container(
                        width: 120,
                        height: 90,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(
                            _currentImageBytes!,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),

                  // مؤشر المعاينة
                  if (_isShowingPreview)
                    Positioned(
                      top: 20,
                      right: 20,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Text(
                          'معاينة',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                  Positioned(
                    bottom: 20,
                    left: 20,
                    child: Column(
                      children: [
                        FloatingActionButton(
                          heroTag: "flash",
                          onPressed: _toggleFlash,
                          backgroundColor:
                              _isFlashOn ? Colors.orange : Colors.grey,
                          child: Icon(
                            _isFlashOn ? Icons.flash_on : Icons.flash_off,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 10),
                        FloatingActionButton(
                          heroTag: "camera_switch",
                          onPressed: _switchCamera,
                          backgroundColor: Colors.purple,
                          child: Icon(
                            _selectedCameraType == CameraType.front
                                ? Icons.camera_front
                                : Icons.camera_rear,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 10),
                        FloatingActionButton(
                          heroTag: "settings",
                          onPressed: _showSettingsBottomSheet,
                          backgroundColor: Colors.blue,
                          child: Icon(Icons.settings, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 20,
                    right: 20,
                    child: CameraStatusBadge(
                      resolution: _selectedResolution,
                      quality: _selectedQuality,
                      qualityValues: _qualityValues,
                      qualities: _qualities,
                      cameraType: _selectedCameraType,
                    ),
                  ),
                ],
              )
              : Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.camera_alt, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      'Camera Permission Required',
                      style: TextStyle(fontSize: 18),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'The app needs camera permission to work',
                      style: TextStyle(color: Colors.grey),
                    ),
                    SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _requestCameraPermission,
                      child: Text('Request Permission'),
                    ),
                  ],
                ),
              ),
    );
  }
}

class CameraSettingsSheet extends StatelessWidget {
  final List<String> resolutions;
  final List<String> qualities;
  final List<int> qualityValues;
  final String selectedResolution;
  final String selectedQuality;
  final CameraType selectedCameraType;
  final ValueChanged<String> onResolutionChanged;
  final ValueChanged<String> onQualityChanged;
  final ValueChanged<CameraType> onCameraTypeChanged;
  final VoidCallback onApply;

  const CameraSettingsSheet({
    super.key,
    required this.resolutions,
    required this.qualities,
    required this.qualityValues,
    required this.selectedResolution,
    required this.selectedQuality,
    required this.selectedCameraType,
    required this.onResolutionChanged,
    required this.onQualityChanged,
    required this.onCameraTypeChanged,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Camera Settings',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close),
              ),
            ],
          ),
          SizedBox(height: 20),
          Text(
            'Resolution',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 10),
          SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: resolutions.length,
              itemBuilder: (context, index) {
                final resolution = resolutions[index];
                final isSelected = resolution == selectedResolution;
                return Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: ChoiceChip(
                    label: Text(resolution),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) onResolutionChanged(resolution);
                    },
                  ),
                );
              },
            ),
          ),
          SizedBox(height: 20),
          Text(
            'Quality',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 10),
          SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: qualities.length,
              itemBuilder: (context, index) {
                final quality = qualities[index];
                final isSelected = quality == selectedQuality;
                return Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: ChoiceChip(
                    label: Text(quality),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) onQualityChanged(quality);
                    },
                  ),
                );
              },
            ),
          ),
          SizedBox(height: 20),
          Text(
            'Camera Type',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.camera_rear, size: 18),
                      SizedBox(width: 5),
                      Text('Macro Back'),
                    ],
                  ),
                  selected: selectedCameraType == CameraType.macroBack,
                  onSelected: (selected) {
                    if (selected) onCameraTypeChanged(CameraType.macroBack);
                  },
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: ChoiceChip(
                  label: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.camera_front, size: 18),
                      SizedBox(width: 5),
                      Text('Front'),
                    ],
                  ),
                  selected: selectedCameraType == CameraType.front,
                  onSelected: (selected) {
                    if (selected) onCameraTypeChanged(CameraType.front);
                  },
                ),
              ),
            ],
          ),
          SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onApply,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text('Apply Settings', style: TextStyle(fontSize: 16)),
            ),
          ),
          SizedBox(height: 20),
        ],
      ),
    );
  }
}

class CameraStatusBadge extends StatelessWidget {
  final String resolution;
  final String quality;
  final List<int> qualityValues;
  final List<String> qualities;
  final CameraType cameraType;
  const CameraStatusBadge({
    super.key,
    required this.resolution,
    required this.quality,
    required this.qualityValues,
    required this.qualities,
    required this.cameraType,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resolution: $resolution',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
          SizedBox(height: 5),
          Text(
            'Quality: ${quality == 'Maximum' ? 'Maximum' : '${qualityValues[qualities.indexOf(quality)]}%'}',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
          SizedBox(height: 5),
          Text(
            'Camera: ${cameraType == CameraType.front ? 'Front' : 'Macro Back'}',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
