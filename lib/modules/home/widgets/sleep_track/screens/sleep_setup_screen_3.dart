import 'package:famina/modules/home/widgets/sleep_track/screens/sleep_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controller/sleep_controller.dart';
import '../models/sleep_model.dart';
import '../theme/sleep_theme.dart';
import '../widgets/responsive.dart';
import '../widgets/sleep_widget.dart';

class SleepSetupScreen3 extends GetView<SleepController> {
  const SleepSetupScreen3({super.key});

  @override
  Widget build(BuildContext context) {
    final padding = ResponsiveHelper.getScreenPadding(context);
    final spacing = ResponsiveHelper.getSpacing(context);
    final isTablet = ResponsiveHelper.isTablet(context);
    final maxWidth = ResponsiveHelper.getMaxWidth(context);

    final autoStartEnabled = true.obs;
    final motionDetectionEnabled = false.obs;
    final noiseDetectionEnabled = false.obs;

    final settings = controller.userData.value?.sleepProfile?.trackingSettings;
    if (settings != null) {
      autoStartEnabled.value = settings.autoStartEnabled;
      motionDetectionEnabled.value = settings.motionDetectionEnabled;
      noiseDetectionEnabled.value = settings.noiseDetectionEnabled;
    }

    Future<void> handleComplete() async {
      final trackingSettings = TrackingSettings(
        autoStartEnabled: autoStartEnabled.value,
        motionDetectionEnabled: motionDetectionEnabled.value,
        noiseDetectionEnabled: noiseDetectionEnabled.value,
      );

      final success = await controller.saveTrackingSettings(trackingSettings);
      if (success) {
        await controller.completeSetup();
        Get.offAll(() => const SleepDashboardScreen());
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
                      currentStep: 3,
                      totalSteps: 3,
                    ),
                    SizedBox(height: spacing),

                    Text(
                      'How should we track\nyour sleep?',
                      style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        fontSize: isTablet ? 32 : 28,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'All features are optional and privacy-focused',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    SizedBox(height: spacing),

                    Container(
                      padding: EdgeInsets.all(isTablet ? 20 : 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            SleepTheme.success.withOpacity(0.1),
                            SleepTheme.info.withOpacity(0.1),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: SleepTheme.success.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.security,
                            color: SleepTheme.success,
                            size: isTablet ? 28 : 24,
                          ),
                          SizedBox(width: isTablet ? 16 : 12),
                          Expanded(
                            child: Text(
                              'Your privacy is our priority. All data stays on your device.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: SleepTheme.textPrimary,
                                fontWeight: FontWeight.w500,
                                fontSize: isTablet ? 14 : 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: spacing),

                    Obx(() => _PermissionCard(
                      icon: Icons.bedtime,
                      iconColor: SleepTheme.primaryMid,
                      title: 'Auto-start tracking',
                      description: 'Automatically detect when you\'re in bed',
                      details:
                      'Uses phone charging status and screen-off time to detect bedtime',
                      isEnabled: autoStartEnabled.value,
                      onChanged: (val) => autoStartEnabled.value = val,
                      recommended: true,
                    )),
                    const SizedBox(height: 16),

                    Obx(() => _PermissionCard(
                      icon: Icons.directions_walk,
                      iconColor: SleepTheme.accentPurple,
                      title: 'Motion detection',
                      description: 'Estimate sleep phases and awakenings',
                      details:
                      'Low-power mode uses <1% battery. Helps identify restless nights.',
                      isEnabled: motionDetectionEnabled.value,
                      onChanged: (val) => motionDetectionEnabled.value = val,
                      batteryImpact: 'Low',
                    )),
                    const SizedBox(height: 16),

                    Obx(() => _PermissionCard(
                      icon: Icons.graphic_eq,
                      iconColor: SleepTheme.info,
                      title: 'Noise detection',
                      description: 'Track disturbances without recording',
                      details:
                      'Only logs event counts and durations—never stores audio.',
                      isEnabled: noiseDetectionEnabled.value,
                      onChanged: (val) => noiseDetectionEnabled.value = val,
                      batteryImpact: 'Medium',
                      privacyNote: 'No audio is ever recorded or stored',
                    )),
                    SizedBox(height: spacing),

                    GestureDetector(
                      onTap: () {
                        _showPrivacyDialog(context);
                      },
                      child: Container(
                        padding: EdgeInsets.all(isTablet ? 20 : 16),
                        decoration: BoxDecoration(
                          color: SleepTheme.primaryPale,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.privacy_tip_outlined,
                              color: SleepTheme.primaryMid,
                              size: isTablet ? 24 : 20,
                            ),
                            SizedBox(width: isTablet ? 16 : 12),
                            Expanded(
                              child: Text(
                                'How we protect your privacy',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: SleepTheme.primaryMid,
                                  fontWeight: FontWeight.w600,
                                  fontSize: isTablet ? 16 : 14,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios,
                              color: SleepTheme.primaryMid,
                              size: isTablet ? 18 : 16,
                            ),
                          ],
                        ),
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
                child: LoadingOverlay(message: 'Completing setup...'),
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
                      onPressed: !controller.isLoading.value ? handleComplete : null,
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
                          Text('Complete Setup'),
                          SizedBox(width: 8),
                          Icon(Icons.check, size: 20),
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

  void _showPrivacyDialog(BuildContext context) {
    final isTablet = ResponsiveHelper.isTablet(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.security,
              color: SleepTheme.success,
              size: isTablet ? 28 : 24,
            ),
            SizedBox(width: isTablet ? 16 : 12),
            const Text('Privacy & Data'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: const [
              _PrivacyPoint(
                icon: Icons.phone_android,
                text: 'All sleep data is stored locally on your device',
              ),
              _PrivacyPoint(
                icon: Icons.cloud_off,
                text: 'Only anonymous summaries sync to your account',
              ),
              _PrivacyPoint(
                icon: Icons.mic_off,
                text: 'No audio is ever recorded or stored',
              ),
              _PrivacyPoint(
                icon: Icons.delete_outline,
                text: 'You can delete all data anytime in Settings',
              ),
              _PrivacyPoint(
                icon: Icons.file_download,
                text: 'Export your data as CSV or JSON',
              ),
              SizedBox(height: 16),
              Text(
                'We follow industry best practices to protect your sensitive health data.',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

// Custom widgets for Screen 3

class _PermissionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final String details;
  final bool isEnabled;
  final Function(bool) onChanged;
  final bool recommended;
  final String? batteryImpact;
  final String? privacyNote;

  const _PermissionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.details,
    required this.isEnabled,
    required this.onChanged,
    this.recommended = false,
    this.batteryImpact,
    this.privacyNote,
  });

  @override
  Widget build(BuildContext context) {
    final isSmall = ResponsiveHelper.isSmallScreen(context);
    final isTablet = ResponsiveHelper.isTablet(context);

    return Container(
      padding: EdgeInsets.all(isTablet ? 24 : (isSmall ? 16 : 20)),
      decoration: BoxDecoration(
        color: SleepTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEnabled ? iconColor.withOpacity(0.3) : SleepTheme.divider,
          width: isEnabled ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(isTablet ? 12 : 10),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: isTablet ? 28 : 24,
                ),
              ),
              SizedBox(width: isTablet ? 20 : 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: isTablet ? 18 : (isSmall ? 14 : 16),
                            ),
                          ),
                        ),
                        if (recommended) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: SleepTheme.success.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Recommended',
                              style: TextStyle(
                                color: SleepTheme.success,
                                fontWeight: FontWeight.w600,
                                fontSize: isSmall ? 8 : 9,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: isTablet ? 14 : (isSmall ? 11 : 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Transform.scale(
                scale: isTablet ? 1.1 : 1.0,
                child: Switch(
                  value: isEnabled,
                  onChanged: onChanged,
                  activeColor: iconColor,
                ),
              ),
            ],
          ),
          SizedBox(height: isTablet ? 16 : 12),
          Text(
            details,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: SleepTheme.textSecondary,
              height: 1.5,
              fontSize: isTablet ? 14 : (isSmall ? 11 : 12),
            ),
          ),
          if (batteryImpact != null || privacyNote != null) ...[
            SizedBox(height: isTablet ? 16 : 12),
            Wrap(
              spacing: isTablet ? 16 : 12,
              runSpacing: 8,
              children: [
                if (batteryImpact != null)
                  _InfoChip(
                    icon: Icons.battery_charging_full,
                    label: '$batteryImpact battery',
                    color: batteryImpact == 'Low'
                        ? SleepTheme.success
                        : SleepTheme.warning,
                  ),
                if (privacyNote != null)
                  _InfoChip(
                    icon: Icons.lock_outline,
                    label: privacyNote!,
                    color: SleepTheme.info,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isSmall = ResponsiveHelper.isSmallScreen(context);
    final isTablet = ResponsiveHelper.isTablet(context);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 12 : 10,
        vertical: isTablet ? 8 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: isTablet ? 16 : 14,
            color: color,
          ),
          SizedBox(width: isTablet ? 8 : 6),
          Text(
            label,
            style: TextStyle(
              fontSize: isTablet ? 13 : (isSmall ? 10 : 11),
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyPoint extends StatelessWidget {
  final IconData icon;
  final String text;

  const _PrivacyPoint({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final isTablet = ResponsiveHelper.isTablet(context);

    return Padding(
      padding: EdgeInsets.only(bottom: isTablet ? 16 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: isTablet ? 24 : 20,
            color: SleepTheme.success,
          ),
          SizedBox(width: isTablet ? 16 : 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: isTablet ? 15 : 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}