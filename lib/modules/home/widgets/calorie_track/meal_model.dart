import 'package:cloud_firestore/cloud_firestore.dart';

enum MealType { breakfast, quickSnack, lunch, dinner;

  String get displayName {
    switch (this) {
      case MealType.breakfast: return 'Breakfast';
      case MealType.quickSnack: return 'Quick Snack';
      case MealType.lunch: return 'Lunch';
      case MealType.dinner: return 'Dinner';
    }
  }

  /// Flask expects plural "snacks"
  String get apiKey {
    switch (this) {
      case MealType.breakfast: return 'breakfast';
      case MealType.quickSnack: return 'snacks'; // <-- changed
      case MealType.lunch: return 'lunch';
      case MealType.dinner: return 'dinner';
    }
  }

  static MealType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'breakfast': return MealType.breakfast;
      case 'snacks': // <-- accept plural
      case 'snack':
      case 'quick_snack':
      case 'quicksnack':
      case 'quicksnacks':
      case 'quickSnack':
        return MealType.quickSnack;
      case 'lunch': return MealType.lunch;
      case 'dinner': return MealType.dinner;
      default: return MealType.breakfast;
    }
  }
}

class NutritionDetail {
  final double kcal;
  final double protein;
  final double fat;
  final double carbs;

  const NutritionDetail({
    required this.kcal,
    required this.protein,
    required this.fat,
    required this.carbs,
  });

  factory NutritionDetail.fromMap(Map<String, dynamic>? map) {
    final m = map ?? const {};
    double _d(v) => (v is int) ? v.toDouble() : (v as num?)?.toDouble() ?? 0.0;
    return NutritionDetail(
      kcal: _d(m['kcal']),
      protein: _d(m['protein']),
      fat: _d(m['fat']),
      carbs: _d(m['carbs']),
    );
  }

  Map<String, dynamic> toJson() => {
    'kcal': kcal,
    'protein': protein,
    'fat': fat,
    'carbs': carbs,
  };
}

class FoodItem {
  final String name;
  final double amount; // e.g., 1
  final String unit;   // e.g., serving
  final NutritionDetail nutrition;

  const FoodItem({
    required this.name,
    required this.amount,
    required this.unit,
    required this.nutrition,
  });

  /// Backward-compatible with both nested and flat shapes.
  factory FoodItem.fromJson(Map<String, dynamic> json) {
    double _d(v) => (v is int) ? v.toDouble() : (v as num?)?.toDouble() ?? 0.0;

    final hasNested = json['nutrition'] is Map<String, dynamic>;
    final nutrition = hasNested
        ? NutritionDetail.fromMap(json['nutrition'] as Map<String, dynamic>?)
        : NutritionDetail(
      kcal: _d(json['kcal']),
      protein: _d(json['protein']),
      fat: _d(json['fat']),
      carbs: _d(json['carbs']),
    );

    return FoodItem(
      name: (json['name'] ?? '').toString(),
      amount: _d(json['amount']),
      unit: (json['unit'] ?? '').toString(),
      nutrition: nutrition,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'amount': amount,
    'unit': unit,
    'nutrition': nutrition.toJson(),
  };

  // Convenience getters for UI.
  double get calories => nutrition.kcal;
  double get protein => nutrition.protein;
  double get fat => nutrition.fat;
  double get carbs => nutrition.carbs;
}

class MealEntry {
  final String id;
  final MealType mealType;
  final List<FoodItem> foods;
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
        .map((f) => FoodItem.fromJson((f as Map).cast<String, dynamic>()))
        .toList();

    // Be resilient if serverTimestamp hasn't resolved yet.
    final ts = data['timestamp'];
    final safeTs = ts is Timestamp
        ? ts.toDate()
        : ts is DateTime
        ? ts
        : DateTime.now();

    double _d(v) => (v is int) ? v.toDouble() : (v as num?)?.toDouble() ?? 0.0;

    return MealEntry(
      id: doc.id,
      mealType:
      MealType.fromString((data['mealType'] ?? 'breakfast').toString()),
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
    'foods': foods.map((f) => f.toJson()).toList(),
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

  factory DailyNutritionSummary.empty(
      DateTime date, double recommendedCalories) =>
      DailyNutritionSummary(
        totalCalories: 0,
        totalProtein: 0,
        totalFat: 0,
        totalCarbs: 0,
        recommendedCalories: recommendedCalories,
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
}
