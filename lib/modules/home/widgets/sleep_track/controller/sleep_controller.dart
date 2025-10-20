import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart';
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
import 'package:shared_preferences/shared_preferences.dart';
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

  // Notifications
  final RxString morningReminderHHmm = '08:00'.obs;

  // thresholds
  static const double _motionThreshold = 15.0;
  static const double _noiseSpikeDb = 55.0;
  static const _kSessionActive = 'sleep_session_active';
  static const _kSessionStartIso = 'sleep_session_start_iso';

  // --- WIND DOWN ---
  final RxBool windDownActive = false.obs;
  final RxInt  windDownRemaining = 0.obs;   // seconds left
  Timer? _windDownTimer;

  // --- NAP SESSION ---
  final RxBool napActive = false.obs;
  final RxInt  napElapsed = 0.obs;          // seconds since start
  DateTime? _napStart;
  Timer? _napTimer;

  @override
  void onInit() {
    super.onInit();
    _boot();
    _startContinuousSensorMonitoring();
  }

  // ✅ FIX 4: Changed order - loadUserData → _restoreSessionIfAny → rescheduleAllReminders
  Future<void> _boot() async {
    try {
      await initNotifications();
      await loadUserData(); // Load first
      await _restoreSessionIfAny(); // Then restore session
      await rescheduleAllReminders(); // Then schedule
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
    final key =
        'm:${settings.motionDetectionEnabled}|n:${settings.noiseDetectionEnabled}';
    if (_lastSensorsKey == key) return; // nothing changed → do nothing
    _lastSensorsKey = key;

    // Always stop old listeners before (re)starting
    _stopContinuousSensorMonitoring();

    // Motion
    if (settings.motionDetectionEnabled == true) {
      _continuousAccelSub = accelerometerEvents.listen((e) {
        if (_isDisposed) return;
        final mag = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
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
          _continuousNoiseSub = _noiseMeter!.noise.listen(
                (reading) {
              if (_isDisposed) return;
              noiseLevel.value = reading.meanDecibel;
            },
            onError: (err) => debugPrint('Continuous noise meter error: $err'),
          );
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
  // ✅ FIX 3: Added notification permission check with proper handling
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
      // ✅ FIX 6: Added 'winddown_complete' payload handling
      onDidReceiveNotificationResponse: (details) async {
        final payload = details.payload;
        if (payload == 'bedtime') {
          Get.to(() => const SleepDashboardScreen());
        } else if (payload == 'morning') {
          Get.to(() => const MorningCheckInScreen());
        } else if (payload == 'auto_stop') {
          if (sessionActive.value) {
            await stopSleepSession(saveLog: true);
            Get.snackbar(
              'Session Stopped',
              'Good morning! Session ended.',
              snackPosition: SnackPosition.BOTTOM,
            );
          } else {
            Get.to(() => const MorningCheckInScreen());
          }
        } else if (payload == 'winddown_complete') {
          Get.to(() => const SleepDashboardScreen());
        }
      },
    );

    try {
      // ✅ FIX 3: Improved notification permission handling
      final notificationStatus = await Permission.notification.status;
      if (notificationStatus.isDenied || notificationStatus.isRestricted) {
        final result = await Permission.notification.request();
        if (!result.isGranted) {
          debugPrint('⚠️ Notification permission denied - reminders will not work');
          // Don't throw error, just log it
        }
      }

      tz.initializeTimeZones();

      try {
        final String localName =
        (await FlutterTimezone.getLocalTimezone()) as String;
        tz.setLocalLocation(tz.getLocation(localName));
        debugPrint('Local timezone set: $localName');
      } catch (e) {
        debugPrint('Failed to get timezone, defaulting to UTC: $e');
        tz.setLocalLocation(tz.UTC);
      }
    } catch (e) {
      debugPrint('Notification init error: $e');
    }
  }

  tz.TZDateTime _nextTimeTodayOrTomorrow(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
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

      if (hour == null ||
          minute == null ||
          hour < 0 ||
          hour > 23 ||
          minute < 0 ||
          minute > 59) {
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
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: 'bedtime',
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
        payload: 'morning',
      );
    } catch (e) {
      debugPrint('Error scheduling morning reminder: $e');
    }
  }

  /// ✅ FIX 1: Auto-stop at user's wake time (uses ID 200)
  Future<void> _scheduleAutoStopAtWake() async {
    final parts = targetWake.value.split(':');
    final wh = int.parse(parts[0]);
    final wm = int.parse(parts[1]);

    try {
      await _notifications.zonedSchedule(
        200, // Auto-stop at wake time
        'Morning',
        'Tap to stop sleep session and log your night 🌅',
        _nextTimeTodayOrTomorrow(wh, wm),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'auto_stop_channel',
            'Auto Stop',
            channelDescription: 'Stops sleep session at wake time',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: 'auto_stop',
      );
    } on PlatformException catch (e) {
      if (e.code == 'exact_alarms_not_permitted') {
        // Fallback to inexact
        await _notifications.zonedSchedule(
          200,
          'Morning',
          'Tap to stop sleep session and log your night 🌅',
          _nextTimeTodayOrTomorrow(wh, wm),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'auto_stop_channel',
              'Auto Stop',
              channelDescription: 'Stops sleep session at wake time',
              importance: Importance.max,
              priority: Priority.high,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: 'auto_stop',
        );
      } else {
        rethrow;
      }
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

      final parts = morningReminderHHmm.value.split(':');
      final mh = int.parse(parts[0]);
      final mm = int.parse(parts[1]);
      await scheduleMorningReminder(hour: mh, minute: mm);
      await scheduleWindDownReminder(targetBedtime.value);

    } catch (e) {
      debugPrint('Error rescheduling reminders: $e');
    }
  }

  // Persist on start/stop
  Future<void> _persistSessionState({
    required bool active,
    DateTime? start,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kSessionActive, active);
    if (active) {
      await p.setString(
        _kSessionStartIso,
        (start ?? DateTime.now()).toIso8601String(),
      );
    } else {
      await p.remove(_kSessionStartIso);
    }
  }

  // Restore after cold start
  Future<void> _restoreSessionIfAny() async {
    try {
      final p = await SharedPreferences.getInstance();
      final wasActive = p.getBool(_kSessionActive) ?? false;
      final iso = p.getString(_kSessionStartIso);

      if (!wasActive || iso == null) return;

      // Re-create state
      _sessionStart = DateTime.tryParse(iso) ?? DateTime.now();
      sessionActive.value = true;
      sessionStatus.value = "Tracking…";

      // Restart listeners
      _accelSub?.cancel();
      _accelSub = accelerometerEvents.listen((e) {
        if (_isDisposed) return;
        final mag = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
        if (mag > _motionThreshold) {
          movementCount.value++;
        }
      }, onError: (err) => debugPrint('Accelerometer restore error: $err'));

      if (await Permission.microphone.isGranted) {
        try {
          _noiseMeter ??= NoiseMeter();
          _noiseSub?.cancel();
          _noiseSub = _noiseMeter!.noise.listen((reading) {
            if (_isDisposed) return;
            final db = reading.meanDecibel;
            _dbSamples++;
            _dbSum += db;
            avgDb.value = _dbSum / _dbSamples;
            if (db > _noiseSpikeDb) {
              noiseSpikeCount.value++;
            }
          }, onError: (_) => sessionStatus.value = "Tracking (no audio)");
        } catch (e) {
          debugPrint('Noise restore error: $e');
        }
      }
    } catch (e) {
      debugPrint('Restore session error: $e');
    }
  }

  // ---------------------- Data Load ----------------------
  // ✅ FIX 2: Removed duplicate sensor start at the end
  Future<void> loadUserData() async {
    try {
      isLoading.value = true;
      errorMessage.value = '';
      final doc = await _firestore.collection('Users').doc(currentUserId).get();

      if (doc.exists) {
        userData.value = UserData.fromFirestore(doc);
        final profile = userData.value?.sleepProfile;
        if (profile != null) {
          final hhmm = profile.morningReminderHHmm;
          if (hhmm != null && hhmm.isNotEmpty) {
            morningReminderHHmm.value = hhmm;
            selectedChronotype.value = profile.chronotype;
            targetBedtime.value = profile.targetBedtime;
            targetWake.value = profile.targetWake;
            morningReminderHHmm.value = profile.morningReminderHHmm ?? '08:00';
            calculateDuration();

            // Start/refresh monitoring only after setup is complete
            if (profile.setupCompleted == true) {
              _startContinuousSensorMonitoring();
            } else {
              _stopContinuousSensorMonitoring();
            }
          }
        } else {
          _stopContinuousSensorMonitoring();
        }
      } else {
        errorMessage.value = 'User not found';
        _stopContinuousSensorMonitoring();
      }
      // ✅ FIX 2: REMOVED duplicate _startContinuousSensorMonitoring() here
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
    rescheduleAllReminders();
  }

  void updateWakeTime(TimeOfDay time) {
    targetWake.value = SleepTimeHelper.formatTimeOfDay(time);
    calculateDuration();
  }

  Future<void> updateMorningReminder(TimeOfDay time) async {
    final newValue = SleepTimeHelper.formatTimeOfDay(time);
    if (morningReminderHHmm.value == newValue) return;

    final prev = morningReminderHHmm.value;
    morningReminderHHmm.value = newValue;

    try {
      await _firestore.collection('Users').doc(currentUserId).set({
        'sleep_profile': {
          'morning_reminder_hhmm': newValue,
          'updated_at': DateTime.now().toIso8601String(),
        },
      }, SetOptions(merge: true));

      await scheduleMorningReminder(
        hour: int.parse(morningReminderHHmm.value.split(':')[0]),
        minute: int.parse(morningReminderHHmm.value.split(':')[1]),
      );
    } catch (e) {
      morningReminderHHmm.value = prev;
      debugPrint('Failed to update morning reminder: $e');
      Get.snackbar(
        'Save Failed',
        'Couldn\'t update your morning reminder. Please try again.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
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
      );
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
          'morning_reminder_hhmm': morningReminderHHmm.value,
          'target_duration_minutes': calculatedDuration.value,
          'updated_at': DateTime.now().toIso8601String(),
          'setup_completed': true,
        },
      }, SetOptions(merge: true));

      await loadUserData();
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
    final duration = SleepTimeHelper.calculateDurationMinutes(
      bedtimeHHmm,
      wakeHHmm,
    );
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
      final from = DateTime(
        start.year,
        start.month,
        start.day,
      ).toIso8601String();
      final toExclusive = DateTime(
        end.year,
        end.month,
        end.day,
      ).add(const Duration(days: 1)).toIso8601String();

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
          .where(
        'date_iso',
        isGreaterThanOrEqualTo: cutoff.toUtc().toIso8601String(),
      )
          .orderBy('date_iso', descending: false)
          .get();
      return q.docs.map((d) => SleepLog.fromMap(d.data())).toList();
    } catch (e) {
      debugPrint('Error getting recent logs: $e');
      return [];
    }
  }

  int computeSleepScore(SleepLog log, SleepProfile profile) {
    final target = (profile.targetDurationMinutes <= 0)
        ? 480
        : profile.targetDurationMinutes;
    final total = (log.totalSleepMinutes ?? log.durationMinutes).clamp(
      0,
      24 * 60,
    );
    final ratio = total / target;
    final durScore = (100 * (ratio > 1 ? (2 - ratio) : ratio)).clamp(
      0.0,
      100.0,
    );
    final qualityScore = ((log.quality ?? 3) * 20).clamp(0, 100);
    final awak = (log.awakenings ?? 0).clamp(0, 4);
    final awakScore = [100, 85, 70, 55, 40][awak];
    final score =
        (0.60 * durScore) + (0.25 * qualityScore) + (0.15 * awakScore);
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
        },
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
        },
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
        },
      }, SetOptions(merge: true));
      await loadUserData();
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
      }
    }

    _sessionStart = DateTime.now();
    movementCount.value = 0;
    noiseSpikeCount.value = 0;
    _dbSamples = 0;
    _dbSum = 0;
    avgDb.value = 0.0;

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
    await _scheduleAutoStopAtWake();
    await _persistSessionState(active: true, start: _sessionStart);
  }

  Future<SleepLog?> stopSleepSession({bool saveLog = true}) async {
    if (!sessionActive.value) return null;

    _cleanupSession();
    sessionActive.value = false;
    sessionStatus.value = "Idle";
    await cancelReminder(200);
    await _persistSessionState(active: false);

    if (_pausedContinuousForSession) {
      _pausedContinuousForSession = false;
      _startContinuousSensorMonitoring();
    }

    final start = _sessionStart ?? DateTime.now();
    final end = DateTime.now();
    final durationMinutes = end.difference(start).inMinutes;

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

  // ✅ FIX 1 & 7: Wind Down Logic - Changed notification ID to 201 and payload to 'winddown_complete'
  Future<void> startWindDown({int minutes = 20}) async {
    cancelWindDown();
    windDownRemaining.value = minutes * 60;
    windDownActive.value = true;

    try {
      await _notifications.zonedSchedule(
        201, // ✅ Changed from 200 to 201
        "Wind Down Complete",
        "Nice! Time to head to bed 😴",
        tz.TZDateTime.now(tz.local).add(Duration(minutes: minutes)),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'winddown_channel', 'Wind Down',
            channelDescription: 'Wind down reminders',
            importance: Importance.high, priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: 'winddown_complete', // ✅ Changed from 'bedtime'
      );
    } catch (_) {}

    _windDownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (windDownRemaining.value <= 1) {
        t.cancel();
        windDownActive.value = false;
        windDownRemaining.value = 0;
      } else {
        windDownRemaining.value--;
      }
    });
  }

  tz.TZDateTime _nextDailyAt(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var sched = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (sched.isBefore(now)) sched = sched.add(const Duration(days: 1));
    return sched;
  }

  Future<void> scheduleWindDownReminder(String bedtimeHHmm) async {
    try {
      final parts = bedtimeHHmm.split(':');
      final bh = int.parse(parts[0]);
      final bm = int.parse(parts[1]);
      final bedtime = DateTime(2000,1,1,bh,bm);
      final wd = bedtime.subtract(const Duration(minutes: 30));
      final wh = wd.hour, wm = wd.minute;

      await _notifications.zonedSchedule(
        102, // id
        "Wind Down",
        "Start winding down to hit your target bedtime",
        _nextDailyAt(wh, wm),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'winddown_channel', 'Wind Down',
            channelDescription: 'Wind down reminders',
            importance: Importance.max, priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: 'bedtime',
      );
    } catch (e) {
      debugPrint('scheduleWindDownReminder error: $e');
    }
  }

  Future<bool> saveNapLog({
    required DateTime start,
    required DateTime end,
    String? notes,
  }) async {
    try {
      final uid = currentUserId;
      final duration = end.difference(start).inMinutes.clamp(0, 6 * 60);
      await _firestore
          .collection('Users').doc(uid)
          .collection('nap_logs')
          .add({
        'start_iso': start.toUtc().toIso8601String(),
        'end_iso':   end.toUtc().toIso8601String(),
        'duration_minutes': duration,
        'notes': notes,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      return true;
    } catch (e) {
      debugPrint('saveNapLog error: $e');
      return false;
    }
  }

  void startNapSession() {
    if (napActive.value) return;
    _napStart = DateTime.now();
    napElapsed.value = 0;
    napActive.value = true;

    _napTimer?.cancel();
    _napTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      napElapsed.value = DateTime.now().difference(_napStart!).inSeconds;
    });
  }

  Future<void> stopNapSession({bool save = true}) async {
    if (!napActive.value) return;
    _napTimer?.cancel();
    _napTimer = null;
    final end = DateTime.now();
    final start = _napStart ?? end;
    napActive.value = false;

    if (save) {
      final ok = await saveNapLog(start: start, end: end);
      if (!ok) {
        Get.snackbar('Error', 'Could not save nap',
            snackPosition: SnackPosition.BOTTOM);
      }
    }
  }

  Future<Map<String,int>> getRecentNapMinutesByDay({int days = 7}) async {
    final uid = currentUserId;
    final end = DateTime.now();
    final start = DateTime(end.year, end.month, end.day)
        .subtract(Duration(days: days - 1));

    final qs = await _firestore
        .collection('Users').doc(uid)
        .collection('nap_logs')
        .where('start_iso', isGreaterThanOrEqualTo: start.toUtc().toIso8601String())
        .where('start_iso', isLessThanOrEqualTo: end.toUtc().toIso8601String())
        .get();

    final map = <String,int>{};
    for (final d in qs.docs) {
      final m = d.data();
      final startIso = m['start_iso'] as String?;
      final dur = (m['duration_minutes'] as int?) ?? 0;
      if (startIso == null) continue;
      final dt = DateTime.parse(startIso).toLocal();
      final key = SleepTimeHelper.dayKey(dt);
      map[key] = (map[key] ?? 0) + dur;
    }
    return map;
  }

  void toggleNapSession() {
    if (napActive.value) {
      stopNapSession(save: true);
    } else {
      startNapSession();
    }
  }

  // ✅ FIX 5: Cancel both wind-down notification IDs
  void cancelWindDown() {
    _windDownTimer?.cancel();
    _windDownTimer = null;
    windDownActive.value = false;
    windDownRemaining.value = 0;
    _notifications.cancel(200); // Old ID (for safety)
    _notifications.cancel(201); // ✅ New wind-down ID
  }
}