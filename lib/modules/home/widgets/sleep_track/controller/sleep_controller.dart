  import 'dart:async';
  import 'dart:math';
  import 'package:flutter_timezone/flutter_timezone.dart';

  import 'package:firebase_auth/firebase_auth.dart';
  import 'package:get/get.dart';
  import 'package:cloud_firestore/cloud_firestore.dart';
  import 'package:flutter/material.dart';

  // sensors
  import 'package:sensors_plus/sensors_plus.dart';
  import 'package:noise_meter/noise_meter.dart';
  import 'package:permission_handler/permission_handler.dart';

  // notifications + timezones
  import 'package:flutter_local_notifications/flutter_local_notifications.dart';
  import 'package:timezone/data/latest.dart' as tz;
  import 'package:timezone/timezone.dart' as tz;

  import '../models/sleep_model.dart';
  import '../screens/sleep_dashboard.dart';
  import '../screens/morning_checking_screen.dart';
  import '../screens/sleep_setup_screen_1.dart';

  class SleepController extends GetxController {
    final FirebaseFirestore _firestore = FirebaseFirestore.instance;

    // ---------------------- Observables ----------------------
    final Rx<UserData?> userData = Rx<UserData?>(null);
    final RxBool isLoading = false.obs;
    final RxString errorMessage = ''.obs;

    // Setup state
    final FlutterLocalNotificationsPlugin _notifications =
    FlutterLocalNotificationsPlugin();
    final Rx<Chronotype?> selectedChronotype = Rx<Chronotype?>(null);
    final RxString targetBedtime = '23:00'.obs;
    final RxString targetWake = '07:00'.obs;
    final RxInt calculatedDuration = 480.obs;
    final RxString durationWarning = ''.obs;

    // Live tracking state
    final RxBool sessionActive = false.obs;
    final RxString sessionStatus = 'Idle'.obs;
    final RxInt movementCount = 0.obs;
    final RxInt noiseSpikeCount = 0.obs;
    final RxDouble avgDb = 0.0.obs;

    // NEW: Real-time observables for dashboard
    final RxDouble noiseLevel = 0.0.obs;
    final RxBool isUserMoving = false.obs;

    DateTime? _sessionStart;
    StreamSubscription<AccelerometerEvent>? _accelSub;
    StreamSubscription<NoiseReading>? _noiseSub;
    NoiseMeter? _noiseMeter;
    int _dbSamples = 0;
    double _dbSum = 0;
    bool _isDisposed = false;
    bool _pausedContinuousForSession = false;
    String? _lastSensorsKey;

    // thresholds
    static const double _motionThreshold = 15.0;
    static const double _noiseSpikeDb = 55.0;

    @override
    void onInit() {
      super.onInit();
      _boot();
      _startContinuousSensorMonitoring();
    }

    Future<void> _boot() async {
      try {
        await initNotifications();
        await loadUserData();

        await rescheduleAllReminders();
      } catch (e) {
        debugPrint('Boot error: $e');
        errorMessage.value = 'Initialization failed: $e';
      }
    }

    @override
    void onClose() {
      _isDisposed = true;
      _cleanupSession();
      _stopContinuousSensorMonitoring();
      super.onClose();
    }

    void _cleanupSession() {
      _accelSub?.cancel();
      _accelSub = null;
      _noiseSub?.cancel();
      _noiseSub = null;
      _noiseMeter = null;
    }

    // NEW: Continuous sensor monitoring for dashboard display
    StreamSubscription<AccelerometerEvent>? _continuousAccelSub;
    StreamSubscription<NoiseReading>? _continuousNoiseSub;
    Timer? _motionResetTimer;

    void _startContinuousSensorMonitoring() async {
      final settings = userData.value?.sleepProfile?.trackingSettings;
      if (settings == null) {
        _stopContinuousSensorMonitoring();
        return;
      }

      // Build a key to detect changes
      final key = 'm:${settings.motionDetectionEnabled}|n:${settings.noiseDetectionEnabled}';
      if (_lastSensorsKey == key) return; // nothing changed → do nothing
      _lastSensorsKey = key;

      // Always stop old listeners before (re)starting
      _stopContinuousSensorMonitoring();

      // Motion
      if (settings.motionDetectionEnabled == true) {
        _continuousAccelSub = accelerometerEvents.listen((e) {
          if (_isDisposed) return;
          final mag = sqrt(e.x*e.x + e.y*e.y + e.z*e.z);
          if (mag > _motionThreshold) {
            isUserMoving.value = true;
            _motionResetTimer?.cancel();
            _motionResetTimer = Timer(const Duration(seconds: 2), () {
              isUserMoving.value = false;
            });
          }
        }, onError: (err) => debugPrint('Continuous accelerometer error: $err'));
      }

      // Noise
      if (settings.noiseDetectionEnabled == true) {
        final status = await Permission.microphone.status;
        if (status.isGranted) {
          try {
            _noiseMeter ??= NoiseMeter();
            _continuousNoiseSub = _noiseMeter!.noise.listen((reading) {
              if (_isDisposed) return;
              noiseLevel.value = reading.meanDecibel;
            }, onError: (err) => debugPrint('Continuous noise meter error: $err'));
          } catch (e) {
            debugPrint('Failed to start continuous noise monitoring: $e');
          }
        }
      }
    }


    void _stopContinuousSensorMonitoring() {
      _continuousAccelSub?.cancel();
      _continuousAccelSub = null;
      _continuousNoiseSub?.cancel();
      _continuousNoiseSub = null;
      _motionResetTimer?.cancel();
      _motionResetTimer = null;
    }

    // ---------------------- Auth ----------------------
    String get currentUserId {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        Get.snackbar(
          'Not signed in',
          'Please sign in to continue',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.withOpacity(0.8),
          colorText: Colors.white,
        );
        throw Exception('No authenticated user');
      }
      return uid;
    }

    // ---------------------- Routing Brain ----------------------
    bool get _inMorningWindow {
      final h = DateTime.now().hour;
      return h >= 6 && h <= 11;
    }

    bool get _inEveningWindow {
      final h = DateTime.now().hour;
      return h >= 17 && h <= 23;
    }

    Future<bool> _shouldPromptForLogNow() async {
      try {
        final todayMissing = !(await hasLogForDate(DateTime.now()));
        if (_inMorningWindow) return todayMissing;

        if (_inEveningWindow) {
          if (todayMissing) return true;
          final last = await _getMostRecentLogDate();
          if (last == null) return true;
          final today = DateTime.now();
          final todayStart = DateTime(today.year, today.month, today.day);
          final lastStart = DateTime(last.year, last.month, last.day);
          final daysAgo = todayStart.difference(lastStart).inDays;
          return daysAgo >= 2;
        }
        return false;
      } catch (e) {
        debugPrint('Error checking log prompt: $e');
        return false;
      }
    }

    Future<DateTime?> _getMostRecentLogDate() async {
      try {
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
      } catch (e) {
        debugPrint('Error getting recent log date: $e');
        return null;
      }
    }

    Future<void> openSleepFeature() async {
      if (isLoading.value) return; // Prevent multiple calls

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
      } catch (e) {
        debugPrint('Error opening sleep feature: $e');
        Get.snackbar(
          'Error',
          'Failed to open sleep feature',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.withOpacity(0.8),
          colorText: Colors.white,
        );
      } finally {
        isLoading.value = false;
      }
    }

    // ---------------------- Notifications ----------------------
    Future<void> initNotifications() async {

      final darwin = const DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const android = AndroidInitializationSettings('@mipmap/ic_launcher');

      final initSettings = InitializationSettings(
        android: android,
        iOS: darwin,
        macOS: darwin,
      );

      await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (details) {
          final payload = details.payload;
          if (payload == 'bedtime') {
            Get.to(() => const SleepDashboardScreen());
          } else if (payload == 'morning') {
            Get.to(() => const MorningCheckInScreen());
          }
        },
      );

      try {
        // Android 13+ runtime permission
        final notificationStatus = await Permission.notification.status;
        if (notificationStatus.isDenied || notificationStatus.isRestricted) {
          await Permission.notification.request();
        }

        tz.initializeTimeZones();

        // Use device local timezone with better fallback
        tz.initializeTimeZones();

        try {
          final String localName = (await FlutterTimezone.getLocalTimezone()) as String;
          tz.setLocalLocation(tz.getLocation(localName));
          debugPrint('Local timezone set: $localName');
        } catch (e) {
          debugPrint('Failed to get timezone, defaulting to UTC: $e');
          tz.setLocalLocation(tz.UTC);
        }

        const android = AndroidInitializationSettings('@mipmap/ic_launcher');
        const initSettings = InitializationSettings(android: android);
        await _notifications.initialize(
          initSettings,
          onDidReceiveNotificationResponse: (details) {
            debugPrint('Notification tapped: ${details.payload}');
          },
        );
      } catch (e) {
        debugPrint('Notification init error: $e');
      }
    }

    tz.TZDateTime _nextTimeTodayOrTomorrow(int hour, int minute) {
      final now = tz.TZDateTime.now(tz.local);
      var scheduled =
      tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
      if (scheduled.isBefore(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }
      return scheduled;
    }



    /// Schedule a bedtime reminder (daily at bedtime)
    Future<void> scheduleBedtimeReminder(String bedtimeHHmm) async {
      try {
        final parts = bedtimeHHmm.split(':');
        if (parts.length != 2) {
          debugPrint('Invalid bedtime format: $bedtimeHHmm');
          return;
        }

        final hour = int.tryParse(parts[0]);
        final minute = int.tryParse(parts[1]);

        if (hour == null || minute == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
          debugPrint('Invalid time values: $bedtimeHHmm');
          return;
        }

        await _notifications.zonedSchedule(
          100, // id
          "Bedtime Reminder",
          "Time to wind down for sleep 😴",
          _nextTimeTodayOrTomorrow(hour, minute),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'bedtime_channel',
              'Bedtime Reminders',
              channelDescription: 'Daily reminders for bedtime',
              importance: Importance.max,
              priority: Priority.high,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: 'bedtime'
        );
      } catch (e) {
        debugPrint('Error scheduling bedtime reminder: $e');
      }
    }

    /// Morning check-in reminder (daily 8:00 by default)
    Future<void> scheduleMorningReminder({int hour = 8, int minute = 0}) async {
      try {
        await _notifications.zonedSchedule(
          101, // id
          "Morning Check-In",
          "Don't forget to log last night's sleep 🌅",
          _nextTimeTodayOrTomorrow(hour, minute),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'morning_channel',
              'Morning Reminders',
              channelDescription: 'Daily morning check-in reminders',
              importance: Importance.max,
              priority: Priority.high,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: 'morning'
        );
      } catch (e) {
        debugPrint('Error scheduling morning reminder: $e');
      }
    }

    Future<void> cancelReminder(int id) async {
      try {
        await _notifications.cancel(id);
      } catch (e) {
        debugPrint('Error canceling reminder $id: $e');
      }
    }

    Future<void> rescheduleAllReminders() async {
      try {
        await cancelReminder(100);
        await cancelReminder(101);
        await scheduleBedtimeReminder(targetBedtime.value);
        await scheduleMorningReminder(); // 8:00 default
      } catch (e) {
        debugPrint('Error rescheduling reminders: $e');
      }
    }

    // ---------------------- Data Load ----------------------
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

            // Start/refresh monitoring only after setup is complete
            if (profile.setupCompleted == true) {
              _startContinuousSensorMonitoring(); // idempotent (see below)
            } else {
              _stopContinuousSensorMonitoring();
            }
          } else {
            _stopContinuousSensorMonitoring();
          }
        } else {
          errorMessage.value = 'User not found';
          _stopContinuousSensorMonitoring();
        }
        _startContinuousSensorMonitoring();
      } catch (e) {
        errorMessage.value = 'Error loading data: $e';
        debugPrint('Error loading user data: $e');
      } finally {
        isLoading.value = false;
      }
    }

    Stream<UserData?> streamUserData() {
      return _firestore
          .collection('Users')
          .doc(currentUserId)
          .snapshots()
          .map((doc) => doc.exists ? UserData.fromFirestore(doc) : null)
          .handleError((error) {
        debugPrint('Stream error: $error');
        return null;
      });
    }

    // ---------------------- Setup Helpers ----------------------
    void selectChronotype(Chronotype chronotype) {
      selectedChronotype.value = chronotype;
      final defaults = SleepProfile.getDefaultTimes(chronotype);
      targetBedtime.value = defaults['bedtime']!;
      targetWake.value = defaults['wake']!;
      calculateDuration();
    }

    void updateBedtime(TimeOfDay time) {
      targetBedtime.value = SleepTimeHelper.formatTimeOfDay(time);
      calculateDuration();
      // re-schedule bedtime reminder when user changes bedtime
      rescheduleAllReminders();
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
        Get.snackbar('Missing Information', 'Please select your sleep preference',
            snackPosition: SnackPosition.BOTTOM);
        return false;
      }
      return true;
    }

    // ---------------------- Save Profile / Logs ----------------------
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
            'setup_completed': true,
          }
        }, SetOptions(merge: true));

        await loadUserData();
        // make sure reminders reflect current targets
        await rescheduleAllReminders();
        return true;
      } catch (e) {
        debugPrint('Error saving sleep profile: $e');
        Get.snackbar(
          'Error',
          'Failed to save profile',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.withOpacity(0.8),
          colorText: Colors.white,
        );
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
        debugPrint('Error saving sleep log: $e');
        Get.snackbar(
          'Error',
          'Failed to save sleep log',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.withOpacity(0.8),
          colorText: Colors.white,
        );
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

    // ---------------------- Insights ----------------------
    Future<bool> hasLogForDate(DateTime date) async {
      try {
        final key = SleepTimeHelper.dayKey(date);
        final snap = await _firestore
            .collection('Users')
            .doc(currentUserId)
            .collection('sleep_logs')
            .doc(key)
            .get();
        return snap.exists;
      } catch (e) {
        debugPrint('Error checking log for date: $e');
        return false;
      }
    }

    Future<SleepLog?> getLogByDayKey(String dayKey) async {
      try {
        final snap = await _firestore
            .collection('Users')
            .doc(currentUserId)
            .collection('sleep_logs')
            .doc(dayKey)
            .get();
        if (!snap.exists) return null;
        return SleepLog.fromMap(snap.data() as Map<String, dynamic>);
      } catch (e) {
        debugPrint('Error getting log by day key: $e');
        return null;
      }
    }

    Future<SleepLog?> getMostRecentLog() async {
      try {
        final q = await _firestore
            .collection('Users')
            .doc(currentUserId)
            .collection('sleep_logs')
            .orderBy('date_iso', descending: true)
            .limit(1)
            .get();
        if (q.docs.isEmpty) return null;
        return SleepLog.fromMap(q.docs.first.data());
      } catch (e) {
        debugPrint('Error getting most recent log: $e');
        return null;
      }
    }

    Future<int> _avgSleepBetween(DateTime start, DateTime end) async {
      try {
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
      } catch (e) {
        debugPrint('Error calculating average sleep: $e');
        return 0;
      }
    }

    Future<int> getVsLastWeekDeltaMinutes() async {
      try {
        final today = DateTime.now();
        final endThis = DateTime(today.year, today.month, today.day);
        final startThis = endThis.subtract(const Duration(days: 6));
        final endLast = startThis.subtract(const Duration(days: 1));
        final startLast = endLast.subtract(const Duration(days: 6));

        final thisAvg = await _avgSleepBetween(startThis, endThis);
        final lastAvg = await _avgSleepBetween(startLast, endLast);
        return thisAvg - lastAvg;
      } catch (e) {
        debugPrint('Error calculating week delta: $e');
        return 0;
      }
    }

    Future<List<SleepLog>> getRecentLogs({int days = 7}) async {
      try {
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
      } catch (e) {
        debugPrint('Error getting recent logs: $e');
        return [];
      }
    }

    int computeSleepScore(SleepLog log, SleepProfile profile) {
      final target =
      (profile.targetDurationMinutes <= 0) ? 480 : profile.targetDurationMinutes;
      final total = (log.totalSleepMinutes ?? log.durationMinutes).clamp(0, 24 * 60);
      final ratio = total / target;
      final durScore = (100 * (ratio > 1 ? (2 - ratio) : ratio)).clamp(0.0, 100.0);
      final qualityScore = ((log.quality ?? 3) * 20).clamp(0, 100);
      final awak = (log.awakenings ?? 0).clamp(0, 4);
      final awakScore = [100, 85, 70, 55, 40][awak];
      final score = (0.60 * durScore) + (0.25 * qualityScore) + (0.15 * awakScore);
      return score.round().clamp(0, 100);
    }

    // ---------------------- Lifestyle / Tracking / Completion ----------------------
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
        debugPrint('Error saving lifestyle factors: $e');
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
        debugPrint('Error saving tracking settings: $e');
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
        await loadUserData();
        // ensure reminders are scheduled after setup
        await rescheduleAllReminders();
        return true;
      } catch (e) {
        debugPrint('Error completing setup: $e');
        return false;
      } finally {
        isLoading.value = false;
      }
    }

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
        // cancel reminders if resetting setup
        await cancelReminder(100);
        await cancelReminder(101);
      } catch (e) {
        debugPrint('Error resetting setup: $e');
      }
    }

    // ---------------------- Real-Time Session ----------------------
    Future<void> startSleepSession() async {

      if (_continuousNoiseSub != null || _continuousAccelSub != null) {
        _stopContinuousSensorMonitoring();
        _pausedContinuousForSession = true;
      }

      if (sessionActive.value) {
        debugPrint('Session already active');
        return;
      }

      // Check and request microphone permission
      final micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {
        final result = await Permission.microphone.request();
        if (!result.isGranted) {
          Get.snackbar(
            'Permission Required',
            'Microphone access is needed to track noise levels',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.orange.withOpacity(0.8),
            colorText: Colors.white,
          );
          // Continue without noise tracking
        }
      }

      _sessionStart = DateTime.now();
      movementCount.value = 0;
      noiseSpikeCount.value = 0;
      _dbSamples = 0;
      _dbSum = 0;
      avgDb.value = 0.0;

      // Motion tracking
      _accelSub = accelerometerEvents.listen(
            (e) {
          if (_isDisposed) return;
          final mag = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
          if (mag > _motionThreshold) {
            movementCount.value++;
          }
        },
        onError: (error) {
          debugPrint('Accelerometer error: $error');
        },
        cancelOnError: false,
      );

      // Noise tracking (only if permission granted)
      if (await Permission.microphone.isGranted) {
        try {
          _noiseMeter = NoiseMeter();
          _noiseSub = _noiseMeter!.noise.listen(
                (reading) {
              if (_isDisposed) return;
              final db = reading.meanDecibel;
              _dbSamples++;
              _dbSum += db;
              avgDb.value = _dbSum / _dbSamples;
              if (db > _noiseSpikeDb) {
                noiseSpikeCount.value++;
              }
            },
            onError: (error) {
              debugPrint('Noise meter error: $error');
              sessionStatus.value = "Tracking (no audio)";
            },
            cancelOnError: false,
          );
        } catch (e) {
          debugPrint('Failed to start noise meter: $e');
        }
      }

      sessionActive.value = true;
      sessionStatus.value = "Tracking…";
    }

    Future<SleepLog?> stopSleepSession({bool saveLog = true}) async {
      if (!sessionActive.value) {
        debugPrint('No active session to stop');
        return null;
      }

      _cleanupSession();
      sessionActive.value = false;
      sessionStatus.value = "Idle";

      // ✅ Resume continuous dashboard monitoring if we paused it for the session
      if (_pausedContinuousForSession) {
        _pausedContinuousForSession = false;
        _startContinuousSensorMonitoring();
      }

      final start = _sessionStart ?? DateTime.now();
      final end = DateTime.now();
      final durationMinutes = end.difference(start).inMinutes;

      // Don't save if session was too short (< 5 minutes)
      if (durationMinutes < 5) {
        Get.snackbar(
          'Session Too Short',
          'Sleep session must be at least 5 minutes',
          snackPosition: SnackPosition.BOTTOM,
        );
        return null;
      }

      final log = SleepLog(
        date: start,
        bedtimeHHmm: targetBedtime.value,
        wakeHHmm: SleepTimeHelper.formatTimeOfDay(TimeOfDay.fromDateTime(end)),
        durationMinutes: durationMinutes,
        totalSleepMinutes: (durationMinutes - 10).clamp(0, durationMinutes),
        quality: null,
        awakenings: (movementCount.value ~/ 40) + (noiseSpikeCount.value ~/ 20),
        sleepLatencyMinutes: 10,
        notes:
        "Auto log from sensors: moves=${movementCount.value}, spikes=${noiseSpikeCount.value}, avgDb=${avgDb.value.toStringAsFixed(1)}",
        wakeReasons: null,
      );

      if (saveLog) {
        final success = await saveSleepLog(log);
        if (!success) return null;
      }
      return log;
    }


    Future<void> toggleSession() async {
      if (sessionActive.value) {
        final log = await stopSleepSession(saveLog: true);
        if (log != null) {
          Get.snackbar(
            "Sleep Session Stopped",
            "Session saved successfully",
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.green.withOpacity(0.8),
            colorText: Colors.white,
          );
        }
      } else {
        await startSleepSession();
        Get.snackbar(
          "Sleep Session Started",
          "Tracking your sleep...",
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.blue.withOpacity(0.8),
          colorText: Colors.white,
        );
      }
    }
  }