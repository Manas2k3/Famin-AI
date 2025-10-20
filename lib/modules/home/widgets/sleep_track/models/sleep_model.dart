import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// =======================
/// Chronotype enum
/// =======================
enum Chronotype {
  earlyBird('early_bird', '🌅 Early Bird', 'You rise with the sun'),
  nightOwl('night_owl', '🌙 Night Owl', 'You thrive in the evening'),
  flexible('flexible', '⚖️ Flexible', 'You adapt to any schedule');

  final String value;
  final String label;
  final String description;

  const Chronotype(this.value, this.label, this.description);

  static Chronotype fromString(String value) {
    return Chronotype.values.firstWhere(
          (e) => e.value == value,
      orElse: () => Chronotype.flexible,
    );
  }
}

/// =======================
/// Sleep Profile (stored in Users/{uid} under sleep_profile)
/// =======================
class SleepProfile {
  final bool setupCompleted;
  final DateTime? setupCompletedAt;
  final Chronotype chronotype;
  final String targetBedtime; // "HH:mm"
  final String targetWake; // "HH:mm"
  final int targetDurationMinutes;
  final LifestyleFactors? lifestyle;
  final TrackingSettings? trackingSettings;
  final DateTime? updatedAt;
  final String? morningReminderHHmm;

  SleepProfile({
    this.setupCompleted = false,
    this.setupCompletedAt,
    required this.chronotype,
    required this.targetBedtime,
    required this.targetWake,
    required this.targetDurationMinutes,
    this.lifestyle,
    this.trackingSettings,
    this.updatedAt,
    this.morningReminderHHmm,
  });

  // Defaults by chronotype
  static Map<String, String> getDefaultTimes(Chronotype chronotype) {
    switch (chronotype) {
      case Chronotype.earlyBird:
        return {'bedtime': '22:00', 'wake': '06:00'};
      case Chronotype.nightOwl:
        return {'bedtime': '00:00', 'wake': '08:00'};
      case Chronotype.flexible:
        return {'bedtime': '23:00', 'wake': '07:00'};
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'setup_completed': setupCompleted,
      'setup_completed_at': setupCompletedAt?.toIso8601String(),
      'chronotype': chronotype.value,
      if (morningReminderHHmm != null)
        'morning_reminder_hhmm': morningReminderHHmm,
      'target_bedtime': targetBedtime,
      'target_wake': targetWake,
      'target_duration_minutes': targetDurationMinutes,
      'lifestyle': lifestyle?.toMap(),
      'tracking_settings': trackingSettings?.toMap(),
      'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
    };
  }

  factory SleepProfile.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return SleepProfile(
        chronotype: Chronotype.flexible,
        targetBedtime: '23:00',
        targetWake: '07:00',
        targetDurationMinutes: 480,
        morningReminderHHmm: map?['morning_reminder_hhmm'] as String?,
      );
    }

    return SleepProfile(
      setupCompleted: map['setup_completed'] ?? false,
      setupCompletedAt: map['setup_completed_at'] != null
          ? DateTime.parse(map['setup_completed_at'])
          : null,
      chronotype: Chronotype.fromString(map['chronotype'] ?? 'flexible'),
      targetBedtime: map['target_bedtime'] ?? '23:00',
      targetWake: map['target_wake'] ?? '07:00',
      targetDurationMinutes: map['target_duration_minutes'] ?? 480,
      lifestyle: map['lifestyle'] != null
          ? LifestyleFactors.fromMap(map['lifestyle'])
          : null,
      trackingSettings: map['tracking_settings'] != null
          ? TrackingSettings.fromMap(map['tracking_settings'])
          : null,
      updatedAt:
      map['updated_at'] != null ? DateTime.parse(map['updated_at']) : null,
    );
  }

  SleepProfile copyWith({
    bool? setupCompleted,
    DateTime? setupCompletedAt,
    Chronotype? chronotype,
    String? targetBedtime,
    String? targetWake,
    int? targetDurationMinutes,
    LifestyleFactors? lifestyle,
    TrackingSettings? trackingSettings,
    DateTime? updatedAt,
  }) {
    return SleepProfile(
      setupCompleted: setupCompleted ?? this.setupCompleted,
      setupCompletedAt: setupCompletedAt ?? this.setupCompletedAt,
      chronotype: chronotype ?? this.chronotype,
      targetBedtime: targetBedtime ?? this.targetBedtime,
      targetWake: targetWake ?? this.targetWake,
      targetDurationMinutes:
      targetDurationMinutes ?? this.targetDurationMinutes,
      lifestyle: lifestyle ?? this.lifestyle,
      trackingSettings: trackingSettings ?? this.trackingSettings,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// =======================
/// Lifestyle Factors
/// =======================
class LifestyleFactors {
  final int caffeinePerDay; // 0–3+
  final String caffeineCutoff; // "HH:mm"
  final String roomTempPref; // "cool" | "neutral" | "warm"
  final int lightSensitivity; // 1–5
  final String snoringNoticed; // "yes" | "no" | "unsure"
  final DateTime? updatedAt;

  LifestyleFactors({
    this.caffeinePerDay = 1,
    this.caffeineCutoff = '17:00',
    this.roomTempPref = 'neutral',
    this.lightSensitivity = 3,
    this.snoringNoticed = 'unsure',
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'caffeine_per_day': caffeinePerDay,
      'caffeine_cutoff': caffeineCutoff,
      'room_temp_pref': roomTempPref,
      'light_sensitivity': lightSensitivity,
      'snoring_noticed': snoringNoticed,
      'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
    };
  }

  static String dayKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final da = d.day.toString().padLeft(2, '0');
    return '$y-$m-$da';
  }


  factory LifestyleFactors.fromMap(Map<String, dynamic> map) {
    return LifestyleFactors(
      caffeinePerDay: map['caffeine_per_day'] ?? 1,
      caffeineCutoff: map['caffeine_cutoff'] ?? '17:00',
      roomTempPref: map['room_temp_pref'] ?? 'neutral',
      lightSensitivity: map['light_sensitivity'] ?? 3,
      snoringNoticed: map['snoring_noticed'] ?? 'unsure',
      updatedAt:
      map['updated_at'] != null ? DateTime.parse(map['updated_at']) : null,
    );
  }
}

/// =======================
/// Tracking Settings
/// =======================
class TrackingSettings {
  final bool autoStartEnabled;
  final bool motionDetectionEnabled;
  final bool noiseDetectionEnabled;
  final DateTime? updatedAt;

  TrackingSettings({
    this.autoStartEnabled = true,
    this.motionDetectionEnabled = false,
    this.noiseDetectionEnabled = false,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'auto_start_enabled': autoStartEnabled,
      'motion_detection_enabled': motionDetectionEnabled,
      'noise_detection_enabled': noiseDetectionEnabled,
      'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
    };
  }

  factory TrackingSettings.fromMap(Map<String, dynamic> map) {
    return TrackingSettings(
      autoStartEnabled: map['auto_start_enabled'] ?? true,
      motionDetectionEnabled: map['motion_detection_enabled'] ?? false,
      noiseDetectionEnabled: map['noise_detection_enabled'] ?? false,
      updatedAt:
      map['updated_at'] != null ? DateTime.parse(map['updated_at']) : null,
    );
  }
}

/// =======================
/// SleepTime helper utils
/// =======================
class SleepTimeHelper {
  /// Calculate duration between two "HH:mm" times (handles overnight).
  static int calculateDurationMinutes(String bedtime, String wake) {
    final bed = _parseTime(bedtime);
    var wakeTime = _parseTime(wake);
    if (wakeTime.isBefore(bed)) {
      wakeTime = wakeTime.add(const Duration(days: 1));
    }
    return wakeTime.difference(bed).inMinutes;
  }

  /// Pretty "Xh Ym"
  static String formatDuration(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return mins == 0 ? '${hours}h' : '${hours}h ${mins}m';
  }

  /// Parse "HH:mm" -> DateTime(today)
  static DateTime _parseTime(String time) {
    final parts = time.split(':');
    final now = DateTime.now();
    return DateTime(
      now.year,
      now.month,
      now.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
  }

  /// Format TimeOfDay -> "HH:mm"
  static String formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// Parse "HH:mm" -> TimeOfDay
  static TimeOfDay parseTimeOfDay(String time) {
    final parts = time.split(':');
    return TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );
  }

  /// Guards for absurd durations (<4h or >12h)
  static String? validateDuration(int minutes) {
    if (minutes < 240) {
      return 'Too short for quality sleep (minimum 4h recommended)';
    }
    if (minutes > 720) {
      return 'Seems unusually long (maximum 12h recommended)';
    }
    return null;
  }

  /// Stable document id key from a DateTime: "yyyy-MM-dd"
  static String dayKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

/// =======================
/// Daily Sleep Log (Users/{uid}/sleep_logs/{yyyy-MM-dd})
/// =======================
// sleep_model.dart

class SleepLog {
  final DateTime date;
  final String bedtimeHHmm;
  final String wakeHHmm;
  final int durationMinutes;
  final int? totalSleepMinutes;
  final int? quality;
  final int? awakenings;
  final int? sleepLatencyMinutes;
  final String? notes;
  final List<String>? wakeReasons; // <— add field

  SleepLog({
    required this.date,
    required this.bedtimeHHmm,
    required this.wakeHHmm,
    required this.durationMinutes,
    this.totalSleepMinutes,
    this.quality,
    this.awakenings,
    this.sleepLatencyMinutes,
    this.notes,
    this.wakeReasons, // <— keep
  });

  String get dayKey => SleepTimeHelper.dayKey(date);

  Map<String, dynamic> toMap() => {
    'date_iso': date.toUtc().toIso8601String(), // also save UTC (see #4)
    'bedtime_hhmm': bedtimeHHmm,
    'wake_hhmm': wakeHHmm,
    'duration_minutes': durationMinutes,
    if (totalSleepMinutes != null) 'total_sleep_minutes': totalSleepMinutes,
    if (quality != null) 'quality': quality,
    if (awakenings != null) 'awakenings': awakenings,
    if (sleepLatencyMinutes != null) 'sleep_latency_minutes': sleepLatencyMinutes,
    if (notes != null) 'notes': notes,
    if (wakeReasons != null && wakeReasons!.isNotEmpty) 'wake_reasons': wakeReasons,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };

  factory SleepLog.fromMap(Map<String, dynamic> map) => SleepLog(
    date: DateTime.parse(map['date_iso']).toLocal(),
    bedtimeHHmm: map['bedtime_hhmm'],
    wakeHHmm: map['wake_hhmm'],
    durationMinutes: map['duration_minutes'],
    totalSleepMinutes: map['total_sleep_minutes'],
    quality: map['quality'],
    awakenings: map['awakenings'],
    sleepLatencyMinutes: map['sleep_latency_minutes'],
    notes: map['notes'],
    wakeReasons: (map['wake_reasons'] as List?)?.cast<String>(),
  );
}


/// =======================
/// UserData
/// =======================
class UserData {
  final String id;
  final String email;
  final String name;
  final int age;
  final int heightCm;
  final int weightKg;
  final String activity;
  final double activityFactor;
  final SleepProfile? sleepProfile;

  // Cycle data
  final Timestamp? lastPeriodStartTs;
  final String? predictedNextPeriodStart;
  final int? avgCycleLengthDays;

  // Health conditions
  final String? healthConditionSelected;

  UserData({
    required this.id,
    required this.email,
    required this.name,
    required this.age,
    required this.heightCm,
    required this.weightKg,
    required this.activity,
    required this.activityFactor,
    this.sleepProfile,
    this.lastPeriodStartTs,
    this.predictedNextPeriodStart,
    this.avgCycleLengthDays,
    this.healthConditionSelected,
  });

  // Calculate BMI
  double get bmi => weightKg / ((heightCm / 100) * (heightCm / 100));

  bool get isUnderweight => bmi < 18.5;

  String get sleepRecommendation {
    if (age >= 18 && age <= 25) {
      return '7-9 hours recommended for young adults';
    } else if (age >= 26 && age <= 64) {
      return '7-9 hours recommended for adults';
    } else {
      return '7-8 hours recommended';
    }
  }

  factory UserData.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserData(
      id: doc.id,
      email: data['email'] ?? '',
      name: data['name'] ?? '',
      age: data['age'] ?? 22,
      heightCm: data['height_cm'] ?? 160,
      weightKg: data['weight_kg'] ?? 50,
      activity: data['profile']?['activity'] ?? 'sedentary',
      activityFactor:
      (data['profile']?['activity_factor'] ?? 1.2).toDouble(),
      sleepProfile: SleepProfile.fromMap(data['sleep_profile']),
      lastPeriodStartTs: data['last_period_start_ts'],
      predictedNextPeriodStart: data['predicted_next_period_start'],
      avgCycleLengthDays: data['avg_cycle_length_days'],
      healthConditionSelected: data['health_conditions']?['selected'],
    );
  }
}
