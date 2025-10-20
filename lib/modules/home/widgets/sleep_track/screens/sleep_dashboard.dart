import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:famina/navigation_menu.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controller/sleep_controller.dart';
import '../models/sleep_model.dart';
import '../theme/sleep_theme.dart';
import 'morning_checking_screen.dart';

class SleepDashboardScreen extends StatefulWidget {
  const SleepDashboardScreen({super.key});

  @override
  State<SleepDashboardScreen> createState() => _SleepDashboardScreenState();
}

class _SleepDashboardScreenState extends State<SleepDashboardScreen> {
  final SleepController controller = Get.find<SleepController>();

  bool _prompted = false;

  late Future<bool> _todayLogFuture;

  @override
  void initState() {
    super.initState();
    _todayLogFuture = _hasLogForToday();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePromptMorning());
  }

  // ---------- Helpers ----------

  /// Returns Firestore doc key like "yyyy-MM-dd"
  String _dayKey(DateTime d) => SleepTimeHelper.dayKey(d);

  /// Check whether today's sleep log exists for current user
  Future<bool> _hasLogForToday() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final key = _dayKey(DateTime.now());
    final snap = await FirebaseFirestore.instance
        .collection('Users')
        .doc(uid)
        .collection('sleep_logs')
        .doc(key)
        .get();
    return snap.exists;
  }

  Future<void> _showManualSleepLogDialog(BuildContext context) async {
    final controller = Get.find<SleepController>();

    // sensible defaults (yesterday -> today)
    DateTime date = DateTime.now().subtract(const Duration(days: 1));
    TimeOfDay? bed =
        SleepTimeHelper.parseTimeOfDay(controller.targetBedtime.value) ??
        const TimeOfDay(hour: 23, minute: 0);
    TimeOfDay? wake =
        SleepTimeHelper.parseTimeOfDay(controller.targetWake.value) ??
        const TimeOfDay(hour: 7, minute: 0);

    String _fmtDate(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    int _calcDuration() {
      final b = SleepTimeHelper.formatTimeOfDay(bed!);
      final w = SleepTimeHelper.formatTimeOfDay(wake!);
      return SleepTimeHelper.calculateDurationMinutes(b, w);
    }

    Future<void> pickDate() async {
      final picked = await showDatePicker(
        context: context,
        initialDate: date,
        firstDate: DateTime.now().subtract(const Duration(days: 30)),
        lastDate: DateTime.now(),
        builder: (ctx, child) {
          return Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: const ColorScheme.light(
                primary: Colors.indigo,
                onPrimary: Colors.white,
                onSurface: Colors.indigo,
              ),
              textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(foregroundColor: Colors.indigo),
              ),
            ),
            child: child!,
          );
        },
      );
      if (picked != null) date = picked;
    }

    Future<void> pickBed() async {
      final picked = await showTimePicker(
        context: context,
        initialTime: bed!,
        helpText: 'Select Bedtime',
        builder: (ctx, child) {
          return Theme(
            data: Theme.of(ctx).copyWith(
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
      if (picked != null) bed = picked;
    }

    Future<void> pickWake() async {
      final picked = await showTimePicker(
        context: context,
        initialTime: wake!,
        helpText: 'Select Wake Time',
        builder: (ctx, child) {
          return Theme(
            data: Theme.of(ctx).copyWith(
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
      if (picked != null) wake = picked;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setState) {
              final durationMin = _calcDuration();
              final durationText = durationMin <= 0
                  ? '—'
                  : '${(durationMin ~/ 60)}h ${(durationMin % 60).toString().padLeft(2, '0')}m';

              Color durationColor;
              if (durationMin == 0) {
                durationColor = Colors.grey;
              } else if (durationMin < 6 * 60) {
                durationColor = Colors.orange;
              } else if (durationMin <= 9 * 60) {
                durationColor = Colors.green;
              } else {
                durationColor = Colors.teal;
              }

              // await pickers before rebuilding
              Widget chipButton({
                required IconData icon,
                required String label,
                required Future<void> Function() onTap,
              }) {
                return ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 120),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.indigo),
                      foregroundColor: Colors.indigo,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                    onPressed: () async {
                      await onTap();
                      if (ctx.mounted) setState(() {});
                    },
                    icon: Icon(icon, size: 18),
                    label: FittedBox(
                      child: Text(
                        label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                );
              }

              // Responsive, centered content with max width
              return LayoutBuilder(
                builder: (ctx, cons) {
                  final horizontalPad = cons.maxWidth < 360 ? 8.0 : 16.0;

                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPad,
                      6,
                      horizontalPad,
                      16,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // title
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 6,
                                bottom: 10,
                              ),
                              child: Text(
                                'Add Manual Sleep Log',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF3F3D56),
                                    ),
                                textAlign: TextAlign.center,
                                softWrap: true,
                                maxLines: 2,
                              ),
                            ),

                            // responsive controls
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                chipButton(
                                  icon: Icons.event,
                                  label: _fmtDate(date),
                                  onTap: pickDate,
                                ),
                                chipButton(
                                  icon: Icons.bedtime,
                                  label:
                                      'Bed: ${SleepTimeHelper.formatTimeOfDay(bed!)}',
                                  onTap: pickBed,
                                ),
                                chipButton(
                                  icon: Icons.wb_sunny,
                                  label:
                                      'Wake: ${SleepTimeHelper.formatTimeOfDay(wake!)}',
                                  onTap: pickWake,
                                ),
                              ],
                            ),

                            const SizedBox(height: 14),

                            // duration preview
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: durationColor.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: durationColor.withOpacity(0.35),
                                ),
                              ),
                              child: Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                children: [
                                  Icon(
                                    Icons.timer_outlined,
                                    size: 18,
                                    color: durationColor,
                                  ),
                                  Text(
                                    'Duration: $durationText',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: durationColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // save button
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.indigo,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                                onPressed: () async {
                                  final ok = await controller
                                      .saveSleepLogFromTimes(
                                        bedtimeHHmm:
                                            SleepTimeHelper.formatTimeOfDay(
                                              bed!,
                                            ),
                                        wakeHHmm:
                                            SleepTimeHelper.formatTimeOfDay(
                                              wake!,
                                            ),
                                        date: date,
                                      );
                                  if (ok) {
                                    Get.back();
                                    Get.snackbar(
                                      'Saved',
                                      'Sleep log added',
                                      snackPosition: SnackPosition.BOTTOM,
                                      backgroundColor: Colors.green.withOpacity(
                                        0.85,
                                      ),
                                      colorText: Colors.white,
                                    );
                                  } else {
                                    Get.snackbar(
                                      'Error',
                                      'Failed to save log',
                                      snackPosition: SnackPosition.BOTTOM,
                                      backgroundColor: Colors.red.withOpacity(
                                        0.85,
                                      ),
                                      colorText: Colors.white,
                                    );
                                  }
                                },
                                child: const Text(
                                  'Save',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  /// Show bottom sheet (one time) if in morning window and log missing
  Future<void> _maybePromptMorning() async {
    if (_prompted) return;
    _prompted = true;

    final now = DateTime.now();
    final inMorningWindow = now.hour >= 6 && now.hour <= 11;
    if (!inMorningWindow) return;

    // Ensure user/profile loaded
    if (controller.userData.value?.sleepProfile == null) return;

    final missing = !(await _hasLogForToday());
    if (!missing || !mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Good morning ☀️",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                "Log your sleep from last night?",
                textAlign: TextAlign.center,
                style: TextStyle(color: SleepTheme.textPrimary),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Later"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Get.to(() => const MorningCheckInScreen());
                      },
                      child: const Text("Log Sleep"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SleepTheme.background,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Get.offAll(() => const NavigationMenu()),
          icon: const Icon(Icons.arrow_back_ios_new),
        ),
        automaticallyImplyLeading: false,
        title: const Text('Sleep Tracking'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          PopupMenuButton<int>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'More options',
            position: PopupMenuPosition.under,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 1,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.alarm),
                  title: const Text('Set Morning Reminder'),
                  subtitle: Text(controller.morningReminderHHmm.value),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 99,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.settings_outlined),
                  title: Text('Sleep settings (soon)'),
                ),
              ),
            ],
            onSelected: (v) async {
              if (v == 1) {
                final current = SleepTimeHelper.parseTimeOfDay(
                  controller.morningReminderHHmm.value,
                );

                final picked = await showTimePicker(
                  context: context,
                  initialTime: current,
                  helpText: 'Morning reminder time',
                  builder: (ctx, child) {
                    return Theme(
                      data: Theme.of(ctx).copyWith(
                        colorScheme: const ColorScheme.light(
                          primary: Colors.indigo, // header & active controls
                          onPrimary: Colors.white, // text on header
                          onSurface: Colors.indigo, // body text
                        ),
                        textButtonTheme: TextButtonThemeData(
                          style: TextButton.styleFrom(
                            foregroundColor:
                                Colors.indigo, // CANCEL & OK buttons
                          ),
                        ),
                      ),
                      child: child!,
                    );
                  },
                );

                if (picked != null) {
                  controller.updateMorningReminder(picked);
                  Get.snackbar(
                    'Updated',
                    'Morning reminder set to ${SleepTimeHelper.formatTimeOfDay(picked)}',
                    snackPosition: SnackPosition.BOTTOM,
                  );
                }
              }
            },
          ),
        ],
      ),
      body: Obx(() {
        final userData = controller.userData.value;
        final sleepProfile = userData?.sleepProfile;

        if (userData == null || sleepProfile == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return RefreshIndicator(
          onRefresh: () async {
            await controller.loadUserData();
            setState(() {
              _todayLogFuture = _hasLogForToday();
            });
          },
          color: SleepTheme.primaryMid,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Morning missing log banner (inline)
                FutureBuilder<bool>(
                  future: _hasLogForToday(),
                  builder: (context, snap) {
                    final now = DateTime.now();
                    final inMorningWindow =
                        now.hour >= 6 && now.hour <= 11; // tune as needed
                    final missing =
                        snap.connectionState == ConnectionState.done &&
                        (snap.data == false);
                    if (missing && inMorningWindow) {
                      return _MissingLogBanner(
                        onLogNow: () {
                          Get.to(() => const MorningCheckInScreen());
                        },
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),

                // Greeting
                _buildGreeting(context),
                const SizedBox(height: 24),

                // Hero + Quick Stats (real data from most recent log)
                FutureBuilder<SleepLog?>(
                  future: controller.getMostRecentLog(),
                  builder: (context, snap) {
                    final log = snap.data;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeroCard(context, sleepProfile, log: log),
                        const SizedBox(height: 24),
                        _buildQuickStats(context, mostRecent: log),
                        const SizedBox(height: 24),
                      ],
                    );
                  },
                ),

                // Live Sensor Readings
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Text(
                      'Live Tracking',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: SleepTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    _buildSessionStatusChip(),
                    const Spacer(),
                    const SizedBox(width: 8),
                    _buildStartStopButton(),
                  ],
                ),

                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: Obx(() {
                        final dB = controller.noiseLevel.value;
                        return _buildStatCard(
                          icon: Icons.mic,
                          iconColor: SleepTheme.accentPurple,
                          value: "${dB.toStringAsFixed(1)} dB",
                          label: "Noise Level",
                        );
                      }),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Obx(() {
                        final moving = controller.isUserMoving.value;
                        return _buildStatCard(
                          icon: Icons.directions_walk,
                          iconColor: moving
                              ? SleepTheme.warning
                              : SleepTheme.success,
                          value: moving ? "Moving" : "Still",
                          label: "Motion Status",
                        );
                      }),
                    ),
                  ],
                ),

                // Consistency & Debt Cards (placeholder logic)
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(child: _buildConsistencyCard(context)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildSleepDebtCard(context)),
                  ],
                ),
                const SizedBox(height: 24),

                // Cycle Phase Card (if applicable)
                if (userData.lastPeriodStartTs != null)
                  _buildCyclePhaseCard(context, userData),
                if (userData.lastPeriodStartTs != null)
                  const SizedBox(height: 24),

                // Quick Actions
                _buildQuickActions(context, sleepProfile),
                const SizedBox(height: 24),

                // Weekly Trend (real data)
                FutureBuilder<List<SleepLog>>(
                  future: controller.getRecentLogs(days: 7),
                  builder: (context, snap) {
                    final logs = snap.data ?? const <SleepLog>[];
                    return _buildWeeklyTrend(context, logs, sleepProfile);
                  },
                ),
                const SizedBox(height: 24),

                // Sleep Tips
                _buildSleepTips(context),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildGreeting(BuildContext context) {
    final hour = DateTime.now().hour;
    String greeting;
    String emoji;

    if (hour < 12) {
      greeting = 'Good morning';
      emoji = '🌅';
    } else if (hour < 17) {
      greeting = 'Good afternoon';
      emoji = '☀️';
    } else if (hour < 21) {
      greeting = 'Good evening';
      emoji = '🌆';
    } else {
      greeting = 'Good night';
      emoji = '🌙';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$greeting $emoji',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          'Here\'s your sleep summary',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: SleepTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _buildHeroCard(
    BuildContext context,
    SleepProfile sleepProfile, {
    SleepLog? log,
  }) {
    final int sleepScore = (log != null)
        ? controller.computeSleepScore(log, sleepProfile)
        : -1; // use -1 as flag

    final int durationMin =
        (log?.totalSleepMinutes ?? log?.durationMinutes) ?? -1;

    final String duration = durationMin >= 0
        ? "${durationMin ~/ 60}h ${durationMin % 60}m"
        : "No sleep logged yet";

    final int awakenings = log?.awakenings ?? -1;

    final String bedtime = log?.bedtimeHHmm ?? "Not logged";
    final String wake = log?.wakeHHmm ?? "Not logged";


    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: SleepTheme.sleepyGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: SleepTheme.softShadow,
      ),
      child: Column(
        children: [
          // Score ring
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 140,
                height: 140,
                child: CircularProgressIndicator(
                  value: (sleepScore.clamp(0, 100)) / 100.0,
                  strokeWidth: 12,
                  backgroundColor: Colors.white.withOpacity(0.2),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              Column(
                children: [
                  Text(
                    sleepScore >= 0 ? sleepScore.toString() : "No data",
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Text(
                    'Sleep Score',
                    style: TextStyle(fontSize: 14, color: Colors.white70),
                  ),

                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Duration
          Text(
            duration,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Total sleep time',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 20),

          // Quick stats
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMiniStat(
                  log != null ? '✅' : '—',
                  'On time',
                ),
                _buildMiniStat(
                  log != null ? '${_approxEfficiency(durationMin, log)}%' : 'No data',
                  'Efficiency',
                ),
                _buildMiniStat(
                  awakenings >= 0 ? '$awakenings' : 'No data',
                  'Awakenings',
                ),

              ],
            ),
          ),
          const SizedBox(height: 16),

          // Time range
          Text(
            log != null
                ? 'In bed: $bedtime → Awake: $wake'
                : 'No sleep session logged yet',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.7),
            ),
          ),

        ],
      ),
    );
  }

  // naive placeholder until you track awake minutes separately
  int _approxEfficiency(int durationMin, SleepLog log) {
    final latency = (log.sleepLatencyMinutes ?? 0).clamp(0, 90);
    final wakes = (log.awakenings ?? 0).clamp(0, 4) * 5; // 5 mins per wake
    final estAsleep = (log.totalSleepMinutes ?? (durationMin - latency - wakes))
        .clamp(0, durationMin);
    if (durationMin <= 0) return 0;
    return ((estAsleep / durationMin) * 100).round().clamp(0, 100);
  }

  Widget _buildMiniStat(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.7)),
        ),
      ],
    );
  }

  Widget _buildQuickStats(BuildContext context, {SleepLog? mostRecent}) {
    final int dur = mostRecent?.durationMinutes ?? 0;
    final int latency = mostRecent?.sleepLatencyMinutes ?? 0;

    final int? estTotalMin = (mostRecent == null)
        ? null
        : (mostRecent.totalSleepMinutes ?? (dur - latency)).clamp(0, dur);

    final int? awakeMin = (dur > 0 && estTotalMin != null)
        ? (dur - estTotalMin).clamp(0, dur)
        : null;

    final int? latencyMin = mostRecent?.sleepLatencyMinutes;

    final int? durationMin = mostRecent?.durationMinutes;

    String fmtMins(int? m) {
      if (m == null) return '—';
      if (m < 60) return '${m} min';
      final h = m ~/ 60, mm = m % 60;
      return mm == 0 ? '${h}h' : '${h}h ${mm}m';
    }

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            icon: Icons.bedtime,
            iconColor: SleepTheme.primaryMid,
            value: fmtMins(latencyMin),
            label: 'Sleep latency',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.nights_stay,
            iconColor: SleepTheme.accentPurple,
            value: fmtMins(awakeMin),
            label: 'Awake time',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FutureBuilder<int>(
            future: controller.getVsLastWeekDeltaMinutes(),
            builder: (context, snap) {
              final has =
                  snap.connectionState == ConnectionState.done && snap.hasData;
              final deltaMin = has ? snap.data!.clamp(-24 * 60, 24 * 60) : 0;
              final sign = deltaMin > 0 ? '+' : (deltaMin < 0 ? '−' : '');
              final absMin = deltaMin.abs();
              final value = has ? '$sign$absMin min' : '—';

              final icon = deltaMin >= 0
                  ? Icons.trending_up
                  : Icons.trending_down;
              final color = deltaMin >= 0
                  ? SleepTheme.success
                  : SleepTheme.warning;

              return _buildStatCard(
                icon: icon,
                iconColor: color,
                value: value,
                label: 'vs last week',
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SleepTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SleepTheme.divider),
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: SleepTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: SleepTheme.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildConsistencyCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SleepTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SleepTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.calendar_today, color: SleepTheme.info, size: 20),
          const SizedBox(height: 12),
          const Text(
            'Consistency',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: SleepTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '±24 min',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: SleepTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: const LinearProgressIndicator(
              value: 0.78,
              backgroundColor: SleepTheme.primaryPale,
              valueColor: AlwaysStoppedAnimation(SleepTheme.info),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Last 7 days',
            style: TextStyle(fontSize: 11, color: SleepTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildSleepDebtCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SleepTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SleepTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.hourglass_bottom,
            color: SleepTheme.warning,
            size: 20,
          ),
          const SizedBox(height: 12),
          const Text(
            'Sleep Debt',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: SleepTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '—',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: SleepTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: SleepTheme.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'Catch up this weekend',
              style: TextStyle(
                fontSize: 10,
                color: SleepTheme.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Rolling 7 days',
            style: TextStyle(fontSize: 11, color: SleepTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildCyclePhaseCard(BuildContext context, UserData userData) {
    final now = DateTime.now();
    final lastPeriod = userData.lastPeriodStartTs?.toDate() ?? now;
    final daysSincePeriod = now.difference(lastPeriod).inDays;
    final cycleLength = userData.avgCycleLengthDays ?? 28;
    final daysToNextPeriod = cycleLength - daysSincePeriod;

    String phase;
    Color phaseColor;
    String phaseIcon;

    if (daysSincePeriod <= 6) {
      phase = 'Menstruation';
      phaseColor = const Color(0xFFEF5350);
      phaseIcon = '🩸';
    } else if (daysSincePeriod <= 14) {
      phase = 'Follicular';
      phaseColor = const Color(0xFF42A5F5);
      phaseIcon = '🌱';
    } else if (daysSincePeriod <= 16) {
      phase = 'Ovulation';
      phaseColor = const Color(0xFFFFB74D);
      phaseIcon = '🌟';
    } else {
      phase = 'Luteal';
      phaseColor = const Color(0xFF9C27B0);
      phaseIcon = '🌙';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [phaseColor.withOpacity(0.1), phaseColor.withOpacity(0.05)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: phaseColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: phaseColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(phaseIcon, style: const TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cycle Phase: $phase',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: phaseColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Day $daysSincePeriod • ${daysToNextPeriod > 0 ? "$daysToNextPeriod days to period" : "Period expected soon"}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: SleepTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.arrow_forward_ios, size: 16, color: phaseColor),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context, SleepProfile sleepProfile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: SleepTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                icon: Icons.air,
                label: 'Wind Down',
                color: SleepTheme.primaryMid,
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(18),
                      ),
                    ),
                    builder: (_) {
                      int mins = 20;
                      final checks = <String, bool>{
                        'Dim the lights': false,
                        'Put phone on DND': false,
                        'Light stretch / breath': false,
                        'No screens': false,
                      }.obs;

                      // auto-suggest start: targetBedtime - 30
                      final tb = SleepTimeHelper.parseTimeOfDay(
                        controller.targetBedtime.value,
                      );
                      final now = TimeOfDay.now();
                      final suggested = TimeOfDay(
                        hour: (tb.hour * 60 + tb.minute - 30) ~/ 60,
                        minute: (tb.hour * 60 + tb.minute - 30) % 60,
                      );
                      final suggestionStr = SleepTimeHelper.formatTimeOfDay(
                        suggested,
                      );
                      final alreadyPast =
                          (now.hour * 60 + now.minute) >
                          (suggested.hour * 60 + suggested.minute);

                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        child: Obx(
                          () => Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Wind Down',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Suggested: $suggestionStr (30 min before bedtime)'
                                '${alreadyPast ? " • tomorrow" : ""}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  const Text('Duration'),
                                  const SizedBox(width: 12),
                                  DropdownButton<int>(
                                    value: mins,
                                    items: const [15, 20, 30, 45]
                                        .map(
                                          (m) => DropdownMenuItem(
                                            value: m,
                                            child: Text('$m min'),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) {
                                      if (v != null) mins = v;
                                    },
                                  ),
                                  const Spacer(),
                                  if (controller.windDownActive.value)
                                    Text(
                                      '${(controller.windDownRemaining.value ~/ 60).toString().padLeft(2, "0")}:${(controller.windDownRemaining.value % 60).toString().padLeft(2, "0")}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ...checks.keys.map(
                                (k) => CheckboxListTile(
                                  dense: true,
                                  value: checks[k],
                                  onChanged: (v) => checks[k] = v ?? false,
                                  title: Text(k),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () {
                                        controller.cancelWindDown();
                                        Get.back();
                                      },
                                      child: const Text('Cancel'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.indigo,
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () {
                                        controller.startWindDown(minutes: mins);
                                      },
                                      child: Text(
                                        controller.windDownActive.value
                                            ? 'Restart'
                                            : 'Start',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                icon: Icons.wb_sunny,
                label: 'Log Sleep',
                color: SleepTheme.success,
                onTap: () async {
                  final missing = !(await _hasLogForToday());
                  final now = DateTime.now();
                  final inMorningWindow = now.hour >= 6 && now.hour <= 11;
                  if (inMorningWindow && missing) {
                    // Morning guided check-in
                    Get.to(() => const MorningCheckInScreen());
                  } else {
                    // Manual quick-add dialog (same helper you wrote earlier)
                    _showManualSleepLogDialog(context);
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                icon: Icons.snooze,
                label: 'Log Nap',
                color: SleepTheme.accentPurple,
                onTap: () async {
                  await showModalBottomSheet(
                    context: context,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(18),
                      ),
                    ),
                    builder: (_) => Obx(() {
                      final active = controller.napActive.value;
                      final elapsed = controller.napElapsed.value;
                      final mm = (elapsed ~/ 60).toString().padLeft(2, '0');
                      final ss = (elapsed % 60).toString().padLeft(2, '0');

                      DateTime end = DateTime.now();
                      DateTime start = end.subtract(
                        const Duration(minutes: 20),
                      );

                      return StatefulBuilder(
                        builder: (ctx, setState) => Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Nap',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Live timer (fixed width constraints on button)
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: SleepTheme.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: SleepTheme.divider),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.timer_outlined),
                                    const SizedBox(width: 8),
                                    Text(
                                      active ? '$mm:$ss' : '00:00',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const Spacer(),
                                    // ✅ shrink-wrapped, height-bounded to avoid infinite width
                                    IntrinsicWidth(
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          minWidth: 0,
                                        ),
                                        child: SizedBox(
                                          height: 50,
                                          child: ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: active
                                                  ? Colors.red
                                                  : Colors.indigo,
                                              foregroundColor: Colors.white,
                                              minimumSize: const Size(0, 50),
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                  ),
                                            ),
                                            onPressed:
                                                controller.toggleNapSession,
                                            child: Text(
                                              active
                                                  ? 'Stop & Save'
                                                  : 'Start Nap',
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 12),
                              const Divider(),
                              const SizedBox(height: 12),

                              // Quick manual log
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.indigo,                 // text & ripple
                                        side: const BorderSide(color: Colors.indigo),   // border
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(28),      // pill look
                                        ),
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                      ),
                                      onPressed: () async {
                                        final t = await showTimePicker(
                                          context: ctx,
                                          initialTime: TimeOfDay.fromDateTime(start),
                                          helpText: 'Nap start',
                                          builder: (pickerCtx, child) {
                                            const indigo = Colors.indigo;

                                            return Theme(
                                              data: Theme.of(pickerCtx).copyWith(
                                                // keep your existing colorScheme overrides if you like
                                                colorScheme: Theme.of(pickerCtx).colorScheme.copyWith(
                                                  primary: indigo,
                                                  onPrimary: Colors.white,
                                                  onSurface: indigo,
                                                ),
                                                textButtonTheme: TextButtonThemeData(
                                                  style: TextButton.styleFrom(foregroundColor: indigo),
                                                ),
                                                timePickerTheme: TimePickerThemeData(
                                                  // the big hour/minute “pill”
                                                  hourMinuteColor: MaterialStateColor.resolveWith(
                                                        (s) => indigo, // filled pill
                                                  ),
                                                  hourMinuteTextColor: MaterialStateColor.resolveWith(
                                                        (s) => Colors.white, // visible text
                                                  ),
                                                  hourMinuteShape: const RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.all(Radius.circular(16)),
                                                  ),

                                                  // AM/PM chip
                                                  dayPeriodColor: MaterialStateColor.resolveWith(
                                                        (s) => s.contains(MaterialState.selected)
                                                        ? indigo
                                                        : indigo.withOpacity(.08),
                                                  ),
                                                  dayPeriodTextColor: MaterialStateColor.resolveWith(
                                                        (s) => s.contains(MaterialState.selected)
                                                        ? Colors.white
                                                        : indigo,
                                                  ),
                                                  dayPeriodShape: const RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.all(Radius.circular(12)),
                                                  ),

                                                  // Dial
                                                  dialBackgroundColor: indigo.withOpacity(.08),
                                                  dialHandColor: indigo,
                                                  dialTextColor: MaterialStateColor.resolveWith(
                                                        (s) => s.contains(MaterialState.selected) ? Colors.white : indigo,
                                                  ),

                                                  entryModeIconColor: indigo,
                                                  helpTextStyle: const TextStyle(fontWeight: FontWeight.w600),
                                                ),
                                              ),
                                              child: child!,
                                            );
                                          },

                                        );
                                        if (t != null) {
                                          final d = DateTime.now();
                                          start = DateTime(d.year, d.month, d.day, t.hour, t.minute);
                                          if (ctx.mounted) setState(() {});
                                        }
                                      },
                                      child: Text(
                                        'Start: ${TimeOfDay.fromDateTime(start).format(ctx)}',
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.indigo,
                                        side: const BorderSide(color: Colors.indigo),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(28),
                                        ),
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                      ),
                                      onPressed: () async {
                                        final t = await showTimePicker(
                                          context: ctx,
                                          initialTime: TimeOfDay.fromDateTime(end),
                                          helpText: 'Nap end',
                                          builder: (pickerCtx, child) {
                                            const indigo = Colors.indigo;

                                            return Theme(
                                              data: Theme.of(pickerCtx).copyWith(
                                                // keep your existing colorScheme overrides if you like
                                                colorScheme: Theme.of(pickerCtx).colorScheme.copyWith(
                                                  primary: indigo,
                                                  onPrimary: Colors.white,
                                                  onSurface: indigo,
                                                ),
                                                textButtonTheme: TextButtonThemeData(
                                                  style: TextButton.styleFrom(foregroundColor: indigo),
                                                ),
                                                timePickerTheme: TimePickerThemeData(
                                                  // the big hour/minute “pill”
                                                  hourMinuteColor: MaterialStateColor.resolveWith(
                                                        (s) => indigo, // filled pill
                                                  ),
                                                  hourMinuteTextColor: MaterialStateColor.resolveWith(
                                                        (s) => Colors.white, // visible text
                                                  ),
                                                  hourMinuteShape: const RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.all(Radius.circular(16)),
                                                  ),

                                                  // AM/PM chip
                                                  dayPeriodColor: MaterialStateColor.resolveWith(
                                                        (s) => s.contains(MaterialState.selected)
                                                        ? indigo
                                                        : indigo.withOpacity(.08),
                                                  ),
                                                  dayPeriodTextColor: MaterialStateColor.resolveWith(
                                                        (s) => s.contains(MaterialState.selected)
                                                        ? Colors.white
                                                        : indigo,
                                                  ),
                                                  dayPeriodShape: const RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.all(Radius.circular(12)),
                                                  ),

                                                  // Dial
                                                  dialBackgroundColor: indigo.withOpacity(.08),
                                                  dialHandColor: indigo,
                                                  dialTextColor: MaterialStateColor.resolveWith(
                                                        (s) => s.contains(MaterialState.selected) ? Colors.white : indigo,
                                                  ),

                                                  entryModeIconColor: indigo,
                                                  helpTextStyle: const TextStyle(fontWeight: FontWeight.w600),
                                                ),
                                              ),
                                              child: child!,
                                            );
                                          },

                                        );
                                        if (t != null) {
                                          final d = DateTime.now();
                                          end = DateTime(d.year, d.month, d.day, t.hour, t.minute);
                                          if (ctx.mounted) setState(() {});
                                        }
                                      },
                                      child: Text(
                                        'End: ${TimeOfDay.fromDateTime(end).format(ctx)}',
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 8),
                              Text(
                                'Duration: ${end.isAfter(start) ? end.difference(start).inMinutes : 0} min',
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.indigo,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: end.isAfter(start)
                                      ? () async {
                                          final ok = await controller
                                              .saveNapLog(
                                                start: start,
                                                end: end,
                                              );
                                          if (ok) {
                                            Get.back();
                                            Get.snackbar('Saved', 'Nap logged');
                                          } else {
                                            Get.snackbar(
                                              'Error',
                                              'Couldn’t save nap',
                                            );
                                          }
                                        }
                                      : null,
                                  child: const Text('Save Quick Log'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                icon: Icons.insights,
                label: 'Insights',
                color: SleepTheme.info,
                onTap: () => _showInsightsSheet(context),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _insightCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SleepTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SleepTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: SleepTheme.info, size: 20),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: SleepTheme.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: SleepTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }


  Future<void> _showInsightsSheet(BuildContext context) async {
    // pull data
    final logs = await controller.getRecentLogs(days: 7);
    if (!mounted) return;

    // compute a few simple insights
    int totalMin = 0;
    int nights = 0;
    int goodNights = 0;
    int avgEfficiency = 0;
    int latestLatency = 0;

    for (final l in logs) {
      final dur = l.totalSleepMinutes ?? l.durationMinutes;
      if (dur != null && dur > 0) {
        totalMin += dur;
        nights++;
        latestLatency = l.sleepLatencyMinutes ?? latestLatency;
        // reuse your helper to estimate efficiency
        avgEfficiency += _approxEfficiency(dur, l);
        if (dur >= 7 * 60) goodNights++;
      }
    }

    final avgMin = nights == 0 ? 0 : (totalMin ~/ nights);
    final avgEff = nights == 0 ? 0 : (avgEfficiency ~/ nights);

    String _fmtMins(int m) {
      if (m <= 0) return '—';
      final h = m ~/ 60, mm = m % 60;
      return mm == 0 ? '${h}h' : '${h}h ${mm}m';
      // e.g. 7h 25m
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: const [
                  Icon(Icons.insights, color: SleepTheme.info),
                  SizedBox(width: 8),
                  Text(
                    'Insights (last 7 days)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Cards
              Row(
                children: [
                  Expanded(
                    child: _insightCard(
                      icon: Icons.hotel,
                      title: 'Avg. Sleep',
                      value: _fmtMins(avgMin),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _insightCard(
                      icon: Icons.speed,
                      title: 'Avg. Efficiency',
                      value: '$avgEff%',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _insightCard(
                      icon: Icons.check_circle,
                      title: '7h+ Nights',
                      value: '$goodNights/$nights',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _insightCard(
                      icon: Icons.hourglass_top,
                      title: 'Latest Latency',
                      value: _fmtMins(latestLatency),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              // Quick note / tip
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SleepTheme.info.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: SleepTheme.info.withOpacity(0.25)),
                ),
                child: Text(
                  avgMin < 7 * 60
                      ? 'You\'re averaging less than 7h. Try starting wind down 30 min earlier tonight.'
                      : 'Nice! You\'re averaging ${_fmtMins(avgMin)}. Keep consistency for better recovery.',
                  style: const TextStyle(
                    color: SleepTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _MissingLogBanner({required VoidCallback onLogNow}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        border: Border.all(color: const Color(0xFFFFECB3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              "⚠️ Missing Sleep Log — you haven’t logged last night’s sleep.",
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(onPressed: onLogNow, child: const Text("Log Now")),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Weekly Trend ----------

  Widget _buildWeeklyTrend(
    BuildContext context,
    List<SleepLog> logs,
    SleepProfile profile,
  ) {
    final now = DateTime.now();
    final days = List.generate(
      7,
      (i) => DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: 6 - i)),
    );

    // nightly hours
    final hoursByKey = <String, double>{};
    for (final l in logs) {
      final mins = (l.totalSleepMinutes ?? l.durationMinutes);
      hoursByKey[SleepTimeHelper.dayKey(l.date)] = mins / 60.0;
    }

    return FutureBuilder<Map<String, int>>(
      future: controller.getRecentNapMinutesByDay(days: 7),
      builder: (context, snap) {
        final napMinByKey = snap.data ?? const <String, int>{};

        final nightly = days.map((d) => hoursByKey[_dayKey(d)] ?? 0.0).toList();
        final naps = days
            .map((d) => (napMinByKey[_dayKey(d)] ?? 0) / 60.0)
            .toList();
        final labels = days.map(_weekdayLabel).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Weekly Trend',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: SleepTheme.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: SleepTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: SleepTheme.divider),
              ),
              child: _buildSimpleChartFrom(
                nightly,
                naps.cast<double>(),
                labels,
              ),
            ),
          ],
        );
      },
    );
  }

  String _weekdayLabel(DateTime d) {
    const names = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return names[d.weekday % 7];
  }

  Widget _buildSimpleChartFrom(
    List<double> sleepHours,
    List<double> napHours,
    List<String> days,
  ) {
    final maxSleep = sleepHours.isEmpty
        ? 8.0
        : sleepHours.reduce((a, b) => a > b ? a : b);
    final maxNap = napHours.isEmpty
        ? 1.0
        : napHours.reduce((a, b) => a > b ? a : b);
    final maxValue = [
      maxSleep + maxNap,
      6.0,
    ].reduce((a, b) => a > b ? a : b); // ensure at least 6h scale

    const double chartHeight = 150;
    const double valueLabelHeight = 16;
    const double spacing = 4;
    final double barMaxHeight = chartHeight - valueLabelHeight - spacing;

    return Column(
      children: [
        SizedBox(
          height: chartHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(7, (i) {
              final base = sleepHours[i];
              final nap = napHours[i];
              final total = base + nap;
              final isToday = i == 6;

              final baseH =
                  ((base <= 0 ? 0.05 : base) / maxValue) * barMaxHeight;
              final napH = (nap / maxValue) * barMaxHeight;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SizedBox(
                        height: valueLabelHeight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            total > 0 ? '${total.toStringAsFixed(1)}h' : '—',
                            style: TextStyle(
                              fontSize: 10,
                              color: isToday
                                  ? SleepTheme.primaryMid
                                  : SleepTheme.textSecondary,
                              fontWeight: isToday
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: spacing),
                      // stacked: nightly (main) + nap (thin overlay)
                      Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          Container(
                            width: double.infinity,
                            height: baseH,
                            decoration: BoxDecoration(
                              color: isToday
                                  ? SleepTheme.primaryMid
                                  : SleepTheme.primaryPale,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ),
                          if (nap > 0)
                            // use Positioned.fill with alignment so width is constrained to parent
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                width: double.infinity,
                                height: napH,
                                decoration: BoxDecoration(
                                  color: SleepTheme.info.withOpacity(0.6),
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(
            7,
            (i) => Expanded(
              child: Text(
                days[i],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: i == 6
                      ? SleepTheme.primaryMid
                      : SleepTheme.textSecondary,
                  fontWeight: i == 6 ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            _LegendSwatch(color: SleepTheme.primaryPale, label: 'Sleep'),
            SizedBox(width: 12),
            _LegendSwatch(color: SleepTheme.info, label: 'Nap'),
          ],
        ),
      ],
    );
  }

  Widget _buildSleepTips(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [SleepTheme.accentPale, SleepTheme.primaryPale],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb_outline,
                color: SleepTheme.accentPurple,
                size: 24,
              ),
              SizedBox(width: 12),
              Text(
                'Today\'s Sleep Tip',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: SleepTheme.textPrimary,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            'Your ideal sleep latency is around 10–20 minutes. If you’re consistently outside that range, consider adjusting caffeine timing and wind-down.',
            style: TextStyle(
              fontSize: 14,
              color: SleepTheme.textPrimary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ==== Live session controls (kept INSIDE the State) ====

  /// FIXED: make the button shrink-wrapped and height-bounded so it never requests infinite width in a Row
  Widget _buildStartStopButton() {
    return Obx(() {
      final active = controller.sessionActive.value;
      return IntrinsicWidth(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 0), // allow shrink in Row
          child: SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: controller.toggleSession,
              icon: Icon(active ? Icons.stop : Icons.play_arrow, size: 18),
              label: Text(active ? 'Stop' : 'Start'),
              style: ElevatedButton.styleFrom(
                // override any global theme that might be forcing infinity
                minimumSize: const Size(0, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                backgroundColor: active ? Colors.red : SleepTheme.primaryMid,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildSessionStatusChip() {
    return Obx(() {
      final active = controller.sessionActive.value;
      final status = controller
          .sessionStatus
          .value; // "Idle" | "Tracking…" | "Tracking (no audio)"
      final Color dot = active ? SleepTheme.success : SleepTheme.textSecondary;

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: SleepTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SleepTheme.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              status,
              style: const TextStyle(
                fontSize: 12,
                color: SleepTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _LegendSwatch extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendSwatch({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: SleepTheme.textSecondary),
        ),
      ],
    );
  }
}
