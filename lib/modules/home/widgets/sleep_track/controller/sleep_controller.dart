import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/sleep_model.dart';
import '../screens/sleep_dashboard.dart';
import '../screens/morning_checking_screen.dart';
import '../screens/sleep_setup_screen_1.dart';

class SleepController extends GetxController {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Observable variables
  final Rx<UserData?> userData = Rx<UserData?>(null);
  final RxBool isLoading = false.obs;
  final RxString errorMessage = ''.obs;

  // Setup screen 1 state
  final Rx<Chronotype?> selectedChronotype = Rx<Chronotype?>(null);
  final RxString targetBedtime = '23:00'.obs;
  final RxString targetWake = '07:00'.obs;
  final RxInt calculatedDuration = 480.obs;
  final RxString durationWarning = ''.obs;

  @override
  void onInit() {
    super.onInit();
    loadUserData();
  }

  /// Get current user ID
  String get currentUserId {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      Get.snackbar(
        'Not signed in',
        'Please sign in to continue',
        snackPosition: SnackPosition.BOTTOM,
      );
      throw Exception('No authenticated user');
    }
    return uid;
  }

  // ---------------------- ROUTING BRAIN ----------------------

  bool get _inMorningWindow {
    final h = DateTime.now().hour;
    return h >= 6 && h <= 11;
  }

  bool get _inEveningWindow {
    final h = DateTime.now().hour;
    return h >= 17 && h <= 23;
  }

  /// Decide whether we should prompt a log right now
  Future<bool> _shouldPromptForLogNow() async {
    final todayMissing = !(await hasLogForDate(DateTime.now()));

    if (_inMorningWindow) {
      return todayMissing;
    }

    if (_inEveningWindow) {
      if (todayMissing) return true;

      // If last log is older than yesterday, prompt.
      final last = await _getMostRecentLogDate();
      if (last == null) return true;
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final lastStart = DateTime(last.year, last.month, last.day);
      final daysAgo = todayStart.difference(lastStart).inDays;
      return daysAgo >= 2;
    }

    // midday: keep it lightweight (no prompt)
    return false;
  }

  Future<DateTime?> _getMostRecentLogDate() async {
    final q = await _firestore
        .collection('Users')
        .doc(currentUserId)
        .collection('sleep_logs')
        .orderBy('date_iso', descending: true)
        .limit(1)
        .get();

    if (q.docs.isEmpty) return null;
    final iso = q.docs.first.data()['date_iso'] as String?;
    if (iso == null) return null;
    final dt = DateTime.parse(iso).toLocal();
    return DateTime(dt.year, dt.month, dt.day);
  }

  /// Entry point to open the feature
  Future<void> openSleepFeature() async {
    try {
      isLoading.value = true;
      await loadUserData();
      final profile = userData.value?.sleepProfile;

      if (profile == null || profile.setupCompleted != true) {
        Get.to(() => const SleepSetupScreen1());
        return;
      }

      final promptNow = await _shouldPromptForLogNow();
      if (promptNow) {
        Get.to(() => const MorningCheckInScreen());
      } else {
        Get.to(() => const SleepDashboardScreen());
      }
    } finally {
      isLoading.value = false;
    }
  }

  // ---------------------- DATA LOAD / STREAM ----------------------

  Future<void> loadUserData() async {
    try {
      isLoading.value = true;
      errorMessage.value = '';

      final doc = await _firestore.collection('Users').doc(currentUserId).get();

      if (doc.exists) {
        userData.value = UserData.fromFirestore(doc);
        final profile = userData.value?.sleepProfile;
        if (profile != null) {
          selectedChronotype.value = profile.chronotype;
          targetBedtime.value = profile.targetBedtime;
          targetWake.value = profile.targetWake;
          calculateDuration();
        }
      } else {
        errorMessage.value = 'User not found';
      }
    } catch (e) {
      errorMessage.value = 'Error loading data: $e';
      // ignore: avoid_print
      print('Error loading user data: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Stream<UserData?> streamUserData() {
    return _firestore
        .collection('Users')
        .doc(currentUserId)
        .snapshots()
        .map((doc) => doc.exists ? UserData.fromFirestore(doc) : null);
  }

  // ---------------------- SETUP SCREEN 1 HELPERS ----------------------

  void selectChronotype(Chronotype chronotype) {
    selectedChronotype.value = chronotype;
    final defaults = SleepProfile.getDefaultTimes(chronotype);
    targetBedtime.value = defaults['bedtime']!;
    targetWake.value = defaults['wake']!;
    calculateDuration();

    Get.snackbar(
      'Sleep Rhythm Updated',
      'Times adjusted to match your ${chronotype.label}',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
      backgroundColor: const Color(0xFFE8EAF6),
      colorText: Colors.black87,
      icon: const Icon(Icons.check_circle, color: Color(0xFF3949AB)),
    );
  }

  void updateBedtime(TimeOfDay time) {
    targetBedtime.value = SleepTimeHelper.formatTimeOfDay(time);
    calculateDuration();
  }

  void updateWakeTime(TimeOfDay time) {
    targetWake.value = SleepTimeHelper.formatTimeOfDay(time);
    calculateDuration();
  }

  void calculateDuration() {
    calculatedDuration.value = SleepTimeHelper.calculateDurationMinutes(
      targetBedtime.value,
      targetWake.value,
    );
    durationWarning.value =
        SleepTimeHelper.validateDuration(calculatedDuration.value) ?? '';
  }

  bool validateScreen1() {
    if (selectedChronotype.value == null) {
      Get.snackbar(
        'Missing Information',
        'Please select your sleep preference',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFFFFEBEE),
        colorText: Colors.black87,
        icon: const Icon(Icons.error_outline, color: Color(0xFFEF5350)),
      );
      return false;
    }
    return true;
  }

  // ---------------------- SAVE PROFILE / LOGS ----------------------

  Future<bool> saveSleepProfile() async {
    if (!validateScreen1()) return false;

    try {
      isLoading.value = true;

      await _firestore.collection('Users').doc(currentUserId).set({
        'sleep_profile': {
          'chronotype': selectedChronotype.value!.value,
          'target_bedtime': targetBedtime.value,
          'target_wake': targetWake.value,
          'target_duration_minutes': calculatedDuration.value,
          'updated_at': DateTime.now().toIso8601String(),
          // optional convenience if you want setup_done right after screen 1:
          'setup_completed': true,
        }
      }, SetOptions(merge: true));

      await loadUserData();
      return true;
    } catch (e) {
      Get.snackbar('Error', 'Failed to save: $e',
          snackPosition: SnackPosition.BOTTOM);
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> saveSleepLog(SleepLog log) async {
    try {
      isLoading.value = true;

      await _firestore
          .collection('Users')
          .doc(currentUserId)
          .collection('sleep_logs')
          .doc(log.dayKey)
          .set(log.toMap(), SetOptions(merge: true));

      return true;
    } catch (e) {
      Get.snackbar('Error', 'Failed to save log: $e',
          snackPosition: SnackPosition.BOTTOM);
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> saveSleepLogFromTimes({
    required String bedtimeHHmm,
    required String wakeHHmm,
    DateTime? date,
    int? totalSleepMinutes,
    int? quality,
    int? awakenings,
    int? sleepLatencyMinutes,
    String? notes,
    List<String>? wakeReasons,
  }) async {
    final d = date ?? DateTime.now();
    final duration =
    SleepTimeHelper.calculateDurationMinutes(bedtimeHHmm, wakeHHmm);

    final log = SleepLog(
      date: d,
      bedtimeHHmm: bedtimeHHmm,
      wakeHHmm: wakeHHmm,
      durationMinutes: duration,
      totalSleepMinutes: totalSleepMinutes,
      quality: quality,
      awakenings: awakenings,
      sleepLatencyMinutes: sleepLatencyMinutes,
      notes: notes,
      wakeReasons: wakeReasons,
    );
    return saveSleepLog(log);
  }

  Stream<List<SleepLog>> streamRecentLogs({int limit = 30}) {
    return _firestore
        .collection('Users')
        .doc(currentUserId)
        .collection('sleep_logs')
        .orderBy('date_iso', descending: true)
        .limit(limit)
        .snapshots()
        .map((qs) => qs.docs.map((d) => SleepLog.fromMap(d.data())).toList());
  }

  Future<bool> hasLogForDate(DateTime date) async {
    final key = SleepTimeHelper.dayKey(date);
    final snap = await _firestore
        .collection('Users')
        .doc(currentUserId)
        .collection('sleep_logs')
        .doc(key)
        .get();
    return snap.exists;
  }

  // ---------------------- DASHBOARD / INSIGHTS HELPERS ----------------------

  Future<SleepLog?> getLogByDayKey(String dayKey) async {
    final snap = await _firestore
        .collection('Users')
        .doc(currentUserId)
        .collection('sleep_logs')
        .doc(dayKey)
        .get();
    if (!snap.exists) return null;
    return SleepLog.fromMap(snap.data() as Map<String, dynamic>);
  }

  Future<SleepLog?> getMostRecentLog() async {
    final q = await _firestore
        .collection('Users')
        .doc(currentUserId)
        .collection('sleep_logs')
        .orderBy('date_iso', descending: true)
        .limit(1)
        .get();

    if (q.docs.isEmpty) return null;
    return SleepLog.fromMap(q.docs.first.data());
  }

  Future<int> _avgSleepBetween(DateTime start, DateTime end) async {
    final from = DateTime(start.year, start.month, start.day).toIso8601String();
    final toExclusive = DateTime(end.year, end.month, end.day)
        .add(const Duration(days: 1))
        .toIso8601String();

    final q = await _firestore
        .collection('Users')
        .doc(currentUserId)
        .collection('sleep_logs')
        .where('date_iso', isGreaterThanOrEqualTo: from)
        .where('date_iso', isLessThan: toExclusive)
        .get();

    if (q.docs.isEmpty) return 0;

    int sum = 0;
    for (final d in q.docs) {
      final m = d.data();
      final int? total = m['total_sleep_minutes'] as int?;
      final int? dur = m['duration_minutes'] as int?;
      sum += (total ?? dur ?? 0);
    }
    return (sum / q.docs.length).round();
  }

  Future<int> getVsLastWeekDeltaMinutes() async {
    final today = DateTime.now();
    final endThis = DateTime(today.year, today.month, today.day);
    final startThis = endThis.subtract(const Duration(days: 6));

    final endLast = startThis.subtract(const Duration(days: 1));
    final startLast = endLast.subtract(const Duration(days: 6));

    final thisAvg = await _avgSleepBetween(startThis, endThis);
    final lastAvg = await _avgSleepBetween(startLast, endLast);

    return thisAvg - lastAvg;
  }

  Future<List<SleepLog>> getRecentLogs({int days = 7}) async {
    final cutoff = DateTime.now().subtract(Duration(days: days + 1));
    final q = await _firestore
        .collection('Users')
        .doc(currentUserId)
        .collection('sleep_logs')
        .where('date_iso',
        isGreaterThanOrEqualTo: cutoff.toUtc().toIso8601String())
        .orderBy('date_iso', descending: false)
        .get();

    return q.docs.map((d) => SleepLog.fromMap(d.data())).toList();
  }

  int computeSleepScore(SleepLog log, SleepProfile profile) {
    final target =
    (profile.targetDurationMinutes <= 0) ? 480 : profile.targetDurationMinutes;

    final total =
    (log.totalSleepMinutes ?? log.durationMinutes).clamp(0, 24 * 60);
    final ratio = total / target;

    final durScore =
    (100 * (ratio > 1 ? (2 - ratio) : ratio)).clamp(0.0, 100.0);
    final qualityScore = ((log.quality ?? 3) * 20).clamp(0, 100);
    final awak = (log.awakenings ?? 0).clamp(0, 4);
    final awakScore = [100, 85, 70, 55, 40][awak];

    final score =
        (0.60 * durScore) + (0.25 * qualityScore) + (0.15 * awakScore);
    return score.round().clamp(0, 100);
  }

  // ---------------------- LIFESTYLE / TRACKING / COMPLETION ----------------------

  Future<bool> saveLifestyleFactors(LifestyleFactors lifestyle) async {
    try {
      isLoading.value = true;
      await _firestore.collection('Users').doc(currentUserId).set({
        'sleep_profile': {
          'lifestyle': lifestyle.toMap(),
          'updated_at': DateTime.now().toIso8601String(),
        }
      }, SetOptions(merge: true));

      await loadUserData();
      return true;
    } catch (e) {
      Get.snackbar('Error', 'Failed to save: $e',
          snackPosition: SnackPosition.BOTTOM);
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> saveTrackingSettings(TrackingSettings settings) async {
    try {
      isLoading.value = true;
      await _firestore.collection('Users').doc(currentUserId).set({
        'sleep_profile': {
          'tracking_settings': settings.toMap(),
          'updated_at': DateTime.now().toIso8601String(),
        }
      }, SetOptions(merge: true));

      await loadUserData();
      return true;
    } catch (e) {
      Get.snackbar('Error', 'Failed to save: $e',
          snackPosition: SnackPosition.BOTTOM);
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> completeSetup() async {
    try {
      isLoading.value = true;
      await _firestore.collection('Users').doc(currentUserId).set({
        'sleep_profile': {
          'setup_completed': true,
          'setup_completed_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        }
      }, SetOptions(merge: true));

      Get.snackbar(
        'Setup Complete! 🎉',
        'Your sleep tracking is now active',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFFE8EAF6),
        colorText: Colors.black87,
        duration: const Duration(seconds: 3),
        icon: const Icon(Icons.bedtime, color: Color(0xFF3949AB)),
      );

      await loadUserData();
      return true;
    } catch (e) {
      Get.snackbar('Error', 'Failed to complete setup: $e',
          snackPosition: SnackPosition.BOTTOM);
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  // ---------------------- RESET ----------------------

  bool get isSetupCompleted =>
      userData.value?.sleepProfile?.setupCompleted ?? false;

  Future<void> resetSetup() async {
    try {
      await _firestore.collection('Users').doc(currentUserId).update({
        'sleep_profile': FieldValue.delete(),
      });
      await loadUserData();
      selectedChronotype.value = null;
      targetBedtime.value = '23:00';
      targetWake.value = '07:00';
      calculateDuration();
    } catch (e) {
      // ignore: avoid_print
      print('Error resetting setup: $e');
    }
  }
}
