import 'package:flutter/material.dart';
import '../models/sleep_model.dart';
import '../theme/sleep_theme.dart';

/// Chronotype Selection Chip
class ChronotypeChip extends StatelessWidget {
  final Chronotype chronotype;
  final bool isSelected;
  final VoidCallback onTap;

  const ChronotypeChip({
    super.key,
    required this.chronotype,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? SleepTheme.primaryMid : SleepTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? SleepTheme.primaryMid : SleepTheme.divider,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected ? SleepTheme.softShadow : null,
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withOpacity(0.2)
                    : SleepTheme.primaryPale,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  chronotype.label.split(' ')[0], // Just the emoji
                  style: const TextStyle(fontSize: 24),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chronotype.label.split(' ').skip(1).join(' '), // Label without emoji
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: isSelected ? Colors.white : SleepTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    chronotype.description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isSelected
                          ? Colors.white.withOpacity(0.8)
                          : SleepTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            // Check mark
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: Colors.white,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }
}

/// Time Picker Button
class TimePickerButton extends StatelessWidget {
  final String label;
  final String timeValue; // "HH:mm" format
  final VoidCallback onTap;

  const TimePickerButton({
    super.key,
    required this.label,
    required this.timeValue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Parse and format time
    final time = SleepTimeHelper.parseTimeOfDay(timeValue);
    final displayTime = time.format(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: SleepTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: SleepTheme.divider),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      label.toLowerCase().contains('bed')
                          ? Icons.bedtime_outlined
                          : Icons.wb_sunny_outlined,
                      color: SleepTheme.primaryMid,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      displayTime,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const Icon(
                  Icons.access_time,
                  color: SleepTheme.textTertiary,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Duration Display Card
class DurationDisplay extends StatelessWidget {
  final int durationMinutes;
  final String? warningMessage;

  const DurationDisplay({
    super.key,
    required this.durationMinutes,
    this.warningMessage,
  });

  @override
  Widget build(BuildContext context) {
    final durationText = SleepTimeHelper.formatDuration(durationMinutes);
    final hasWarning = warningMessage != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hasWarning ? SleepTheme.warning.withOpacity(0.1) : SleepTheme.primaryPale,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasWarning ? SleepTheme.warning : SleepTheme.primaryLight.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasWarning ? Icons.warning_amber_rounded : Icons.bedtime,
            color: hasWarning ? SleepTheme.warning : SleepTheme.primaryMid,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '💤 ',
                      style: const TextStyle(fontSize: 16),
                    ),
                    Text(
                      '$durationText target sleep',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: hasWarning ? SleepTheme.warning : SleepTheme.primaryMid,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (hasWarning) ...[
                  const SizedBox(height: 4),
                  Text(
                    warningMessage!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: SleepTheme.warning,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Personalized Info Card
class PersonalizedInfoCard extends StatelessWidget {
  final UserData userData;

  const PersonalizedInfoCard({
    super.key,
    required this.userData,
  });

  List<String> _generateTips() {
    final tips = <String>[];

    // Age-based tip
    tips.add('Age ${userData.age}: ${userData.sleepRecommendation}');

    // BMI-based tip (gentle)
    if (userData.isUnderweight) {
      tips.add('We\'ll suggest gentler temperature and meal timing tips');
    }

    // Activity-based tip
    if (userData.activity == 'sedentary') {
      tips.add('Light evening walks can help improve sleep onset');
    } else if (userData.activity == 'very_active') {
      tips.add('We\'ll adjust wind-down timing for your active lifestyle');
    }

    return tips;
  }

  @override
  Widget build(BuildContext context) {
    final tips = _generateTips();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            SleepTheme.accentPale,
            SleepTheme.primaryPale,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: SleepTheme.accentLavender.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.lightbulb_outline,
                  color: SleepTheme.accentPurple,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Based on your profile:',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: SleepTheme.primaryDeep,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...tips.map((tip) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('• ', style: TextStyle(fontSize: 16)),
                Expanded(
                  child: Text(
                    tip,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: SleepTheme.textPrimary,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

/// Section Header with optional subtitle
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

/// Progress Indicator for setup flow
class SetupProgressIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const SetupProgressIndicator({
    super.key,
    required this.currentStep,
    required this.totalSteps,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(totalSteps, (index) {
        final isActive = index < currentStep;
        final isCurrent = index == currentStep - 1;

        return Expanded(
          child: Container(
            height: 4,
            margin: EdgeInsets.only(
              right: index < totalSteps - 1 ? 8 : 0,
            ),
            decoration: BoxDecoration(
              color: isActive || isCurrent
                  ? SleepTheme.primaryMid
                  : SleepTheme.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}

/// Loading overlay
class LoadingOverlay extends StatelessWidget {
  final String message;

  const LoadingOverlay({
    super.key,
    this.message = 'Saving...',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(SleepTheme.primaryMid),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom App Bar for setup flow
class SetupAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback? onBackPressed;
  final bool showBackButton;

  const SetupAppBar({
    super.key,
    required this.title,
    this.onBackPressed,
    this.showBackButton = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: showBackButton
          ? IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: onBackPressed ?? () => Navigator.of(context).pop(),
      )
          : null,
      title: Text(title),
      centerTitle: false,
    );
  }
}

/// Snackbar helpers
class SleepSnackBar {
  static void showSuccess(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: SleepTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  static void showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: SleepTheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  static void showInfo(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: SleepTheme.info,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}