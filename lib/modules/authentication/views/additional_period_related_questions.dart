// lib/modules/authentication/views/period_questions_pages.dar

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import 'health_conditions_page.dart'; // adjust import path if your project differs

// Helper: common scaffold to keep UI consistent
class _QuestionScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final VoidCallback? onNext;
  final bool nextEnabled;

  const _QuestionScaffold({
    Key? key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.onNext,
    this.nextEnabled = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.pink.shade200,
        elevation: 0,
        centerTitle: true,
        title: Text(title, style: const TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black87),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(14),
                ),
                child: child,
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.pink.shade200,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                  ),
                  onPressed: nextEnabled ? onNext : null,
                  child: const Text('Next', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

// ========== 1) Blood Group Page ==========
class BloodGroupPage extends StatefulWidget {
  const BloodGroupPage({Key? key}) : super(key: key);

  @override
  State<BloodGroupPage> createState() => _BloodGroupPageState();
}

class _BloodGroupPageState extends State<BloodGroupPage> {
  final box = GetStorage();
  String? selected; // null => optional

  final List<String> groups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

  Future<void> _saveAndNext() async {
    box.write('blood_group', selected ?? '');

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance.collection('Users').doc(user.uid).set({
          'blood_group': selected ?? '',
        }, SetOptions(merge: true));
      } catch (e) {
        Get.snackbar('Save failed', e.toString(), backgroundColor: Colors.red.shade50);
      }
    }

    Get.to(() => const CycleRegularityPage());
  }

  @override
  Widget build(BuildContext context) {
    return _QuestionScaffold(
      title: 'Do you know your blood group?',
      subtitle: 'This is optional but helps for medical context in future features.',
      onNext: _saveAndNext,
      nextEnabled: true,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final g in groups)
            ChoiceChip(
              label: Text(g, style: const TextStyle(fontWeight: FontWeight.w600)),
              selected: selected == g,
              onSelected: (v) => setState(() => selected = v ? g : null),
              selectedColor: Colors.pink.shade200.withOpacity(0.95),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 2,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          // Clear selection chip
          ActionChip(
            label: const Text('Prefer not to say'),
            onPressed: () => setState(() => selected = null),
            backgroundColor: Colors.white,
            elevation: 0,
          ),
        ],
      ), // optional so always enabled
    );
  }
}

// ========== 2) Cycle Regularity Page ==========
class CycleRegularityPage extends StatefulWidget {
  const CycleRegularityPage({Key? key}) : super(key: key);

  @override
  State<CycleRegularityPage> createState() => _CycleRegularityPageState();
}

class _CycleRegularityPageState extends State<CycleRegularityPage> {
  final box = GetStorage();
  String? selected; // 'Regular' or 'Irregular'

  Future<void> _saveAndNext() async {
    if (selected == null) return; // guard, but UI enables Next only when chosen
    box.write('cycle_regular', selected);

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance.collection('Users').doc(user.uid).set({
          'cycle_regular': selected == 'Regular',
        }, SetOptions(merge: true));
      } catch (e) {
        Get.snackbar('Save failed', e.toString(), backgroundColor: Colors.red.shade50);
      }
    }

    Get.to(() => const PeriodDurationPage());
  }

  @override
  Widget build(BuildContext context) {
    return _QuestionScaffold(
      title: 'Are your cycles usually regular or irregular?',
      subtitle: 'Choose the option that best describes your menstrual cycle rhythm.',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _RegularityButton(label: 'Regular', selected: selected == 'Regular', onTap: () => setState(() => selected = 'Regular')),
          _RegularityButton(label: 'Irregular', selected: selected == 'Irregular', onTap: () => setState(() => selected = 'Irregular')),
        ],
      ),
      onNext: _saveAndNext,
      nextEnabled: selected != null,
    );
  }
}

class _RegularityButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _RegularityButton({required this.label, required this.selected, required this.onTap, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        height: 100,
        decoration: BoxDecoration(
          color: selected ? Colors.pink.shade200 : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 3)),
          ],
          border: Border.all(color: selected ? Colors.pink.shade300 : Colors.grey.shade200),
        ),
        child: Center(
          child: Text(label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: selected ? Colors.white : Colors.black87)),
        ),
      ),
    );
  }
}

// ========== 3) Period Duration Page ==========
class PeriodDurationPage extends StatefulWidget {
  const PeriodDurationPage({Key? key}) : super(key: key);

  @override
  State<PeriodDurationPage> createState() => _PeriodDurationPageState();
}

class _PeriodDurationPageState extends State<PeriodDurationPage> {
  final box = GetStorage();
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _controller = TextEditingController();

  Future<void> _saveAndNext() async {
    if (!_formKey.currentState!.validate()) return;
    final value = int.tryParse(_controller.text.trim()) ?? 0;
    box.write('period_duration_days', value);

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance.collection('Users').doc(user.uid).set({
          'period_duration_days': value,
        }, SetOptions(merge: true));
      } catch (e) {
        Get.snackbar('Save failed', e.toString(), backgroundColor: Colors.red.shade50);
      }
    }

    Get.to(() => const AverageCycleLengthPage());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _QuestionScaffold(
      title: 'How many days does your period usually last?',
      subtitle: 'Enter the typical number of days your period lasts (e.g., 5).',
      child: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            hintText: 'Number of days',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          validator: (v) {
            final n = int.tryParse(v ?? '');
            if (n == null || n <= 0 || n > 30) return 'Enter a valid number between 1 and 30';
            return null;
          },
        ),
      ),
      onNext: _saveAndNext,
      nextEnabled: true,
    );
  }
}

// ========== 4) Average Cycle Length Page ==========
class AverageCycleLengthPage extends StatefulWidget {
  const AverageCycleLengthPage({Key? key}) : super(key: key);

  @override
  State<AverageCycleLengthPage> createState() => _AverageCycleLengthPageState();
}

class _AverageCycleLengthPageState extends State<AverageCycleLengthPage> {
  final box = GetStorage();
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _controller = TextEditingController();

  Future<void> _saveAndFinish() async {
    if (_controller.text.trim().isNotEmpty) {
      if (!_formKey.currentState!.validate()) return;
    }

    final value = _controller.text.trim().isEmpty ? null : int.tryParse(_controller.text.trim());
    box.write('avg_cycle_length_days', value ?? '');

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance.collection('Users').doc(user.uid).set({
          'avg_cycle_length_days': value ?? '',
        }, SetOptions(merge: true));
      } catch (e) {
        Get.snackbar('Save failed', e.toString(), backgroundColor: Colors.red.shade50);
      }
    }

    // Mark flow complete locally if you want
    box.write('hasCompletedPeriodQuestions', true);

    // Navigate to HealthConditionsPage
    Get.offAll(() => const HealthConditionsPage());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _QuestionScaffold(
      title: 'Average cycle length (optional)',
      subtitle: 'Enter the average number of days between the start of two periods (e.g., 28). Leave blank if unknown.',
      onNext: _saveAndFinish,
      nextEnabled: true,
      child: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            hintText: 'e.g., 28 days (optional)',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return null;
            final n = int.tryParse(v);
            if (n == null || n < 18 || n > 90) return 'Enter a realistic cycle length (18 - 90)';
            return null;
          },
        ),
      ),
    );
  }
}

// ==================== End of file ====================
