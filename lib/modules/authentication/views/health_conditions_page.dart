// file: health_conditions_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import '../../../data/repositories/authentication/authentication_repository.dart';
import 'activity_level_page.dart';
import 'cycleSelectionPage.dart';

class HealthConditionsPage extends StatefulWidget {
  const HealthConditionsPage({super.key});

  @override
  State<HealthConditionsPage> createState() => _HealthConditionsPageState();
}

class _HealthConditionsPageState extends State<HealthConditionsPage> {
  // options and descriptions
  final List<Map<String, String>> _options = [
    {
      'title': 'Yeast infection',
      'desc':
      'Common fungal infection causing itching, irritation and discharge. If you suspect this, consider visiting a clinician.',
    },
    {
      'title': 'Urinary tract infection (UTI)',
      'desc':
      'Infections of the urinary tract that can cause burning sensation during urination, frequent urination and discomfort.',
    },
    {
      'title': 'PCOS (Polycystic Ovary Syndrome)',
      'desc':
      'A hormonal condition that can affect periods, weight, and fertility. If you suspect PCOS, diagnostic tests are required.',
    },
    {
      'title': 'Endometriosis',
      'desc':
      'A condition where tissue similar to the lining of the uterus grows outside it and can cause painful periods and other symptoms.',
    },
    {
      'title': 'None of the above',
      'desc': 'No relevant gynecological conditions to report.',
    },
    {
      'title': 'Other',
      'desc': 'Any other condition not listed here (specify here below please).',
    },
  ];

  int? _selectedIndex;
  // which tiles are open (expand)
  final Set<int> _expanded = {};

  final _fire = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _box = GetStorage();

  bool _saving = false;

  // controller for "Other" input
  final TextEditingController _otherController = TextEditingController();
  final FocusNode _otherFocus = FocusNode();

  // UI colors
  Color get _primary => Colors.pink.shade200;
  Color get _surface => Colors.white;

  @override
  void dispose() {
    _otherController.dispose();
    _otherFocus.dispose();
    super.dispose();
  }

  bool get _isOtherSelected {
    if (_selectedIndex == null) return false;
    return (_options[_selectedIndex!]['title'] ?? '') == 'Other';
  }

  bool get _canProceed {
    if (_selectedIndex == null) return false;
    if (_isOtherSelected) {
      return _otherController.text.trim().isNotEmpty && !_saving;
    }
    return !_saving;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Any health conditions?',
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
            // optional subheader
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12),
              child: Text(
                "Do you currently have any of the following conditions that affect the vagina or cycle? Tap an item to read more.",
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
                      // Tapping selects
                      setState(() {
                        _selectedIndex = index;
                        // toggle expansion as well
                        if (isExpanded) {
                          _expanded.remove(index);
                        } else {
                          _expanded.add(index);
                        }

                        // if 'Other' selected, request focus to its field
                        if ((_options[index]['title'] ?? '') == 'Other') {
                          // small delay to allow rebuild
                          Future.delayed(const Duration(milliseconds: 150), () {
                            if (mounted) _otherFocus.requestFocus();
                          });
                        } else {
                          // clear other input when switching away (optional)
                          // _otherController.clear();
                          _otherFocus.unfocus();
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
                                  item['title'] ?? '',
                                  style: TextStyle(
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
                                child: Icon(Icons.expand_more, color: Colors.black54),
                              ),
                            ],
                          ),

                          // expanded description
                          AnimatedCrossFade(
                            firstChild: const SizedBox.shrink(),
                            secondChild: Padding(
                              padding: const EdgeInsets.only(top: 12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      item['desc'] ?? '',
                                      style: const TextStyle(color: Colors.black87, height: 1.35),
                                    ),
                                  ),
                                  // If this is the 'Other' tile and it's expanded, show the textfield
                                  if ((_options[index]['title'] ?? '') == 'Other')
                                    Padding(
                                      padding: const EdgeInsets.only(top: 12.0),
                                      child: TextField(
                                        controller: _otherController,
                                        focusNode: _otherFocus,
                                        textInputAction: TextInputAction.done,
                                        onChanged: (_) {
                                          // update Next button state
                                          setState(() {});
                                        },
                                        decoration: InputDecoration(
                                          hintText: 'Type your health condition here',
                                          // remove floating label behavior by not using a label at all
                                          contentPadding:
                                          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(10),
                                            borderSide: BorderSide(color: Colors.grey.shade300),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(10),
                                            borderSide: BorderSide(color: _primary),
                                          ),
                                          // no labelText, no floating label — just a hint (as requested)
                                        ),
                                      ),
                                    ),
                                ],
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
                        onPressed: _canProceed
                            ? () async {
                          await _saveSelectionAndProceed();
                        }
                            : null,
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
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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

    final selectedTitle = _options[idx]['title'] ?? 'Other';
    String selectedDesc = _options[idx]['desc'] ?? '';

    // if Other, override desc with user-provided note (but keep original desc available in case)
    final isOther = selectedTitle == 'Other';
    final otherText = _otherController.text.trim();

    if (isOther) {
      selectedDesc = otherText.isNotEmpty ? otherText : selectedDesc;
    }

    final user = _auth.currentUser;
    try {
      // Save to Firestore if user is signed in
      if (user != null) {
        await _fire.collection('Users').doc(user.uid).set({
          'health_conditions': {
            // keep selected as 'Other' so it's clear it's a custom entry
            'selected': selectedTitle,
            // store the user's typed note (or the original desc for non-Other)
            'note': selectedDesc,
            'updated_at': DateTime.now().toIso8601String(),
          }
        }, SetOptions(merge: true));
      }

      // Mark locally (so your AuthenticationRepository can read this flag)
      _box.write('hasCompletedHealthConditions', true);

      // also call AuthenticationRepository helper if available
      try {
        AuthenticationRepository.instance.completeHealthConditions();
      } catch (_) {
        // ignore if method not present
      }

      // proceed to cycle selection
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      Get.to(() => const ActivityLevelPage());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save your answer: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
