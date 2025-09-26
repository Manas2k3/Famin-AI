import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;

  @override
  void initState() {
    super.initState();
    // Ensure permissions plugin is initialized before first use
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initPermissions();
    });
  }

  Future<void> _initPermissions() async {
    await [
      Permission.camera,
      Permission.photos,
      Permission.storage,
    ].request();
  }

  Future<bool> _requestPermission(Permission permission) async {
    var status = await permission.status;
    if (!status.isGranted) {
      status = await permission.request();
    }
    return status.isGranted;
  }

  // Open Camera
  Future<void> _captureImage() async {
    bool cameraGranted = await _requestPermission(Permission.camera);
    if (!cameraGranted) {
      _showPermissionDeniedDialog("Camera");
      return;
    }

    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  // Open Gallery
  Future<void> _pickFromGallery() async {
    bool storageGranted;

    if (Platform.isAndroid) {
      // Android 13+ requires READ_MEDIA_IMAGES instead of READ_EXTERNAL_STORAGE
      if (await _requestPermission(Permission.photos)) {
        storageGranted = true;
      } else if (await _requestPermission(Permission.storage)) {
        storageGranted = true;
      } else {
        storageGranted = false;
      }
    } else {
      // iOS
      storageGranted = await _requestPermission(Permission.photos);
    }

    if (!storageGranted) {
      _showPermissionDeniedDialog("Gallery");
      return;
    }

    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  void _showPermissionDeniedDialog(String feature) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("$feature Permission Required"),
        content: Text("Please enable $feature access from settings."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text("Open Settings"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          "Scan",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 15, // this will work only if you use flutter >=3.24
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 70),
              child: Text(
                "Choose an option",
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
              ),
            ),
            GestureDetector(
              onTap: _captureImage,
              child: Container(
                height: MediaQuery.of(context).size.height * 0.06,
                width: MediaQuery.of(context).size.width * 0.5,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  color: Colors.red,
                ),
                alignment: Alignment.center,
                child: const Text(
                  "Capture Image",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            GestureDetector(
              onTap: _pickFromGallery,
              child: Container(
                height: MediaQuery.of(context).size.height * 0.06,
                width: MediaQuery.of(context).size.width * 0.6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  color: Colors.grey.shade300,
                ),
                alignment: Alignment.center,
                child: const Text(
                  "Upload from gallery",
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            if (_selectedImage != null) ...[
              const SizedBox(height: 20),
              const Text(
                "Preview:",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Column(
                spacing: 15,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      _selectedImage!,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {},
                    child: Container(
                      height: MediaQuery.of(context).size.height * 0.04,
                      width: MediaQuery.of(context).size.width * 0.3,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.red,
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        "Submit",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
