import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart'; // for TimeOfDay in schedule stubs

import '../models/sleep_model.dart';

class SleepService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Root user doc (collection **Users** ✅)
  DocumentReference<Map<String, dynamic>> _userDoc(String userId) {
    return _firestore.collection('Users').doc(userId);
  }

  /// Subcollection: sleep_logs
  CollectionReference<Map<String, dynamic>> _sleepLogs(String userId) {
    return _userDoc(userId).collection('sleep_logs');
  }

  // -----------------------------
  // User + Profile
  // -----------------------------

  /// Fetch user data, including `sleep_profile` if present.
  Future<UserData?> getUserData(String userId) async {
    try {
      final doc = await _userDoc(userId).get();
      if (!doc.exists) return null;
      return UserData.fromFirestore(doc);
    } catch (e) {
      // ignore: avoid_print
      print('SleepService.getUserData error: $e');
      rethrow;
    }
  }

  /// Live stream of user data.
  Stream<UserData?> streamUserData(String userId) {
    return _userDoc(userId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserData.fromFirestore(doc);
    });
  }

  /// Save Screen 1 (chronotype + targets).
  /// Uses merge so it creates the map if missing.
  Future<void> saveSleepProfile({
    required String userId,
    required Chronotype chronotype,
    required String targetBedtime, // "HH:mm"
    required String targetWake,    // "HH:mm"
    required int targetDurationMinutes,
  }) async {
    try {
      await _userDoc(userId).set({
        'sleep_profile': {
          'chronotype': chronotype.value,
          'target_bedtime': targetBedtime,
          'target_wake': targetWake,
          'target_duration_minutes': targetDurationMinutes,
          'updated_at': DateTime.now().toIso8601String(),
        }
      }, SetOptions(merge: true));
    } catch (e) {
      // ignore: avoid_print
      print('SleepService.saveSleepProfile error: $e');
      rethrow;
    }
  }

  /// Save Screen 2 (lifestyle).
  Future<void> saveLifestyleFactors({
    required String userId,
    required LifestyleFactors lifestyle,
  }) async {
    try {
      await _userDoc(userId).set({
        'sleep_profile': {
          'lifestyle': lifestyle.toMap(),
          'updated_at': DateTime.now().toIso8601String(),
        }
      }, SetOptions(merge: true));
    } catch (e) {
      // ignore: avoid_print
      print('SleepService.saveLifestyleFactors error: $e');
      rethrow;
    }
  }

  /// Save Screen 3 (tracking settings).
  Future<void> saveTrackingSettings({
    required String userId,
    required TrackingSettings settings,
  }) async {
    try {
      await _userDoc(userId).set({
        'sleep_profile': {
          'tracking_settings': settings.toMap(),
          'updated_at': DateTime.now().toIso8601String(),
        }
      }, SetOptions(merge: true));
    } catch (e) {
      // ignore: avoid_print
      print('SleepService.saveTrackingSettings error: $e');
      rethrow;
    }
  }

  /// Mark setup completed.
  Future<void> completeSetup(String userId) async {
    try {
      final now = DateTime.now().toIso8601String();
      await _userDoc(userId).set({
        'sleep_profile': {
          'setup_completed': true,
          'setup_completed_at': now,
          'updated_at': now,
        }
      }, SetOptions(merge: true));
    } catch (e) {
      // ignore: avoid_print
      print('SleepService.completeSetup error: $e');
      rethrow;
    }
  }

  /// Partial updates under sleep_profile.*
  Future<void> updateSleepProfile({
    required String userId,
    required Map<String, dynamic> updates, // keys like "target_bedtime": "23:00"
  }) async {
    if (updates.isEmpty) return;
    try {
      final Map<String, dynamic> prefixed = {};
      for (final entry in updates.entries) {
        prefixed['sleep_profile.${entry.key}'] = entry.value;
      }
      prefixed['sleep_profile.updated_at'] = DateTime.now().toIso8601String();
      await _userDoc(userId).set(prefixed, SetOptions(merge: true));
    } catch (e) {
      // ignore: avoid_print
      print('SleepService.updateSleepProfile error: $e');
      rethrow;
    }
  }

  /// Check if onboarding/setup completed.
  Future<bool> isSetupCompleted(String userId) async {
    try {
      final snap = await _userDoc(userId).get();
      final data = snap.data();
      return data?['sleep_profile']?['setup_completed'] == true;
    } catch (e) {
      // ignore: avoid_print
      print('SleepService.isSetupCompleted error: $e');
      return false;
    }
  }

  // -----------------------------
  // Logs (optional helpers)
  // -----------------------------

  /// Save a log (merge-friendly).
  Future<void> saveSleepLog(String userId, SleepLog log) async {
    try {
      await _sleepLogs(userId).doc(log.dayKey).set(
        log.toMap(),
        SetOptions(merge: true),
      );
    } catch (e) {
      // ignore: avoid_print
      print('SleepService.saveSleepLog error: $e');
      rethrow;
    }
  }

  /// Fetch a specific day’s log by key "yyyy-MM-dd".
  Future<SleepLog?> getLog(String userId, String dayKey) async {
    try {
      final doc = await _sleepLogs(userId).doc(dayKey).get();
      if (!doc.exists) return null;
      return SleepLog.fromMap(doc.data()!);
    } catch (e) {
      // ignore: avoid_print
      print('SleepService.getLog error: $e');
      rethrow;
    }
  }

  /// Fetch most recent log by date_iso.
  Future<SleepLog?> getMostRecentLog(String userId) async {
    try {
      final q = await _sleepLogs(userId)
          .orderBy('date_iso', descending: true)
          .limit(1)
          .get();
      if (q.docs.isEmpty) return null;
      return SleepLog.fromMap(q.docs.first.data());
    } catch (e) {
      // ignore: avoid_print
      print('SleepService.getMostRecentLog error: $e');
      rethrow;
    }
  }

  /// Fetch logs since [days] ago (ascending).
  Future<List<SleepLog>> getRecentLogs(String userId, {int days = 7}) async {
    try {
      final cutoff = DateTime.now().subtract(Duration(days: days + 1));
      final q = await _sleepLogs(userId)
          .where('date_iso',
          isGreaterThanOrEqualTo: cutoff.toUtc().toIso8601String())
          .orderBy('date_iso', descending: false)
          .get();
      return q.docs.map((d) => SleepLog.fromMap(d.data())).toList();
    } catch (e) {
      // ignore: avoid_print
      print('SleepService.getRecentLogs error: $e');
      rethrow;
    }
  }

  /// Quick existence check for a date.
  Future<bool> hasLogForDate(String userId, DateTime date) async {
    try {
      final key = SleepTimeHelper.dayKey(date);
      final snap = await _sleepLogs(userId).doc(key).get();
      return snap.exists;
    } catch (e) {
      // ignore: avoid_print
      print('SleepService.hasLogForDate error: $e');
      return false;
    }
  }

  // -----------------------------
  // Notification stubs (to implement with flutter_local_notifications)
  // -----------------------------

  Future<void> scheduleEveningNudge(TimeOfDay targetBedtime) async {
    // TODO: implement zonedSchedule -> targetBedtime - 30 min
  }

  Future<void> scheduleMorningNudge(TimeOfDay targetWake) async {
    // TODO: implement zonedSchedule -> targetWake + 15 min
  }
}
