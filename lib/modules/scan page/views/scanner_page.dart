// lib/features/scanner/scanner_page.dart
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:iconsax/iconsax.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import 'AnalysisResultsPage.dart';

class ScannerPage extends StatefulWidget {

  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {

  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;
  bool _submitting = false;
  Color get _pink => Colors.pink.shade200;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initPermissions());
  }

  Future<void> _initPermissions() async {
    await [Permission.camera, Permission.photos, Permission.storage].request();
  }

  Future<bool> _requestPermission(Permission permission) async {
    var status = await permission.status;
    if (!status.isGranted) status = await permission.request();
    return status.isGranted;
  }

  // ====== PICK (no crop) ======
  Future<void> _pickFrom(ImageSource source) async {
    // Permissions
    if (source == ImageSource.camera) {
      final ok = await _requestPermission(Permission.camera);
      if (!ok) return _showPermissionDeniedDialog("Camera");
    } else {
      bool storageGranted;
      if (Platform.isAndroid) {
        storageGranted = await _requestPermission(Permission.photos) ||
            await _requestPermission(Permission.storage);
      } else {
        storageGranted = await _requestPermission(Permission.photos);
      }
      if (!storageGranted) return _showPermissionDeniedDialog("Gallery");
    }

    // Pick
    final XFile? image = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (image == null) return;

    // No crop: use as-is
    setState(() => _selectedImage = File(image.path));
  }

  Future<void> _showPickSheet() async {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text("Capture with Camera"),
              subtitle: const Text("Open camera and take a new photo"),
              onTap: () {
                Navigator.pop(context);
                _pickFrom(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text("Choose from Gallery"),
              subtitle: const Text("Pick an existing photo"),
              onTap: () {
                Navigator.pop(context);
                _pickFrom(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  // Legacy direct triggers (kept so your action tiles still work)
  Future<void> _captureImage() => _pickFrom(ImageSource.camera);
  Future<void> _pickFromGallery() => _pickFrom(ImageSource.gallery);

  void _removeImage() {
    setState(() => _selectedImage = null);
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

  // ===================== UI =====================

  @override
  Widget build(BuildContext context) {
    final pink = _pink;
    final bg = Colors.white;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        backgroundColor: bg,
        title: ShaderMask(
          shaderCallback: (rect) =>
              LinearGradient(colors: [pink, Colors.pink.shade300]).createShader(rect),
          child: const Text(
            "Scan",
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 24,
              color: Colors.white,
              letterSpacing: 0.3,
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: "Upload options",
            onPressed: _showPickSheet,
            icon: Icon(Iconsax.add_square, color: Colors.pink.shade300),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned(top: -140, left: -80, child: _GlowBlob(color: pink.withOpacity(.25), size: 320)),
          Positioned(top: -220, right: -60, child: _GlowBlob(color: Colors.pink.shade100.withOpacity(.25), size: 260)),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _GlassCard(
                    child: Row(
                      children: [
                        Container(
                          height: 56,
                          width: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(colors: [pink, Colors.pink.shade100]),
                          ),
                          child: const Icon(Iconsax.scan, color: Colors.white),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Text(
                            "Choose an option",
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: .2),
                          ),
                        ),
                        Icon(Iconsax.arrow_down_1, color: Colors.grey.shade600),
                      ],
                    ),
                  ).animate().fadeIn(duration: 250.ms).moveY(begin: 8, end: 0, curve: Curves.easeOut),
                  const SizedBox(height: 16),

                  // Action tiles
                  LayoutBuilder(
                    builder: (context, c) {
                      final isWide = c.maxWidth > 560;
                      final children = [
                        _ActionTile(
                          title: "Capture",
                          subtitle: "Use camera",
                          icon: Iconsax.camera,
                          color: pink,
                          onTap: _captureImage,
                        ),
                        _ActionTile(
                          title: "Gallery",
                          subtitle: "Pick a photo",
                          icon: Iconsax.image,
                          color: Colors.pink.shade100,
                          outline: true,
                          onTap: _pickFromGallery,
                        ),
                      ];
                      return isWide
                          ? Row(children: [Expanded(child: children[0]), const SizedBox(width: 14), Expanded(child: children[1])])
                          : Column(children: [children[0], const SizedBox(height: 14), children[1]]);
                    },
                  ).animate().fadeIn(duration: 280.ms).moveY(begin: 12, end: 0, curve: Curves.easeOut),

                  const SizedBox(height: 18),

                  _GlassCard(
                    padding: const EdgeInsets.all(14),
                    child: AnimatedSwitcher(
                      duration: 250.ms,
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: _selectedImage == null
                          ? _EmptyPreview(color: pink, key: const ValueKey('empty'))
                          : Column(
                        key: const ValueKey('img'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ImagePreview(file: _selectedImage!),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                onPressed: _removeImage,
                                icon: const Icon(Iconsax.trash),
                                label: const Text("Remove"),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.red.shade400,
                                ),
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),



      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: FilledButton.icon(
            onPressed: (_selectedImage == null || _submitting)
                ? null
                : () async {
              setState(() => _submitting = true);

              // Fake load for ~5s
              await Future.delayed(const Duration(seconds: 5));
              if (!mounted) return;

              setState(() => _submitting = false);

              // Navigate to results, pass the picked file to show on top banner
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AnalysisResultsPage(imageFile: _selectedImage),
                ),
              );
            },
            icon: _submitting
                ? const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
            )
                : const Icon(Iconsax.send_2),
            label: Text(
              _submitting ? "Analyzing..." : "Submit",
              style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: .2),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _selectedImage == null
                  ? Colors.pink.shade100
                  : (_submitting ? Colors.pink.shade200 : Colors.pink.shade300),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: _selectedImage == null ? 0 : 2,
            ),
          )
              .animate(target: _selectedImage == null ? 0 : 1).scale(begin: const Offset(.995, .995), end: const Offset(1, 1)),
        ),
      ),
    );
  }
}

// ---------- UI bits ----------

class _GlowBlob extends StatelessWidget {
  final double size;
  final Color color;
  const _GlowBlob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size, width: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [BoxShadow(color: color, blurRadius: 80, spreadRadius: 20)],
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  const _GlassCard({required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding ?? const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.pink.shade50, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.pink.shade100.withOpacity(.35),
                blurRadius: 22,
                spreadRadius: -6,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool outline;
  final VoidCallback onTap;

  const _ActionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.outline = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final border = Border.all(color: Colors.pink.shade100, width: 1.2);
    return Material(
      color: outline ? Colors.white : color,
      elevation: outline ? 0 : 1.5,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: outline ? border : null,
          ),
          child: Row(
            children: [
              Container(
                height: 52,
                width: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: outline ? Colors.pink.shade50 : Colors.white.withOpacity(.95),
                ),
                child: Icon(icon, color: Colors.pink.shade300),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: outline ? Colors.pink.shade300 : Colors.white,
                        )),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: outline ? Colors.grey.shade600 : Colors.white.withOpacity(.95),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Iconsax.arrow_right_3, color: outline ? Colors.pink.shade300 : Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

// Dashed empty-state painter (no dotted_border dependency)
class _EmptyPreview extends StatelessWidget {
  final Color color;
  const _EmptyPreview({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 10,
      child: CustomPaint(
        painter: _DashedBorderPainter(color: color, strokeWidth: 1.6),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Iconsax.gallery, size: 40, color: color),
              const SizedBox(height: 8),
              Text(
                "No image selected",
                style: TextStyle(fontWeight: FontWeight.w700, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 6),
              Text(
                "Capture or pick from gallery",
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double gap;
  final double dash;

  _DashedBorderPainter({
    required this.color,
    this.strokeWidth = 1.6,
    this.dash = 7,
    this.gap = 6,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16));
    final path = Path()..addRRect(rrect);

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final segment = metric.extractPath(distance, distance + dash);
        canvas.drawPath(segment, paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth || old.gap != gap || old.dash != dash;
}

class _ImagePreview extends StatelessWidget {
  final File file;
  const _ImagePreview({super.key, required this.file});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: 16 / 10,
            child: Image.file(
              file,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                print('[ImagePreview] Load error: $error\n$stackTrace');
                return Container(
                  color: Colors.grey.shade200,
                  alignment: Alignment.center,
                  child: const Icon(Icons.error_outline, color: Colors.red, size: 48),
                );
              },
            ),
          ),
          Positioned(
            right: 10,
            top: 10,
            child: _PillBadge(icon: Iconsax.tick_circle, label: "Ready"),
          ),
        ],
      ),
    );
  }
}

class _PillBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _PillBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.pink.shade100),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.pink.shade300),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: Colors.pink.shade300),
          ),
        ],
      ),
    );
  }
}
