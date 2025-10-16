// lib/modules/home/widgets/calorie_track/meal_model.dart
// Hybrid-ready data model aligned to your JSON (per 100 g + servings/default).

import 'package:cloud_firestore/cloud_firestore.dart';

enum MealType { breakfast, quickSnack, lunch, dinner }

extension MealTypeX on MealType {
  String get displayName {
    switch (this) {
      case MealType.breakfast:
        return 'Breakfast';
      case MealType.quickSnack:
        return 'Quick Snack';
      case MealType.lunch:
        return 'Lunch';
      case MealType.dinner:
        return 'Dinner';
    }
  }

  /// API/flask-compatible key
  String get apiKey {
    switch (this) {
      case MealType.breakfast:
        return 'breakfast';
      case MealType.quickSnack:
        return 'snacks';
      case MealType.lunch:
        return 'lunch';
      case MealType.dinner:
        return 'dinner';
    }
  }

  static MealType fromString(String v) {
    final k = v.toLowerCase();
    if (k == 'breakfast') return MealType.breakfast;
    if (k == 'lunch') return MealType.lunch;
    if (k == 'dinner') return MealType.dinner;
    // snack / snacks / quickSnack variants
    return MealType.quickSnack;
  }
}

/// Serving mapping -> grams (ml ≈ g for water-like liquids; your JSON defines grams explicitly)
class ServingOption {
  final String unit;         // 'piece', 'cup', 'ml', '100g', etc.
  final double grams;        // grams represented by the unit
  final String? description; // UX hint

  const ServingOption({required this.unit, required this.grams, this.description});

  factory ServingOption.fromMap(Map<String, dynamic> m) => ServingOption(
    unit: (m['unit'] ?? '').toString(),
    grams: (m['grams'] is num)
        ? (m['grams'] as num).toDouble()
        : double.tryParse(m['grams']?.toString() ?? '') ?? 0.0,
    description: m['description']?.toString(),
  );

  Map<String, dynamic> toMap() => {
    'unit': unit,
    'grams': grams,
    'description': description,
  };
}

/// Canonical food item from JSON/USDA normalized to per 100 g
class FoodItem {
  final String key;   // JSON key (e.g., 'idli', 'coconut milk') or FDC id for USDA
  final String name;

  // Per 100 g baseline
  final double per100gCalories;
  final double per100gProtein;
  final double per100gFat;
  final double per100gCarbs;

  // Serving options
  final List<ServingOption> servings;
  final String? defaultServing;

  const FoodItem({
    required this.key,
    required this.name,
    required this.per100gCalories,
    required this.per100gProtein,
    required this.per100gFat,
    required this.per100gCarbs,
    required this.servings,
    this.defaultServing,
  });

  factory FoodItem.fromJsonEntry(String key, Map<String, dynamic> map) {
    final np100 = Map<String, dynamic>.from(map['nutrition_per_100g'] ?? {});
    final servingsList = (map['servings'] as List<dynamic>? ?? [])
        .map((e) => ServingOption.fromMap(Map<String, dynamic>.from(e)))
        .toList();

    return FoodItem(
      key: key,
      name: key, // display name = key; replace if you store a nicer label
      per100gCalories: (np100['calories'] as num?)?.toDouble() ?? 0.0,
      per100gProtein: (np100['protein'] as num?)?.toDouble() ?? 0.0,
      per100gFat: (np100['fat'] as num?)?.toDouble() ?? 0.0,
      per100gCarbs: (np100['carbs'] as num?)?.toDouble() ?? 0.0,
      servings: servingsList,
      defaultServing: map['default_serving']?.toString(),
    );
  }

  Map<String, dynamic> toJsonEntry() => {
    'nutrition_per_100g': {
      'calories': per100gCalories,
      'protein': per100gProtein,
      'fat': per100gFat,
      'carbs': per100gCarbs,
    },
    'servings': servings.map((s) => s.toMap()).toList(),
    'default_serving': defaultServing,
  };

  double? servingSizeGrams(String unit) {
    for (final s in servings) {
      if (s.unit == unit) return s.grams;
    }
    return null;
  }

  Map<String, double> nutrientsForGrams(double grams) {
    final k = grams / 100.0;
    return {
      'calories': per100gCalories * k,
      'protein': per100gProtein * k,
      'fat': per100gFat * k,
      'carbs': per100gCarbs * k,
    };
  }

  Map<String, double> nutrientsForServings(double count, {String? unit}) {
    final u = unit ?? defaultServing;
    if (u == null) return nutrientsForGrams(0);
    final g = servingSizeGrams(u) ?? 0;
    return nutrientsForGrams(count * g);
  }
}

/// Logged food item as stored in Firestore (per entry line)
class LoggedMealItem {
  final String name;
  final double amount; // number of default-serving units (or grams if unit=='g')
  final String unit;   // 'piece', 'cup', 'ml', '100g', etc.
  final Map<String, double> nutrients; // {calories, protein, fat, carbs}

  LoggedMealItem({
    required this.name,
    required this.amount,
    required this.unit,
    required this.nutrients,
  });

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'amount': amount,
    'unit': unit,
    'nutrition': {
      'kcal': nutrients['calories'] ?? 0,
      'protein': nutrients['protein'] ?? 0,
      'fat': nutrients['fat'] ?? 0,
      'carbs': nutrients['carbs'] ?? 0,
    }
  };

  factory LoggedMealItem.fromFirestore(Map<String, dynamic> m) {
    double _d(v) => (v is int) ? v.toDouble() : (v as num?)?.toDouble() ?? 0.0;
    final n = Map<String, dynamic>.from(m['nutrition'] ?? {});
    return LoggedMealItem(
      name: (m['name'] ?? '').toString(),
      amount: _d(m['amount']),
      unit: (m['unit'] ?? 'serving').toString(),
      nutrients: {
        'calories': _d(n['kcal']),
        'protein': _d(n['protein']),
        'fat': _d(n['fat']),
        'carbs': _d(n['carbs']),
      },
    );
  }
}

/// Firestore meal entry doc
class MealEntry {
  final String id;
  final MealType mealType;
  final List<LoggedMealItem> foods;
  final DateTime timestamp;
  final double totalCalories;
  final double totalProtein;
  final double totalFat;
  final double totalCarbs;

  MealEntry({
    required this.id,
    required this.mealType,
    required this.foods,
    required this.timestamp,
    required this.totalCalories,
    required this.totalProtein,
    required this.totalFat,
    required this.totalCarbs,
  });

  factory MealEntry.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>? ?? {});
    final foodsList = (data['foods'] as List? ?? [])
        .map((f) => LoggedMealItem.fromFirestore(
      Map<String, dynamic>.from(f as Map),
    ))
        .toList();

    // Be resilient if serverTimestamp hasn't resolved yet.
    final ts = data['timestamp'];
    final safeTs =
    ts is Timestamp ? ts.toDate() : ts is DateTime ? ts : DateTime.now();

    double _d(v) => (v is int) ? v.toDouble() : (v as num?)?.toDouble() ?? 0.0;

    return MealEntry(
      id: doc.id,
      mealType: MealTypeX.fromString((data['mealType'] ?? 'breakfast').toString()),
      foods: foodsList,
      timestamp: safeTs,
      totalCalories: _d(data['totalCalories']),
      totalProtein: _d(data['totalProtein']),
      totalFat: _d(data['totalFat']),
      totalCarbs: _d(data['totalCarbs']),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'mealType': mealType.apiKey,
    'foods': foods.map((f) => f.toFirestore()).toList(),
    'timestamp': Timestamp.fromDate(timestamp),
    'totalCalories': totalCalories,
    'totalProtein': totalProtein,
    'totalFat': totalFat,
    'totalCarbs': totalCarbs,
  };
}

class DailyNutritionSummary {
  final double totalCalories;
  final double totalProtein;
  final double totalFat;
  final double totalCarbs;
  final double recommendedCalories;
  final DateTime date;

  DailyNutritionSummary({
    required this.totalCalories,
    required this.totalProtein,
    required this.totalFat,
    required this.totalCarbs,
    required this.recommendedCalories,
    required this.date,
  });

  factory DailyNutritionSummary.empty(DateTime date, double rec) =>
      DailyNutritionSummary(
        totalCalories: 0,
        totalProtein: 0,
        totalFat: 0,
        totalCarbs: 0,
        recommendedCalories: rec,
        date: date,
      );
}

class UserProfile {
  final double weightKg;
  final double heightCm;
  final int age;
  final String activity;
  final String activityLabel;

  UserProfile({
    required this.weightKg,
    required this.heightCm,
    required this.age,
    required this.activity,
    required this.activityLabel,
  });

  factory UserProfile.fromFirestore(Map<String, dynamic> data) {
    final profileData = data['profile'] as Map<String, dynamic>? ?? {};
    double _d(v) => (v is int) ? v.toDouble() : (v as num?)?.toDouble() ?? 0.0;

    return UserProfile(
      weightKg: _d(data['weight_kg'] ?? profileData['weight_kg'] ?? 50),
      heightCm: _d(data['height_cm'] ?? 160),
      age: (data['age'] ?? 25 as num).toInt(),
      activity: (profileData['activity'] ?? 'sedentary').toString(),
      activityLabel: (profileData['activity_label'] ?? 'Sedentary').toString(),
    );
  }

  /// Mifflin–St Jeor (female) × activity factor (quick & consistent)
  double get recommendedCalories {
    final bmr = 10 * weightKg + 6.25 * heightCm - 5 * age - 161;
    const factors = {
      'sedentary': 1.2,
      'light': 1.375,
      'moderate': 1.55,
      'active': 1.725,
      'very active': 1.9,
    };
    final k = activity.toLowerCase().trim();
    final f = factors[k] ?? 1.2;
    return double.parse((bmr * f).toStringAsFixed(0));
  }
}
