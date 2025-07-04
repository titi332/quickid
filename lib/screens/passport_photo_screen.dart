import 'dart:io';
import 'dart:typed_data';
import 'package:background_remover/background_remover.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class PassportPhotoScreen extends StatefulWidget {
  const PassportPhotoScreen({super.key});

  @override
  _PassportPhotoScreenState createState() => _PassportPhotoScreenState();
}

class _PassportPhotoScreenState extends State<PassportPhotoScreen> {
  String selectedBackground = "";
  String selectedDress = "Original";
  int selectedCopy =1;

  Uint8List? _originalImageBytes;
  Uint8List? _processedImageBytes;
  final ImagePicker _picker = ImagePicker();
  bool isProcessing = false;

  // Dress position and scale
  Offset _dressOffset = const Offset(0, 0);
  double _dressScale = 1.0;
  double _dressRotation = 0.0;

  Offset _initialFocalPoint = Offset.zero;
  Offset _initialDressOffset = Offset.zero;
  double _initialDressScale = 1.0;
  double _initialDressRotation = 0.0;

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image == null) {
        _showMessage("No image selected");
        return;
      }

      final File imageFile = File(image.path);
      final bytes = await imageFile.readAsBytes();

      // Decode and resize if needed
      img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) {
        _showMessage("Could not decode image");
        return;
      }

      if (decoded.width > 2000 || decoded.height > 2000) {
        decoded = img.copyResize(decoded, width: 2000);
      }

      final resizedBytes = Uint8List.fromList(img.encodeJpg(decoded, quality: 90));

      setState(() {
        _originalImageBytes = resizedBytes;
        _processedImageBytes = null;
        selectedBackground = "";
        selectedDress = "Original";
        selectedCopy = 1;
        _dressOffset = const Offset(0, 0);
        _dressScale = 1.0;
      });

    } catch (e) {
      _showMessage("Error: ${e.toString()}");
    }
  }
  Future<bool> _detectFace(Uint8List imageBytes) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/temp.jpg');
      await tempFile.writeAsBytes(imageBytes);

      final inputImage = InputImage.fromFile(tempFile);
      final faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableContours: false,
          enableLandmarks: false,
        ),
      );

      final faces = await faceDetector.processImage(inputImage);
      await faceDetector.close();

      return faces.isNotEmpty;
    } catch (e) {
      _showMessage("Face detection error: ${e.toString()}");
      return false;
    }
  }

  Future<void> _removeBackground() async {
    if (_originalImageBytes == null) return;

    setState(() {
      isProcessing = true;
    });

    final hasFace = await _detectFace(_originalImageBytes!);
    if (!hasFace) {
      _showMessage("No face detected. Background change skipped.");
      setState(() => isProcessing = false);
      return;
    }

    try {
      final removedBgBytes = await removeBackground(imageBytes: _originalImageBytes!);
      final decodedImage = img.decodeImage(removedBgBytes);
      if (decodedImage == null) {
        _showMessage("Failed to process image");
        setState(() => isProcessing = false);
        return;
      }

      // Fill transparent background with selected color
      final bgColor = _getSelectedColor();
      final withBg = img.Image(width: decodedImage.width, height: decodedImage.height);
      img.fill(withBg, color: bgColor);

      for (int y = 0; y < decodedImage.height; y++) {
        for (int x = 0; x < decodedImage.width; x++) {
          final pixel = decodedImage.getPixel(x, y);
          if (pixel.a > 0) withBg.setPixel(x, y, pixel);
        }
      }

      // Add top padding (15%)
      final topPadding = (withBg.height * 0.15).toInt();
      final paddedImage = img.Image(
        width: withBg.width,
        height: withBg.height + topPadding,
      );
      img.fill(paddedImage, color: bgColor);

      for (int y = 0; y < withBg.height; y++) {
        for (int x = 0; x < withBg.width; x++) {
          paddedImage.setPixel(x, y + topPadding, withBg.getPixel(x, y));
        }
      }

      // Resize only if image is too small or too large
      img.Image finalImage = paddedImage;

      // Define passport size
      const targetWidth = 413;
      const targetHeight = 531;

      if (paddedImage.width < targetWidth || paddedImage.height < targetHeight ||
          paddedImage.width > targetWidth * 2 || paddedImage.height > targetHeight * 2) {
        finalImage = img.copyResize(
          paddedImage,
          width: targetWidth,
          height: targetHeight,
          interpolation: img.Interpolation.linear, // High quality
        );
      }

      // Center crop (optional if resize above matches exactly)
      final cropped = img.copyCrop(
        finalImage,
        x: (finalImage.width - targetWidth) ~/ 2,
        y: (finalImage.height - targetHeight) ~/ 2,
        width: targetWidth,
        height: targetHeight,
      );

      final pngBytes = img.encodePng(cropped);

      setState(() {
        _processedImageBytes = Uint8List.fromList(pngBytes);
        _dressOffset = const Offset(0, 0);
        _dressScale = 1.0;
      });

    } catch (e) {
      _showMessage("Error: ${e.toString()}");
    }

    setState(() => isProcessing = false);
  }

  img.ColorRgb8 _getSelectedColor() {
    switch (selectedBackground) {
      case 'blue':
        return img.ColorRgb8(0, 102, 204);
      case 'grey':
        return img.ColorRgb8(200, 200, 200);
      default:
        return img.ColorRgb8(255, 255, 255);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text("Take a photo"),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text("Choose from gallery"),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final imageToShow = _processedImageBytes ?? _originalImageBytes;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Passport Photo Maker"),
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: _showImageSourceDialog,
              child: Container(
                height: 250,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[700]!),
                ),
                child: isProcessing
                    ? const Center(child: CircularProgressIndicator(color: Colors.white))
                    : imageToShow != null
                    ? Center(
                  child: ClipRect(
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        Image.memory(
                          imageToShow,
                          fit: BoxFit.contain,
                        ),
                        if (_processedImageBytes != null && selectedDress != "Original")
                          Positioned(
                            left: _dressOffset.dx,
                            top: _dressOffset.dy,
                            child: GestureDetector(
                              onScaleStart: (details) {
                                _initialFocalPoint = details.focalPoint;
                                _initialDressOffset = _dressOffset;
                                _initialDressScale = _dressScale;
                                _initialDressRotation = _dressRotation;
                              },
                              onScaleUpdate: (details) {
                                setState(() {
                                  _dressScale = (_initialDressScale * details.scale).clamp(0.5, 3.0);
                                  final delta = details.focalPoint - _initialFocalPoint;
                                  _dressOffset = _initialDressOffset + delta;
                                  _dressRotation = _initialDressRotation + details.rotation;
                                });
                              },
                              child: Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.identity()
                                  ..translate(0.0, 0.0)
                                  ..scale(_dressScale)
                                  ..rotateZ(_dressRotation),
                                child: Image.asset(
                                  _getDressAssetPath(selectedDress),
                                  width: 200,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                )


                    : const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.upload, color: Colors.white70, size: 40),
                      SizedBox(height: 8),
                      Text("Tap to upload photo", style: TextStyle(color: Colors.white60)),
                    ],
                  ),
                ),
              ),
            ),
            if (_processedImageBytes != null && selectedDress == "Gents")
              TextButton(
                onPressed: () {
                  setState(() {
                    _dressOffset = const Offset(0, 0);
                    _dressScale = 1.0;
                    _dressRotation = 0.0;
                  });
                },
                child: const Text("Reset Dress", style: TextStyle(color: Colors.white70)),
              ),            const SizedBox(height: 24),

            const Align(
              alignment: Alignment.centerLeft,
              child: Text("Background", style: TextStyle(color: Colors.white70, fontSize: 16)),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              children: ["white", "blue", "grey"].map((color) {
                return ChoiceChip(
                  label: Text(color, style: const TextStyle(color: Colors.white)),
                  selectedColor: Colors.blueGrey[700],
                  selected: selectedBackground == color,
                  onSelected: (_) {
                    setState(() => selectedBackground = color);
                    if (_originalImageBytes != null) _removeBackground();
                  },
                  backgroundColor: Colors.grey[800],
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            const Align(
              alignment: Alignment.centerLeft,
              child: Text("Dress Type", style: TextStyle(color: Colors.white70, fontSize: 16)),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.grey[850],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey[700]!),
              ),
              child: DropdownButton<String>(
                dropdownColor: Colors.grey[900],
                value: selectedDress,
                underline: const SizedBox(),
                iconEnabledColor: Colors.white70,
                style: const TextStyle(color: Colors.white),
                isExpanded: true,
                onChanged: (val) => setState(() => selectedDress = val!),
                items: ["Original", "Gents", "Ladies", "Kids"]
                    .map((e) => DropdownMenuItem(
                  value: e,
                  child: Text("Formal - $e"),
                ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 24),

            const Align(
              alignment: Alignment.centerLeft,
              child: Text("No. of Copies", style: TextStyle(color: Colors.white70, fontSize: 16)),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              children: [4, 6, 8, 16].map((num) {
                return ChoiceChip(
                  label: Text('$num', style: const TextStyle(color: Colors.white)),
                  selectedColor: Colors.deepPurple,
                  selected: selectedCopy == num,
                  onSelected: (_) => setState(() => selectedCopy = num),
                  backgroundColor: Colors.grey[800],
                );
              }).toList(),
            ),
            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _processedImageBytes != null
                    ? () {
                  Navigator.pushNamed(
                    context,
                    '/export',
                    arguments: {
                      'imageBytes': _processedImageBytes,
                      'background': selectedBackground,
                      'dress': selectedDress,
                      'copies': selectedCopy,
                    },
                  );
                }
                    : null,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text("Continue"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _processedImageBytes != null ? Colors.deepPurple : Colors.grey[800],
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getDressAssetPath(String dressType) {
    switch (dressType) {
      case "Gents":
        return 'assets/dress/dress_gents.png';
      case "Ladies":
        return 'assets/dress/dress_ladies.png';
      case "Kids":
        return 'assets/dress/dress_kids.png';
      default:
        return ''; // No overlay
    }
  }
}
