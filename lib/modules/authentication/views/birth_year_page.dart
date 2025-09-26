// lib/modules/authentication/views/birth_year_page.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:famina/features/period%20cycle/cycleSelectionPage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../../../data/repositories/authentication/authentication_repository.dart';
import '../../../modules/authentication/widgets/verify_mail.dart';
import '../../../modules/authentication/views/weight_page.dart';
import 'additional_period_related_questions.dart';
import 'health_conditions_page.dart';

class BirthYearPage extends StatefulWidget {
  const BirthYearPage({Key? key}) : super(key: key);

  @override
  State<BirthYearPage> createState() => _BirthYearPageState();
}

class _BirthYearPageState extends State<BirthYearPage> {
  final box = GetStorage();
  final int minYear = 1990;
  late final int currentYear;
  late final int maxSelectableYear; // currentYear - 16

  // generated year list
  late List<int> years;

  // wheel selected index & user picked state
  int _selectedIndex = 0;
  bool _hasPicked = false;

  // show a subtle hint until first pick
  String get selectedDisplay =>
      _hasPicked ? '${years[_selectedIndex]}' : 'Select';

  @override
  void initState() {
    super.initState();
    currentYear = DateTime.now().year;
    maxSelectableYear = currentYear - 16;

    // clamp maxSelectableYear so UI has values; ensure it's >= minYear
    final actualMax = maxSelectableYear < minYear ? minYear : maxSelectableYear;

    // build list from minYear .. actualMax (ascending)
    years = [for (int y = minYear; y <= actualMax; y++) y];

    // default selection visually in middle (but not counted as "picked")
    _selectedIndex = (years.length ~/ 2).clamp(0, years.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.pink.shade200,
        elevation: 0,
        centerTitle: true,
        title: Text('When were you born?', style: TextStyle(color: Colors.white),),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 18),

            // Subheading text
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                "Your age can have some relevance with cycle. Knowing it would help us make better predictions",
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 28),

            // big selected display card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    selectedDisplay == 'Select' ? 'Select' : '${selectedDisplay}',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: selectedDisplay == 'Select'
                          ? Colors.grey
                          : Colors.black,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // wheel picker area (large)
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  // subtle top rounded card to mimic the reference style
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 18),
                    // Wheel picker
                    SizedBox(
                      height: 240,
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          // When user scrolls the wheel, mark as picked
                          if (notification is ScrollEndNotification && !_hasPicked) {
                            setState(() => _hasPicked = true);
                          }
                          return false;
                        },
                        child: ListWheelScrollView.useDelegate(
                          itemExtent: 56,
                          physics: const FixedExtentScrollPhysics(),
                          perspective: 0.003,
                          diameterRatio: 1.4,
                          overAndUnderCenterOpacity: 0.5,
                          onSelectedItemChanged: (index) {
                            setState(() {
                              _selectedIndex = index;
                              _hasPicked = true;
                            });
                          },
                          childDelegate: ListWheelChildBuilderDelegate(
                            builder: (context, index) {
                              if (index < 0 || index >= years.length) return null;
                              final y = years[index];
                              final isSelected = index == _selectedIndex && _hasPicked;
                              return Center(
                                child: Text(
                                  '$y',
                                  style: TextStyle(
                                    fontSize: isSelected ? 28 : 20,
                                    fontWeight:
                                    isSelected ? FontWeight.bold : FontWeight.w400,
                                    color: isSelected ? Colors.pink.shade400 : Colors.grey,
                                  ),
                                ),
                              );
                            },
                            childCount: years.length,
                          ),
                        ),
                      ),
                    ),

                    SizedBox(height: MediaQuery.of(context).size.height*0.11),

                    // bottom Next button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.pink.shade200,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(32),
                            ),
                          ),
                          onPressed: (_hasPicked && _isSelectionAllowed())
                              ? _onNextPressed
                              : null,
                          child: const Text(
                            'Next',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),
                    Text(
                      'You must be at least 16 years old to continue.',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                    const SizedBox(height: 18),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  bool _isSelectionAllowed() {
    if (!_hasPicked) return false;
    final selectedYear = years[_selectedIndex];
    final age = currentYear - selectedYear;
    return age >= 16;
  }

  Future<void> _onNextPressed() async {
    final selectedYear = years[_selectedIndex];
    final age = currentYear - selectedYear;

    if (age < 16) {
      // This should be prevented by the wheel bounds, but guard anyway
      await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Too young'),
          content: const Text('You must be at least 16 years old to use this app.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    // store locally
    box.write('pending_birth_year', selectedYear);
    box.write('pending_birth_display', '$selectedYear');

    // save to Firestore for signed-in user
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // Not signed in — save locally and go to login
      Get.snackbar('Saved locally', 'Birth year saved locally. Please sign in to persist.');
      // mark step done locally
      box.write('hasCompletedBirth', true);
      // navigate to login or next screen
      Get.offAll(() => const BloodGroupPage());
      return;
    }

    // Write to Users doc (merge)
    try {
      await FirebaseFirestore.instance.collection('Users').doc(user.uid).set({
        // 'birth_year': selectedYear,
        'age': age,
        // 'birth_display': '$selectedYear',
      }, SetOptions(merge: true));

      // mark completion in local storage so your auth flow will recognize it
      box.write('hasCompletedBirth', true);

      // Optionally mark via repository if you added such helper
      try {
        AuthenticationRepository.instance.completeBirth(); // safe if implemented; ignore otherwise
      } catch (_) {}

      // (Optional) send verification and route like your weight flow:

      // Navigate to VerifyMail (mirrors weight flow behaviour)
      Get.offAll(() => const BloodGroupPage());
    } catch (e) {
      // show error
      Get.snackbar('Save failed', e.toString(), backgroundColor: Colors.red.shade100);
    }
  }
}
