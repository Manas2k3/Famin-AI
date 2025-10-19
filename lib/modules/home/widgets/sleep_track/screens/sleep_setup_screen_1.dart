import 'package:famina/modules/home/widgets/sleep_track/screens/sleep_setup_screen_2.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controller/sleep_controller.dart';
import '../models/sleep_model.dart';
import '../theme/sleep_theme.dart';
import '../widgets/sleep_widget.dart';

class SleepSetupScreen1 extends GetView<SleepController> {
  const SleepSetupScreen1({super.key});

  Future<void> _selectBedtime(BuildContext context) async {
    final currentTime = SleepTimeHelper.parseTimeOfDay(
      controller.targetBedtime.value,
    );
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: currentTime,
      helpText: 'Select Target Bedtime',
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
            textButtonTheme: TextButtonThemeData(
              style: ButtonStyle(
                foregroundColor: WidgetStatePropertyAll(Colors.indigo),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      controller.updateBedtime(picked);
    }
  }

  Future<void> _selectWakeTime(BuildContext context) async {
    final currentTime = SleepTimeHelper.parseTimeOfDay(
      controller.targetWake.value,
    );
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: currentTime,
      helpText: 'Select Target Wake Time',
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
            textButtonTheme: TextButtonThemeData(
              style: ButtonStyle(
                foregroundColor: WidgetStatePropertyAll(Colors.indigo),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      controller.updateWakeTime(picked);
    }
  }

  Future<void> _continue() async {
    if (controller.durationWarning.value.isNotEmpty) {
      final confirm = await Get.dialog<bool>(
        AlertDialog(
          title: const Text('Unusual Sleep Duration'),
          content: Text(controller.durationWarning.value),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: const Text('Edit Times'),
            ),
            ElevatedButton(
              onPressed: () => Get.back(result: true),
              child: const Text('Continue Anyway'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    final success = await controller.saveSleepProfile();
    if (success) {
      Get.to(() => const SleepSetupScreen2());
    }
  }

  Future<bool> _onWillPop() async {
    if (controller.selectedChronotype.value != null) {
      final shouldPop = await Get.dialog<bool>(
        AlertDialog(
          title: const Text('Save Progress?'),
          content: const Text('Do you want to save your changes before leaving?'),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: true),
              child: const Text('Discard', style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                await controller.saveSleepProfile();
                Get.back(result: true);
              },
              child: const Text('Save & Exit'),
            ),
          ],
        ),
      );
      return shouldPop ?? false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: SleepTheme.background,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              if (await _onWillPop()) Get.back();
            },
          ),
          title: const Text('Sleep Setup'),
          elevation: 0,
          backgroundColor: Colors.transparent,
        ),
        body: Obx(() {
          if (controller.isLoading.value && controller.userData.value == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (controller.errorMessage.value.isNotEmpty &&
              controller.userData.value == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: SleepTheme.error),
                  const SizedBox(height: 16),
                  Text(
                    controller.errorMessage.value,
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: controller.loadUserData,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final userData = controller.userData.value;
          if (userData == null) {
            return const Center(child: Text('User data not available'));
          }

          return Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SetupProgressIndicator(currentStep: 1, totalSteps: 3),
                    const SizedBox(height: 32),

                    Text(
                      'Let\'s personalize your\nsleep tracking',
                      style: Theme.of(context).textTheme.displayMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This will only take a minute',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 32),

                    const SectionHeader(
                      title: 'What\'s your natural rhythm?',
                      subtitle: 'When do you feel most alert?',
                    ),
                    ...Chronotype.values.map(
                          (chronotype) => Obx(
                            () => ChronotypeChip(
                          chronotype: chronotype,
                          isSelected: controller.selectedChronotype.value == chronotype,
                          onTap: () => controller.selectChronotype(chronotype),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    const SectionHeader(
                      title: 'Your ideal sleep window',
                      subtitle: 'We\'ll remind you to wind down at this time',
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Obx(
                                () => TimePickerButton(
                              label: 'Target Bedtime',
                              timeValue: controller.targetBedtime.value,
                              onTap: () => _selectBedtime(context),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Obx(
                                () => TimePickerButton(
                              label: 'Target Wake Time',
                              timeValue: controller.targetWake.value,
                              onTap: () => _selectWakeTime(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Obx(
                          () => DurationDisplay(
                        durationMinutes: controller.calculatedDuration.value,
                        warningMessage: controller.durationWarning.value.isEmpty
                            ? null
                            : controller.durationWarning.value,
                      ),
                    ),
                    const SizedBox(height: 32),

                    PersonalizedInfoCard(userData: userData),
                    const SizedBox(height: 100), // space for bottom button
                  ],
                ),
              ),

              if (controller.isLoading.value)
                const Positioned.fill(
                  child: LoadingOverlay(message: 'Saving your profile...'),
                ),

              Positioned(
                left: 0,
                right: 0,
                bottom: 0, // <- keep at 0 so it sits flush with safe area
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
                    child: Obx(
                          () => ElevatedButton(
                        onPressed: controller.selectedChronotype.value != null &&
                            !controller.isLoading.value
                            ? _continue
                            : null,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
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
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}
