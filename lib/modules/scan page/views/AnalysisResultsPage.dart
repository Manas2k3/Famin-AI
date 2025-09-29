import 'dart:io';
import 'package:flutter/material.dart';

class AnalysisResultsPage extends StatelessWidget {
  const AnalysisResultsPage({super.key, this.imageFile});

  /// Optional: show the just-picked image on top if you pass it in
  final File? imageFile;

  @override
  Widget build(BuildContext context) {
    const titleStyle = TextStyle(
      fontWeight: FontWeight.w800,
      fontSize: 24,
      color: Colors.black,
      letterSpacing: .2,
    );

    const sectionHeader = TextStyle(
      fontWeight: FontWeight.w900,
      fontSize: 26,
      color: Colors.black,
      height: 1.2,
    );

    const labelStyle = TextStyle(
      fontSize: 16,
      color: Color(0xFF866B6C), // muted mauve/brown like the mock
      fontWeight: FontWeight.w600,
      height: 1.4,
      letterSpacing: .2,
    );

    const headingStyle = TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w900,
      color: Colors.black,
      height: 1.2,
    );

    const bodyStyle = TextStyle(
      fontSize: 16,
      color: Color(0xFF8C7373),
      height: 1.5,
      letterSpacing: .2,
      fontWeight: FontWeight.w500,
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text("Scan Results", style: titleStyle),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Top banner image (pads-like image)
          AspectRatio(
            aspectRatio: 16 / 9,
            child: imageFile != null
                ? Image.file(imageFile!, fit: BoxFit.cover)
                : Image.asset(
              'assets/images/sample_pad.jpg', // fallback if you want; else keep a placeholder
              fit: BoxFit.cover,
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Observations", style: sectionHeader),
                const SizedBox(height: 22),

                _ObservationTile(
                  label: "Symptom Detected",
                  title: "Iron Deficiency",
                  body:
                  "Low iron levels may contribute to fatigue and weakness.",
                  iconCard: _IconCard(
                    bg: const Color(0xFF4B2E2E),
                    child: const Icon(Icons.water_drop, size: 44, color: Color(0xFFD33A2C)),
                  ),
                  labelStyle: labelStyle,
                  titleStyle: headingStyle,
                  bodyStyle: bodyStyle,
                ),

                const SizedBox(height: 24),

                _ObservationTile(
                  label: "Observation",
                  title: "Light Flow",
                  body:
                  "Your flow appears lighter than average, which could be due to various factors.",
                  iconCard: _IconCard(
                    bg: const Color(0xFFF4F4F4),
                    child: const Icon(Icons.psychology_alt_outlined, size: 44, color: Colors.black87),
                  ),
                  labelStyle: labelStyle,
                  titleStyle: headingStyle,
                  bodyStyle: bodyStyle,
                ),

                const SizedBox(height: 24),

                _ObservationTile(
                  label: "Recommendation",
                  title: "Consider Increasing Iron Intake",
                  body:
                  "Consult with a healthcare professional about dietary changes or supplements.",
                  iconCard: _IconCard(
                    bg: const Color(0xFFFFE8E8),
                    child: const Icon(Icons.favorite_border, size: 44, color: Color(0xFFEA7B7B)),
                  ),
                  labelStyle: labelStyle,
                  titleStyle: headingStyle,
                  bodyStyle: bodyStyle,
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ObservationTile extends StatelessWidget {
  const _ObservationTile({
    required this.label,
    required this.title,
    required this.body,
    required this.iconCard,
    required this.labelStyle,
    required this.titleStyle,
    required this.bodyStyle,
  });

  final String label;
  final String title;
  final String body;
  final Widget iconCard;
  final TextStyle labelStyle;
  final TextStyle titleStyle;
  final TextStyle bodyStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Text block
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: labelStyle),
              const SizedBox(height: 6),
              Text(title, style: titleStyle),
              const SizedBox(height: 6),
              Text(body, style: bodyStyle),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // Right icon card
        iconCard,
      ],
    );
  }
}

class _IconCard extends StatelessWidget {
  const _IconCard({required this.bg, required this.child});

  final Color bg;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      width: 96,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}
