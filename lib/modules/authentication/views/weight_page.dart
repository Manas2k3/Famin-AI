// file: weight_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import '../../../data/repositories/authentication/authentication_repository.dart';
import '../../../modules/authentication/widgets/verify_mail.dart';
import 'birth_year_page.dart';

class WeightPage extends StatefulWidget {
  const WeightPage({Key? key}) : super(key: key);

  @override
  State<WeightPage> createState() => _WeightPageState();
}

class _WeightPageState extends State<WeightPage> {
  // units: true => metric (kg), false => imperial (lb)
  bool _isMetric = true;

  final List<int> _kgValues = List<int>.generate(201, (i) => 30 + i); // 30..230 kg
  int _selectedKg = 64;

  // lbs range (66..506) roughly 30kg -> 230kg
  late final List<int> _lbValues;
  int _selectedLb = 141; // ~64kg

  final box = GetStorage();

  // controllers so wheel opens at the selected item
  late final FixedExtentScrollController _kgController;
  late final FixedExtentScrollController _lbController;

  @override
  void initState() {
    super.initState();
    _lbValues = List<int>.generate(441, (i) => 66 + i); // 66..506

    final kg = box.read('weight_kg') as int?;
    final lb = box.read('weight_lb') as int?;
    if (kg != null) _selectedKg = kg;
    if (lb != null) _selectedLb = lb;

    // keep lb in sync if kg provided
    _selectedLb = (_selectedKg * 2.20462).round();

    // initialize controllers at the correct index (fall back to some safe index)
    final kgIndex = _kgValues.indexOf(_selectedKg);
    _kgController = FixedExtentScrollController(initialItem: kgIndex >= 0 ? kgIndex : 0);

    final lbIndex = _lbValues.indexOf(_selectedLb);
    _lbController = FixedExtentScrollController(initialItem: lbIndex >= 0 ? lbIndex : 0);
  }

  @override
  void dispose() {
    _kgController.dispose();
    _lbController.dispose();
    super.dispose();
  }

  // helper conversions
  int _kgToLb(int kg) => (kg * 2.20462).round();
  int _lbToKg(int lb) => (lb / 2.20462).round();

  Future<void> _finishAndSave() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Get.snackbar('Error', 'No signed-in user found.');
      return;
    }

    final kg = _isMetric ? _selectedKg : _lbToKg(_selectedLb);
    final lb = _isMetric ? _kgToLb(_selectedKg) : _selectedLb;

    // local storage
    box.write('weight_kg', kg);
    box.write('weight_lb', lb);
    box.write('weight_display_kg', '$kg kg');
    box.write('weight_display_lb', '$lb lb');

    // save to firestore
    await FirebaseFirestore.instance.collection('Users').doc(user.uid).set({
      'weight_kg': kg,
      'weight_lb': lb,
    }, SetOptions(merge: true));

    AuthenticationRepository.instance.completeWeight();
    Get.offAll(() => const BirthYearPage());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.pink.shade200,
        elevation: 0,
        title: const Text('How much do you weigh?', style: TextStyle(color: Colors.white),),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: LinearProgressIndicator(
                value: 0.8,
                backgroundColor: Colors.grey.shade200,
                color: Colors.pink.shade300,
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 18),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                'Tell us your weight',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
            ),

            // toggle
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
                              )
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
                              )
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

            // Display card
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
                      text: '$_selectedKg ',
                      style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.black),
                      children: const [
                        TextSpan(
                            text: 'kg',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w600))
                      ],
                    ),
                  )
                      : RichText(
                    text: TextSpan(
                      text: '$_selectedLb ',
                      style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.black),
                      children: const [
                        TextSpan(
                            text: 'lb',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w600))
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Wheel picker
            Expanded(
              child: Center(
                child: SizedBox(
                  height: 220,
                  child: _isMetric ? _buildKgWheel() : _buildLbWheel(),
                ),
              ),
            ),

            // Finish button
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _finishAndSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.pink.shade200,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 2,
                  ),
                  child: const Text('Finish',
                      style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKgWheel() {
    return ListWheelScrollView.useDelegate(
      controller: _kgController,
      itemExtent: 56,
      physics: const FixedExtentScrollPhysics(),
      diameterRatio: 1.6,
      perspective: 0.003,
      onSelectedItemChanged: (index) {
        setState(() {
          _selectedKg = _kgValues[index];
          _selectedLb = _kgToLb(_selectedKg);
        });
      },
      childDelegate: ListWheelChildBuilderDelegate(
        builder: (context, index) {
          final v = _kgValues[index];
          final isSelected = v == _selectedKg;
          return Center(
            child: Text(
              '$v kg',
              style: TextStyle(
                fontSize: isSelected ? 26 : 18,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w400,
                color: isSelected ? Colors.pink.shade400 : Colors.grey,
              ),
            ),
          );
        },
        childCount: _kgValues.length,
      ),
    );
  }

  Widget _buildLbWheel() {
    return ListWheelScrollView.useDelegate(
      controller: _lbController,
      itemExtent: 56,
      physics: const FixedExtentScrollPhysics(),
      diameterRatio: 1.6,
      perspective: 0.003,
      onSelectedItemChanged: (index) {
        setState(() {
          _selectedLb = _lbValues[index];
          _selectedKg = _lbToKg(_selectedLb);
        });
      },
      childDelegate: ListWheelChildBuilderDelegate(
        builder: (context, index) {
          final v = _lbValues[index];
          final isSelected = v == _selectedLb;
          return Center(
            child: Text(
              '$v lb',
              style: TextStyle(
                fontSize: isSelected ? 26 : 18,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w400,
                color: isSelected ? Colors.pink.shade400 : Colors.grey,
              ),
            ),
          );
        },
        childCount: _lbValues.length,
      ),
    );
  }
}
