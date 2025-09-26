import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../../../data/repositories/authentication/authentication_repository.dart';
import '../views/weight_page.dart';

class HeightPage extends StatefulWidget {
  const HeightPage({Key? key}) : super(key: key);

  @override
  State<HeightPage> createState() => _HeightPageState();
}

class _HeightPageState extends State<HeightPage> {
  // units: true => metric (cm), false => imperial (ft/in)
  bool _isMetric = true;

  // metric: 100..240 cm, default 170
  final List<int> _cmValues = List<int>.generate(141, (i) => 100 + i); // 100..240
  int _selectedCm = 170;

  // imperial: store inches (e.g., 5'7" = 67 in). Range: 3'0" (36) to 7'11" (95)
  final List<int> _inchValues = List<int>.generate(60, (i) => 36 + i); // 36..95
  int _selectedInch = 67; // ~170 cm

  final box = GetStorage();

  late final FixedExtentScrollController _cmController;
  late final FixedExtentScrollController _inchController;

  @override
  void initState() {
    super.initState();

    // initialize selected values from storage if exist
    final cm = box.read('height_cm') as int?;
    final inch = box.read('height_in') as int?;

    if (cm != null) _selectedCm = cm;
    if (inch != null) _selectedInch = inch;

    // If only cm provided and inch not, keep consistency
    if (cm != null && inch == null) {
      _selectedInch = _cmToInch(_selectedCm);
    } else if (inch != null && cm == null) {
      _selectedCm = _inchToCm(_selectedInch);
    }

    // initialize controllers at right index
    final cmIndex = _cmValues.indexOf(_selectedCm);
    _cmController = FixedExtentScrollController(initialItem: cmIndex >= 0 ? cmIndex : 0);

    final inchIndex = _inchValues.indexOf(_selectedInch);
    _inchController = FixedExtentScrollController(initialItem: inchIndex >= 0 ? inchIndex : 0);
  }

  @override
  void dispose() {
    _cmController.dispose();
    _inchController.dispose();
    super.dispose();
  }

  // Helper conversions
  int _cmToInch(int cm) => (cm / 2.54).round();
  int _inchToCm(int inches) => (inches * 2.54).round();

  String _formatInchDisplay(int inches) {
    final ft = inches ~/ 12;
    final rem = inches % 12;
    return "$ft' ${rem}\"";
  }

  // Save both representations into Firestore
  Future<void> _saveHeightAndContinue() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Get.snackbar('Error', 'No signed-in user found.');
      return;
    }

    final cm = _isMetric ? _selectedCm : _inchToCm(_selectedInch);
    final inches = _isMetric ? _cmToInch(_selectedCm) : _selectedInch;

    // Local storage
    box.write('height_cm', cm);
    box.write('height_in', inches);
    box.write('height_display_metric', '$cm cm');
    box.write('height_display_imperial', _formatInchDisplay(inches));

    // Save to Firestore (merge to avoid overwriting other user fields)
    await FirebaseFirestore.instance.collection('Users').doc(user.uid).set(
      {
        'height_cm': cm,
        'height_in': inches,
      },
      SetOptions(merge: true),
    );

    // mark height step done and navigate to weight
    AuthenticationRepository.instance.completeHeight();
    Get.offAll(() => const WeightPage());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.pink.shade200,
        elevation: 0,
        title: const Text(
          'How tall are you?',
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
        systemOverlayStyle: theme.appBarTheme.systemOverlayStyle,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 18),

            // progress line mimic
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: LinearProgressIndicator(
                value: 0.5,
                backgroundColor: Colors.grey.shade200,
                color: Colors.pink.shade300,
                minHeight: 4,
              ),
            ),

            const SizedBox(height: 18),

            // Title
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                'Tell us your height',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
            ),

            // Unit toggle segmented control
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48.0, vertical: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _isMetric = true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: _isMetric
                              ? BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.03),
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          )
                              : null,
                          child: Center(
                            child: Text(
                              'Metric',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _isMetric ? Colors.black : Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _isMetric = false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: !_isMetric
                              ? BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.03),
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          )
                              : null,
                          child: Center(
                            child: Text(
                              'Imperial',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: !_isMetric ? Colors.black : Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Big display card showing the selected value
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18.0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: _isMetric
                      ? RichText(
                    text: TextSpan(
                      text: '$_selectedCm ',
                      style: const TextStyle(
                          fontSize: 36, fontWeight: FontWeight.bold, color: Colors.black),
                      children: const [
                        TextSpan(
                          text: 'cm',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  )
                      : RichText(
                    text: TextSpan(
                      text: _formatInchDisplay(_selectedInch),
                      style: const TextStyle(
                          fontSize: 36, fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Wheel picker area (expanded)
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Center(
                  child: SizedBox(
                    height: 220,
                    child: _isMetric ? _buildCmWheel() : _buildInchWheel(),
                  ),
                ),
              ),
            ),

            // Next button
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _saveHeightAndContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.pink.shade200,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    elevation: 2,
                  ),
                  child: const Text(
                    'Next',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCmWheel() {
    return ListWheelScrollView.useDelegate(
      controller: _cmController,
      itemExtent: 56,
      physics: const FixedExtentScrollPhysics(),
      diameterRatio: 1.6,
      perspective: 0.003,
      onSelectedItemChanged: (index) {
        setState(() {
          _selectedCm = _cmValues[index];
        });
      },
      childDelegate: ListWheelChildBuilderDelegate(
        builder: (context, index) {
          final v = _cmValues[index];
          final isSelected = v == _selectedCm;
          return Center(
            child: Text(
              '$v cm',
              style: TextStyle(
                fontSize: isSelected ? 26 : 18,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w400,
                color: isSelected ? Colors.pink.shade400 : Colors.grey,
              ),
            ),
          );
        },
        childCount: _cmValues.length,
      ),
    );
  }

  Widget _buildInchWheel() {
    return ListWheelScrollView.useDelegate(
      controller: _inchController,
      itemExtent: 56,
      physics: const FixedExtentScrollPhysics(),
      diameterRatio: 1.6,
      perspective: 0.003,
      onSelectedItemChanged: (index) {
        setState(() {
          _selectedInch = _inchValues[index];
        });
      },
      childDelegate: ListWheelChildBuilderDelegate(
        builder: (context, index) {
          final v = _inchValues[index];
          final isSelected = v == _selectedInch;
          return Center(
            child: Text(
              _formatInchDisplay(v),
              style: TextStyle(
                fontSize: isSelected ? 26 : 18,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w400,
                color: isSelected ? Colors.pink.shade400 : Colors.grey,
              ),
            ),
          );
        },
        childCount: _inchValues.length,
      ),
    );
  }
}
