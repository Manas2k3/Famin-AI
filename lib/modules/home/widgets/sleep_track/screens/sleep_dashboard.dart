import 'package:cloud_firestore/cloud_firestore.dart';
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

  @override
  void initState() {
    super.initState();
    // Prompt the morning bottom sheet once after first frame
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

  /// Show bottom sheet (one time) if in morning window and log missing
  Future<void> _maybePromptMorning() async {
    if (_prompted) return;
    _prompted = true;

    final now = DateTime.now();
    // Morning window; tweak to your exact rule (e.g., 7:00–11:00)
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
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Good morning ☀️",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
    );
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SleepTheme.background,
      appBar: AppBar(
        title: const Text('Sleep Tracking'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Get.snackbar(
                'Settings',
                'Sleep settings coming soon',
                snackPosition: SnackPosition.BOTTOM,
                backgroundColor: SleepTheme.primaryPale,
                colorText: SleepTheme.textPrimary,
              );
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
          onRefresh: controller.loadUserData,
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
                    final missing = snap.connectionState == ConnectionState.done &&
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

                // Hero Sleep Score Card (real data)
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


                // Consistency & Debt Cards (placeholder logic)
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
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Here\'s your sleep summary',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: SleepTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildHeroCard(BuildContext context, SleepProfile sleepProfile,
      {SleepLog? log}) {
    // Real score and values if log exists
    final int sleepScore = (log != null)
        ? controller.computeSleepScore(log, sleepProfile)
        : 0;

    final int durationMin =
        (log?.totalSleepMinutes ?? log?.durationMinutes) ?? 0;
    final String duration = durationMin > 0
        ? "${durationMin ~/ 60}h ${durationMin % 60}m"
        : '--';

    final int awakenings = log?.awakenings ?? 0;

    final String bedtime = log?.bedtimeHHmm ?? sleepProfile.targetBedtime;
    final String wake = log?.wakeHHmm ?? sleepProfile.targetWake;

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
                  valueColor:
                  const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              Column(
                children: [
                  Text(
                    log != null ? sleepScore.toString() : '—',
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Text(
                    'Sleep Score',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
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
            padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMiniStat(log != null ? '✅' : '—', 'On time'),
                _buildMiniStat(
                    log != null
                        ? '${_approxEfficiency(durationMin, log)}%'
                        : '—',
                    'Efficiency'),
                _buildMiniStat(
                    log != null ? '$awakenings' : '—', 'Awakenings'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Time range
          Text(
            'In bed: $bedtime → Awake: $wake',
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
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickStats(BuildContext context, {SleepLog? mostRecent}) {
    // Derive values from the most recent log if available
    final int? latencyMin = mostRecent?.sleepLatencyMinutes;

    final int? durationMin = mostRecent?.durationMinutes;
    final int? estTotalMin = (mostRecent == null)
        ? null
        : (mostRecent.totalSleepMinutes ??
        ((mostRecent.durationMinutes) -
            (mostRecent.sleepLatencyMinutes ?? 0)))
        .clamp(0, mostRecent.durationMinutes);

    final int? awakeMin = (durationMin != null && estTotalMin != null)
        ? (durationMin - estTotalMin).clamp(0, durationMin)
        : null;

    String fmtMins(int? m) {
      if (m == null) return '—';
      if (m < 60) return '${m} min';
      final h = m ~/ 60, mm = m % 60;
      return mm == 0 ? '${h}h' : '${h}h ${mm}m';
      // If you prefer always-minutes for these small stats, use: '${m} min'
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
              final has = snap.connectionState == ConnectionState.done && snap.hasData;
              final deltaMin = has ? snap.data!.clamp(-24 * 60, 24 * 60) : 0;
              final sign = deltaMin > 0 ? '+' : (deltaMin < 0 ? '−' : '');
              final absMin = deltaMin.abs();
              final value = has ? '$sign$absMin min' : '—';

              final icon = deltaMin >= 0 ? Icons.trending_up : Icons.trending_down;
              final color = deltaMin >= 0 ? SleepTheme.success : SleepTheme.warning;

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
          const Icon(
            Icons.calendar_today,
            color: SleepTheme.info,
            size: 20,
          ),
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
            child: LinearProgressIndicator(
              value: 0.78,
              backgroundColor: SleepTheme.primaryPale,
              valueColor: const AlwaysStoppedAnimation(SleepTheme.info),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Last 7 days',
            style: TextStyle(
              fontSize: 11,
              color: SleepTheme.textSecondary,
            ),
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
            padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            style: TextStyle(
              fontSize: 11,
              color: SleepTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCyclePhaseCard(BuildContext context, UserData userData) {
    // Calculate cycle phase
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
          colors: [
            phaseColor.withOpacity(0.1),
            phaseColor.withOpacity(0.05),
          ],
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
                  Get.snackbar(
                    'Wind Down',
                    'Evening routine coming soon',
                    snackPosition: SnackPosition.BOTTOM,
                    backgroundColor: SleepTheme.primaryPale,
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
                onTap: () {
                  Get.to(() => const MorningCheckInScreen());
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
                onTap: () {
                  Get.snackbar(
                    'Log Nap',
                    'Nap tracking coming soon',
                    snackPosition: SnackPosition.BOTTOM,
                    backgroundColor: SleepTheme.accentPale,
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
                onTap: () {
                  Get.snackbar(
                    'Insights',
                    'Detailed insights coming soon',
                    snackPosition: SnackPosition.BOTTOM,
                    backgroundColor: SleepTheme.info.withOpacity(0.2),
                  );
                },
              ),
            ),
          ],
        ),
      ],
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
      BuildContext context, List<SleepLog> logs, SleepProfile profile) {
    // Build last 7 calendar days (oldest..today)
    final now = DateTime.now();
    final last7 = List.generate(
      7,
          (i) => DateTime(now.year, now.month, now.day).subtract(
        Duration(days: 6 - i),
      ),
    );

    // Map dayKey -> hours
    final hoursByKey = <String, double>{};
    for (final l in logs) {
      final mins = (l.totalSleepMinutes ?? l.durationMinutes);
      hoursByKey[SleepTimeHelper.dayKey(l.date)] = mins / 60.0;
    }

    final data = last7
        .map((d) => hoursByKey[_dayKey(d)] ?? 0.0)
        .toList(growable: false);
    final labels = last7.map(_weekdayLabel).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
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
          child: _buildSimpleChartFrom(data, labels),
        ),
      ],
    );
  }

  String _weekdayLabel(DateTime d) {
    const names = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return names[d.weekday % 7];
  }

  Widget _buildSimpleChartFrom(List<double> data, List<String> days) {
    // pick a dynamic max that doesn't crush tiny bars
    final maxData = data.isEmpty ? 8.0 : data.reduce((a, b) => a > b ? a : b);
    final maxValue = maxData < 6.0 ? 6.0 : (maxData > 10.0 ? 10.0 : maxData);

    // Layout constants
    const double chartHeight = 150; // total box height for bars + value label
    const double valueLabelHeight = 16; // rough text height
    const double spacing = 4; // gap between value label and bar
    final double barMaxHeight = chartHeight - valueLabelHeight - spacing;

    return Column(
      children: [
        SizedBox(
          height: chartHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(7, (index) {
              final value = index < data.length ? data[index] : 0.0;
              final barHeight =
                  ((value <= 0 ? 0.05 : value) / maxValue) * barMaxHeight;
              final isToday = index == 6;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Reserve a fixed box for the value text so total stays within chartHeight
                      SizedBox(
                        height: valueLabelHeight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            value > 0 ? '${value.toStringAsFixed(1)}h' : '—',
                            style: TextStyle(
                              fontSize: 10,
                              color: isToday
                                  ? SleepTheme.primaryMid
                                  : SleepTheme.textSecondary,
                              fontWeight:
                              isToday ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: spacing),
                      Container(
                        width: double.infinity,
                        height: barHeight,
                        decoration: BoxDecoration(
                          color: isToday
                              ? SleepTheme.primaryMid
                              : SleepTheme.primaryPale,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4)),
                        ),
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
                (index) => Expanded(
              child: Text(
                days[index],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: index == 6
                      ? SleepTheme.primaryMid
                      : SleepTheme.textSecondary,
                  fontWeight:
                  index == 6 ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSleepTips(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            SleepTheme.accentPale,
            SleepTheme.primaryPale,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
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
}
