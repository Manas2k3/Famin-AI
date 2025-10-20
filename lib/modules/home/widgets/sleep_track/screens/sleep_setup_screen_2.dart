import 'package:famina/modules/home/widgets/sleep_track/screens/sleep_setup_screen_3.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controller/sleep_controller.dart';
import '../models/sleep_model.dart';
import '../theme/sleep_theme.dart';
import '../widgets/responsive.dart';
import '../widgets/sleep_widget.dart';

class SleepSetupScreen2 extends GetView<SleepController> {
  const SleepSetupScreen2({super.key});

  @override
  Widget build(BuildContext context) {
    final padding = ResponsiveHelper.getScreenPadding(context);
    final spacing = ResponsiveHelper.getSpacing(context);
    final isTablet = ResponsiveHelper.isTablet(context);
    final maxWidth = ResponsiveHelper.getMaxWidth(context);

    final caffeinePerDay = 1.obs;
    final caffeineCutoff = '17:00'.obs;
    final roomTempPref = 'neutral'.obs;
    final lightSensitivity = 3.obs;
    final snoringNoticed = 'unsure'.obs;

    final lifestyle = controller.userData.value?.sleepProfile?.lifestyle;
    if (lifestyle != null) {
      caffeinePerDay.value = lifestyle.caffeinePerDay;
      caffeineCutoff.value = lifestyle.caffeineCutoff;
      roomTempPref.value = lifestyle.roomTempPref;
      lightSensitivity.value = lifestyle.lightSensitivity;
      snoringNoticed.value = lifestyle.snoringNoticed;
    }

    Future<void> selectCaffeineCutoff() async {
      final currentTime = SleepTimeHelper.parseTimeOfDay(caffeineCutoff.value);
      final TimeOfDay? picked = await showTimePicker(
        context: context,
        initialTime: currentTime,
        helpText: 'Last Caffeine Cutoff Time',
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              timePickerTheme: TimePickerThemeData(
                backgroundColor: SleepTheme.surface,
                hourMinuteTextColor: SleepTheme.primaryMid,
                dayPeriodColor: SleepTheme.primaryPale,
                dialBackgroundColor: SleepTheme.primaryPale,
                dialHandColor: Colors.white,
              ),
              textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.indigo,
                  disabledForegroundColor: Colors.indigoAccent.withOpacity(0.38),
                ),
              ),
            ),
            child: child!,
          );
        },
      );

      if (picked != null) {
        caffeineCutoff.value = SleepTimeHelper.formatTimeOfDay(picked);
      }
    }

    Future<void> handleContinue() async {
      final lifestyleData = LifestyleFactors(
        caffeinePerDay: caffeinePerDay.value,
        caffeineCutoff: caffeineCutoff.value,
        roomTempPref: roomTempPref.value,
        lightSensitivity: lightSensitivity.value,
        snoringNoticed: snoringNoticed.value,
      );

      final success = await controller.saveLifestyleFactors(lifestyleData);
      if (success) {
        Get.to(() => const SleepSetupScreen3());
      }
    }

    return Scaffold(
      backgroundColor: SleepTheme.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Get.back(),
        ),
        title: const Text('Sleep Setup'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: SingleChildScrollView(
                padding: padding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SetupProgressIndicator(
                      currentStep: 2,
                      totalSteps: 3,
                    ),
                    SizedBox(height: spacing),

                    Text(
                      'Your daily habits',
                      style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        fontSize: isTablet ? 32 : 28,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Help us personalize your sleep tips',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    SizedBox(height: spacing),

                    const SectionHeader(
                      title: 'Caffeine intake',
                      subtitle: 'Coffee, tea, energy drinks, etc.',
                    ),
                    Obx(() => _CaffeineSelector(
                      value: caffeinePerDay.value,
                      onChanged: (val) => caffeinePerDay.value = val,
                    )),
                    const SizedBox(height: 16),

                    Obx(() => TimePickerButton(
                      label: 'Last caffeine cutoff time',
                      timeValue: caffeineCutoff.value,
                      onTap: selectCaffeineCutoff,
                    )),
                    const SizedBox(height: 8),
                    Text(
                      '💡 Tip: Caffeine stays in your system for 4-6 hours',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: SleepTheme.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    SizedBox(height: spacing),

                    const SectionHeader(
                      title: 'Room temperature preference',
                      subtitle: 'What helps you sleep best?',
                    ),
                    Obx(() => _TemperatureSelector(
                      value: roomTempPref.value,
                      onChanged: (val) => roomTempPref.value = val,
                    )),
                    SizedBox(height: spacing),

                    const SectionHeader(
                      title: 'Light sensitivity',
                      subtitle: 'How sensitive are you to light when sleeping?',
                    ),
                    Obx(() => _LightSensitivitySlider(
                      value: lightSensitivity.value,
                      onChanged: (val) => lightSensitivity.value = val,
                    )),
                    SizedBox(height: spacing),

                    const SectionHeader(
                      title: 'Snoring awareness',
                      subtitle: 'Have you been told you snore?',
                    ),
                    Obx(() => _SnoringSelector(
                      value: snoringNoticed.value,
                      onChanged: (val) => snoringNoticed.value = val,
                    )),
                    const SizedBox(height: 16),
                    Text(
                      '💡 Optional: This helps us suggest breathing exercises',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: SleepTheme.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),

                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ),

          Obx(() {
            if (controller.isLoading.value) {
              return const Positioned.fill(
                child: LoadingOverlay(message: 'Saving preferences...'),
              );
            }
            return const SizedBox.shrink();
          }),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Container(
                  padding: padding,
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
                    child: Obx(() => ElevatedButton(
                      onPressed: !controller.isLoading.value ? handleContinue : null,
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size.fromHeight(isTablet ? 60 : 56),
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Text('Continue'),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward, size: 20),
                        ],
                      ),
                    )),
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

// Custom widgets remain mostly the same but with responsive adjustments

class _CaffeineSelector extends StatelessWidget {
  final int value;
  final Function(int) onChanged;

  const _CaffeineSelector({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isSmall = ResponsiveHelper.isSmallScreen(context);
    final options = [
      {'value': 0, 'label': 'None', 'icon': '🚫'},
      {'value': 1, 'label': '1-2 cups', 'icon': '☕'},
      {'value': 2, 'label': '3-4 cups', 'icon': '☕☕'},
      {'value': 3, 'label': '5+ cups', 'icon': '☕☕☕'},
    ];

    return Wrap(
      spacing: isSmall ? 8 : 12,
      runSpacing: isSmall ? 8 : 12,
      children: options.map((option) {
        final isSelected = value == option['value'];
        return GestureDetector(
          onTap: () => onChanged(option['value'] as int),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(
              horizontal: isSmall ? 14 : 20,
              vertical: isSmall ? 12 : 16,
            ),
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
                  style: TextStyle(fontSize: isSmall ? 20 : 24),
                ),
                const SizedBox(height: 8),
                Text(
                  option['label'] as String,
                  style: TextStyle(
                    color: isSelected ? Colors.white : SleepTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: isSmall ? 12 : 14,
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

class _TemperatureSelector extends StatelessWidget {
  final String value;
  final Function(String) onChanged;

  const _TemperatureSelector({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isSmall = ResponsiveHelper.isSmallScreen(context);
    final options = [
      {'value': 'cool', 'label': 'Cool', 'icon': '❄️', 'desc': '16-18°C'},
      {'value': 'neutral', 'label': 'Neutral', 'icon': '🌡️', 'desc': '18-20°C'},
      {'value': 'warm', 'label': 'Warm', 'icon': '🔥', 'desc': '20-22°C'},
    ];

    return Column(
      children: options.map((option) {
        final isSelected = value == option['value'];
        return GestureDetector(
          onTap: () => onChanged(option['value'] as String),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(bottom: 12),
            padding: EdgeInsets.all(isSmall ? 12 : 16),
            decoration: BoxDecoration(
              color: isSelected ? SleepTheme.primaryMid : SleepTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? SleepTheme.primaryMid : SleepTheme.divider,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: isSmall ? 40 : 48,
                  height: isSmall ? 40 : 48,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withOpacity(0.2)
                        : SleepTheme.primaryPale,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      option['icon'] as String,
                      style: TextStyle(fontSize: isSmall ? 20 : 24),
                    ),
                  ),
                ),
                SizedBox(width: isSmall ? 12 : 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option['label'] as String,
                        style: TextStyle(
                          color: isSelected ? Colors.white : SleepTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: isSmall ? 14 : 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        option['desc'] as String,
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white.withOpacity(0.8)
                              : SleepTheme.textSecondary,
                          fontSize: isSmall ? 11 : 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(
                    Icons.check_circle,
                    color: Colors.white,
                    size: isSmall ? 20 : 24,
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _LightSensitivitySlider extends StatelessWidget {
  final int value;
  final Function(int) onChanged;

  const _LightSensitivitySlider({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isSmall = ResponsiveHelper.isSmallScreen(context);
    final labels = ['Very Low', 'Low', 'Medium', 'High', 'Very High'];

    return Container(
      padding: EdgeInsets.all(isSmall ? 16 : 20),
      decoration: BoxDecoration(
        color: SleepTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SleepTheme.divider),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('🌙', style: TextStyle(fontSize: isSmall ? 20 : 24)),
              Flexible(
                child: Text(
                  labels[value - 1],
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: SleepTheme.primaryMid,
                    fontWeight: FontWeight.w600,
                    fontSize: isSmall ? 14 : 16,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Text('☀️', style: TextStyle(fontSize: isSmall ? 20 : 24)),
            ],
          ),
          const SizedBox(height: 16),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: SleepTheme.primaryMid,
              inactiveTrackColor: SleepTheme.primaryPale,
              thumbColor: SleepTheme.primaryMid,
              overlayColor: SleepTheme.primaryMid.withOpacity(0.2),
              trackHeight: 4,
              thumbShape: RoundSliderThumbShape(
                enabledThumbRadius: isSmall ? 8 : 10,
              ),
            ),
            child: Slider(
              value: value.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              onChanged: (val) => onChanged(val.toInt()),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(5, (index) {
              return Text(
                '${index + 1}',
                style: TextStyle(
                  color: value == index + 1
                      ? SleepTheme.primaryMid
                      : SleepTheme.textTertiary,
                  fontWeight: value == index + 1 ? FontWeight.w600 : FontWeight.w400,
                  fontSize: 12,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _SnoringSelector extends StatelessWidget {
  final String value;
  final Function(String) onChanged;

  const _SnoringSelector({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isSmall = ResponsiveHelper.isSmallScreen(context);
    final options = [
      {'value': 'yes', 'label': 'Yes, I snore', 'icon': '😴'},
      {'value': 'no', 'label': 'No snoring', 'icon': '😌'},
      {'value': 'unsure', 'label': 'Not sure', 'icon': '🤷'},
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Stack vertically on very small screens
        if (constraints.maxWidth < 320) {
          return Column(
            children: options.map((option) {
              final isSelected = value == option['value'];
              return GestureDetector(
                onTap: () => onChanged(option['value'] as String),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: isSelected ? SleepTheme.primaryMid : SleepTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? SleepTheme.primaryMid : SleepTheme.divider,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        option['icon'] as String,
                        style: const TextStyle(fontSize: 24),
                      ),
                      const SizedBox(width: 12),
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

        // Row layout for normal screens
        return Row(
          children: options.map((option) {
            final isSelected = value == option['value'];
            return Expanded(
              child: GestureDetector(
                onTap: () => onChanged(option['value'] as String),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 8),
                  padding: EdgeInsets.symmetric(vertical: isSmall ? 12 : 16),
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
                        style: TextStyle(fontSize: isSmall ? 28 : 32),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        option['label'] as String,
                        style: TextStyle(
                          color: isSelected ? Colors.white : SleepTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: isSmall ? 11 : 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

