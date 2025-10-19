import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controller/sleep_controller.dart';
import '../models/sleep_model.dart';
import '../theme/sleep_theme.dart';
import '../widgets/sleep_widget.dart';
import 'sleep_dashboard.dart';

class MorningCheckInScreen extends GetView<SleepController> {
  const MorningCheckInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Local state for check-in
    final sleepQuality = 3.obs;       // 1–5
    final awakeningsCount = 0.obs;    // 0,1,2(=2-3 times),3(=4+)
    final sleepLatency = 10.obs;      // minutes (5,10,20,40)
    final wakeReasons = <String>[].obs;
    final notes = ''.obs;

    final inBedTime = Rx<TimeOfDay?>(null);
    final wakeTime = Rx<TimeOfDay?>(null);

    // Prefill times from profile (bed) + current time (wake)
    final profile = controller.userData.value?.sleepProfile;
    if (profile != null && inBedTime.value == null) {
      inBedTime.value = SleepTimeHelper.parseTimeOfDay(profile.targetBedtime);
      wakeTime.value = TimeOfDay.now();
    }

    Future<void> selectInBedTime() async {
      final picked = await showTimePicker(
        context: context,
        initialTime: inBedTime.value ?? const TimeOfDay(hour: 23, minute: 0),
        helpText: 'What time did you get in bed?',
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              timePickerTheme: const TimePickerThemeData(
                backgroundColor: SleepTheme.surface,
                hourMinuteTextColor: SleepTheme.primaryMid,
                dayPeriodColor: SleepTheme.primaryPale,
                dialBackgroundColor: SleepTheme.primaryPale,
                dialHandColor: Colors.white,
              ),
              textButtonTheme: const TextButtonThemeData(
                style: ButtonStyle(
                  foregroundColor: WidgetStatePropertyAll(Colors.indigo),
                ),
              ),
            ),
            child: child!,
          );
        },
      );
      if (picked != null) inBedTime.value = picked;
    }

    Future<void> selectWakeTime() async {
      final picked = await showTimePicker(
        context: context,
        initialTime: wakeTime.value ?? TimeOfDay.now(),
        helpText: 'What time did you wake up?',
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              timePickerTheme: const TimePickerThemeData(
                backgroundColor: SleepTheme.surface,
                hourMinuteTextColor: SleepTheme.primaryMid,
                dayPeriodColor: SleepTheme.primaryPale,
                dialBackgroundColor: SleepTheme.primaryPale,
                dialHandColor: Colors.white,
              ),
              textButtonTheme: const TextButtonThemeData(
                style: ButtonStyle(
                  foregroundColor: WidgetStatePropertyAll(Colors.indigo),
                ),
              ),
            ),
            child: child!,
          );
        },
      );
      if (picked != null) wakeTime.value = picked;
    }

    Future<void> handleSave() async {
      // Validation
      if (inBedTime.value == null || wakeTime.value == null) {
        Get.snackbar(
          'Missing Times',
          'Please enter when you went to bed and woke up',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: SleepTheme.warning.withOpacity(0.2),
          colorText: SleepTheme.textPrimary,
        );
        return;
      }

      // Format times as HH:mm strings
      final bedtimeStr = SleepTimeHelper.formatTimeOfDay(inBedTime.value!);
      final wakeStr = SleepTimeHelper.formatTimeOfDay(wakeTime.value!);

      // Calculate duration (bed to wake)
      final durationMinutes =
      SleepTimeHelper.calculateDurationMinutes(bedtimeStr, wakeStr);

      // Estimate total sleep time (subtract latency + rough penalty for wakes)
      final awakenPenalty = switch (awakeningsCount.value) {
        0 => 0,
        1 => 10,
        2 => 20, // "2–3 times"
        _ => 30, // "4+"
      };

      final estimatedSleep =
      (durationMinutes - sleepLatency.value - awakenPenalty)
          .clamp(0, 24 * 60);

      // Build log
      final now = DateTime.now();
      final log = SleepLog(
        date: now,
        bedtimeHHmm: bedtimeStr,
        wakeHHmm: wakeStr,
        durationMinutes: durationMinutes,
        totalSleepMinutes: estimatedSleep,
        quality: sleepQuality.value,
        awakenings: awakeningsCount.value,
        sleepLatencyMinutes: sleepLatency.value,
        notes: notes.value.isEmpty ? null : notes.value.trim(),
        wakeReasons: wakeReasons.isEmpty ? null : wakeReasons.toList(),
      );

      // Save
      final success = await controller.saveSleepLog(log);
      if (success) {
        Get.off(() => const SleepDashboardScreen());
      }
    }

    return Scaffold(
      backgroundColor: SleepTheme.background,
      appBar: AppBar(
        title: const Text('Morning Check-In'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Greeting
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        SleepTheme.primaryPale,
                        SleepTheme.accentPale,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Text('🌅', style: TextStyle(fontSize: 48)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Good morning!',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'How did you sleep last night?',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // 1) Sleep times
                const _SectionTitle(title: 'Sleep times', number: '1'),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Obx(
                            () => _TimeCard(
                          label: 'In bed',
                          icon: Icons.bedtime,
                          time: inBedTime.value,
                          onTap: selectInBedTime,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Obx(
                            () => _TimeCard(
                          label: 'Woke up',
                          icon: Icons.wb_sunny,
                          time: wakeTime.value,
                          onTap: selectWakeTime,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // 2) Sleep quality
                const _SectionTitle(
                  title: 'How was your sleep quality?',
                  number: '2',
                ),
                const SizedBox(height: 16),
                Obx(
                      () => _QualitySelector(
                    value: sleepQuality.value,
                    onChanged: (val) => sleepQuality.value = val,
                  ),
                ),
                const SizedBox(height: 32),

                // 3) Awakenings
                const _SectionTitle(
                  title: 'Did you wake up during the night?',
                  number: '3',
                ),
                const SizedBox(height: 16),
                Obx(
                      () => _AwakeningsSelector(
                    value: awakeningsCount.value,
                    onChanged: (val) => awakeningsCount.value = val,
                  ),
                ),
                const SizedBox(height: 32),

                // 4) Wake reasons (conditional)
                Obx(() {
                  if (awakeningsCount.value > 0) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SectionTitle(
                          title: 'Why did you wake up?',
                          number: '4',
                        ),
                        const SizedBox(height: 16),
                        _WakeReasonsSelector(
                          selected: wakeReasons,
                          onChanged: (reasons) => wakeReasons.value = reasons,
                        ),
                        const SizedBox(height: 32),
                      ],
                    );
                  }
                  return const SizedBox.shrink();
                }),

                // 5) Sleep latency
                _SectionTitle(
                  title: 'How long to fall asleep?',
                  number: awakeningsCount.value > 0 ? '5' : '4',
                ),
                const SizedBox(height: 16),
                Obx(
                      () => _LatencySelector(
                    value: sleepLatency.value,
                    onChanged: (val) => sleepLatency.value = val,
                  ),
                ),
                const SizedBox(height: 32),

                // 6) Notes (optional)
                _SectionTitle(
                  title: 'Add a note (optional)',
                  number: awakeningsCount.value > 0 ? '6' : '5',
                ),
                const SizedBox(height: 16),
                TextField(
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'e.g., Felt tired, had vivid dreams...',
                    filled: true,
                    fillColor: SleepTheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (val) => notes.value = val,
                ),

                const SizedBox(height: 100), // Space for button
              ],
            ),
          ),

          // Loading overlay
          Obx(() {
            if (controller.isLoading.value) {
              return const Positioned.fill(
                child: LoadingOverlay(message: 'Saving sleep data...'),
              );
            }
            return const SizedBox.shrink();
          }),

          // Bottom button
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: SleepTheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: ElevatedButton(
                  onPressed: () async => handleSave(),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: SleepTheme.divider,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Text(
                        'Save Sleep Log',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.check_circle, size: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ======== Custom widgets ========

class _SectionTitle extends StatelessWidget {
  final String title;
  final String number;

  const _SectionTitle({required this.title, required this.number});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: SleepTheme.primaryMid,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: SleepTheme.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _TimeCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final TimeOfDay? time;
  final VoidCallback onTap;

  const _TimeCard({
    required this.label,
    required this.icon,
    required this.time,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: SleepTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: time != null ? SleepTheme.primaryMid : SleepTheme.divider,
            width: time != null ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color:
              time != null ? SleepTheme.primaryMid : SleepTheme.textTertiary,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: SleepTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              time?.format(context) ?? '--:--',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color:
                time != null ? SleepTheme.primaryMid : SleepTheme.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QualitySelector extends StatelessWidget {
  final int value;
  final Function(int) onChanged;

  const _QualitySelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final emojis = ['😩', '😞', '😐', '😊', '😄'];
    final labels = ['Very Bad', 'Bad', 'Okay', 'Good', 'Great'];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: SleepTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SleepTheme.divider),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(5, (index) {
              final quality = index + 1;
              final isSelected = value == quality;
              return GestureDetector(
                onTap: () => onChanged(quality),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? SleepTheme.primaryMid.withOpacity(0.1)
                        : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? SleepTheme.primaryMid
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Text(
                    emojis[index],
                    style: TextStyle(
                      fontSize: isSelected ? 36 : 28,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          Text(
            labels[value - 1],
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: SleepTheme.primaryMid,
            ),
          ),
        ],
      ),
    );
  }
}

class _AwakeningsSelector extends StatelessWidget {
  final int value;
  final Function(int) onChanged;

  const _AwakeningsSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final options = [
      {'value': 0, 'label': 'No wakes', 'icon': '😌'},
      {'value': 1, 'label': 'Once', 'icon': '😪'},
      {'value': 2, 'label': '2-3 times', 'icon': '😫'},
      {'value': 3, 'label': '4+ times', 'icon': '😵'},
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: options.map((option) {
        final optionValue = option['value'] as int;
        final isSelected = value == optionValue;
        return GestureDetector(
          onTap: () => onChanged(optionValue),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: isSelected ? SleepTheme.primaryMid : SleepTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? SleepTheme.primaryMid : SleepTheme.divider,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Text(
                  option['icon'] as String,
                  style: const TextStyle(fontSize: 28),
                ),
                const SizedBox(height: 8),
                Text(
                  option['label'] as String,
                  style: TextStyle(
                    color: isSelected ? Colors.white : SleepTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _WakeReasonsSelector extends StatelessWidget {
  final RxList<String> selected;
  final Function(List<String>) onChanged;

  const _WakeReasonsSelector({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final reasons = [
      {'value': 'noise', 'label': 'Noise', 'icon': '🔊'},
      {'value': 'bathroom', 'label': 'Bathroom', 'icon': '🚽'},
      {'value': 'pain', 'label': 'Pain/Cramps', 'icon': '🤕'},
      {'value': 'stress', 'label': 'Stress/Dreams', 'icon': '😰'},
      {'value': 'hot', 'label': 'Too Hot', 'icon': '🔥'},
      {'value': 'cold', 'label': 'Too Cold', 'icon': '❄️'},
      {'value': 'unknown', 'label': 'Unknown', 'icon': '🤷'},
    ];

    return Obx(
          () => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: reasons.map((reason) {
          final value = reason['value'] as String;
          final isSelected = selected.contains(value);
          return GestureDetector(
            onTap: () {
              if (isSelected) {
                selected.remove(value);
              } else {
                selected.add(value);
              }
              onChanged(selected.toList());
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? SleepTheme.accentPurple : SleepTheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? SleepTheme.accentPurple : SleepTheme.divider,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    reason['icon'] as String,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    reason['label'] as String,
                    style: TextStyle(
                      color: isSelected ? Colors.white : SleepTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _LatencySelector extends StatelessWidget {
  final int value;
  final Function(int) onChanged;

  const _LatencySelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final options = [
      {'value': 5, 'label': '< 5 min'},
      {'value': 10, 'label': '5-15 min'},
      {'value': 20, 'label': '15-30 min'},
      {'value': 40, 'label': '30+ min'},
    ];

    return Row(
      children: options.map((option) {
        final optionValue = option['value'] as int;
        final isSelected = value == optionValue;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onChanged(optionValue),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSelected ? SleepTheme.primaryMid : SleepTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? SleepTheme.primaryMid : SleepTheme.divider,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Text(
                  option['label'] as String,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isSelected ? Colors.white : SleepTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
