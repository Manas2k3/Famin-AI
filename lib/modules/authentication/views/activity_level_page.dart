// file: activity_level_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../../../data/repositories/authentication/authentication_repository.dart';
import 'cycleSelectionPage.dart';

class ActivityLevelPage extends StatefulWidget {
  const ActivityLevelPage({super.key});

  @override
  State<ActivityLevelPage> createState() => _ActivityLevelPageState();
}

class _ActivityLevelPageState extends State<ActivityLevelPage> {
  // UI colors to match your page
  Color get _primary => Colors.pink.shade200;
  Color get _surface => Colors.white;

  final _fire = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _box = GetStorage();

  bool _saving = false;
  int? _selectedIndex;
  final Set<int> _expanded = {};

  /// Options: title + short desc + activity factor
  final List<Map<String, dynamic>> _options = const [
    {
      'title': 'Sedentary',
      'desc': 'Desk job, little to no exercise. Mostly sitting throughout the day.',
      'factor': 1.20,
      'slug': 'sedentary',
    },
    {
      'title': 'Lightly active',
      'desc': 'On your feet sometimes or 1–3 easy workouts/week (walking, light yoga).',
      'factor': 1.375,
      'slug': 'lightly_active',
    },
    {
      'title': 'Moderately active',
      'desc': '3–5 moderate workouts/week (gym, jogging, sports) or active commute.',
      'factor': 1.55,
      'slug': 'moderately_active',
    },
    {
      'title': 'Very active',
      'desc': '6–7 hard workouts/week or a physically demanding job (field, warehouse).',
      'factor': 1.725,
      'slug': 'very_active',
    },
    {
      'title': 'Athlete',
      'desc': 'Intense training twice a day or elite-level schedule/competition prep.',
      'factor': 1.90,
      'slug': 'athlete',
    },
  ];

  bool get _canProceed => _selectedIndex != null && !_saving;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Daily Activity Level',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black54),
          onPressed: () => Get.back(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // subheader
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 12),
              child: Text(
                "Choose the option that best describes your usual day. "
                    "We’ll use this to adjust your calorie target. You can change it anytime.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black87, fontSize: 14),
              ),
            ),
            const SizedBox(height: 8),

            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _options.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = _options[index];
                  final isSelected = _selectedIndex == index;
                  final isExpanded = _expanded.contains(index);

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedIndex = index;
                        if (isExpanded) {
                          _expanded.remove(index);
                        } else {
                          _expanded.add(index);
                        }
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isSelected ? _primary.withOpacity(0.12) : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? _primary : Colors.grey.shade200,
                          width: isSelected ? 1.2 : 1.0,
                        ),
                        boxShadow: isSelected
                            ? [
                          BoxShadow(
                            color: _primary.withOpacity(0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          )
                        ]
                            : null,
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              // custom radio
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? _primary : Colors.grey.shade400,
                                    width: 2,
                                  ),
                                  color: isSelected ? _primary : Colors.white,
                                ),
                                child: isSelected
                                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item['title'] as String,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black87,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              // expansion chevron
                              AnimatedRotation(
                                turns: isExpanded ? 0.5 : 0.0,
                                duration: const Duration(milliseconds: 200),
                                child: const Icon(Icons.expand_more, color: Colors.black54),
                              ),
                            ],
                          ),

                          // expanded description
                          AnimatedCrossFade(
                            firstChild: const SizedBox.shrink(),
                            secondChild: Padding(
                              padding: const EdgeInsets.only(top: 12.0),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  item['desc'] as String,
                                  style: const TextStyle(color: Colors.black87, height: 1.35),
                                ),
                              ),
                            ),
                            crossFadeState:
                            isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                            duration: const Duration(milliseconds: 220),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Next button row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 18),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _canProceed ? _saveSelectionAndProceed : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primary,
                          disabledBackgroundColor: _primary.withOpacity(0.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: _saving
                            ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white,
                          ),
                        )
                            : const Text('Next', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveSelectionAndProceed() async {
    final idx = _selectedIndex;
    if (idx == null) return;

    setState(() => _saving = true);

    final item = _options[idx];
    final String title = item['title'] as String;
    final String slug = item['slug'] as String;
    final double factor = (item['factor'] as num).toDouble();

    final user = _auth.currentUser;

    try {
      if (user != null) {
        await _fire.collection('Users').doc(user.uid).set({
          'profile': {
            'activity': slug, // e.g., "sedentary"
            'activity_label': title, // human-readable
            'activity_factor': factor, // e.g., 1.2
            'activity_last_updated': DateTime.now().toIso8601String(),
          }
        }, SetOptions(merge: true));
      }

      // local flags (so your onboarding flow can branch)
      _box.write('activityLevel', slug);
      _box.write('hasCompletedActivity', true);

      // optional repo hook (ignore if not implemented)
      try {
        AuthenticationRepository.instance.completeActivityStep();
      } catch (_) {}

      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;

      // proceed to next step (mirroring your sample)
      Get.to(() => const CycleSelectionPage());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save your activity: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
