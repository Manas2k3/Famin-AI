// Firestore repository using hybrid model (per-100 g baseline + servings).

import 'dart:developer' as dev;
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/nutrition_api_service.dart';
import '../../modules/home/widgets/calorie_track/meal_model.dart';
import '../models/pending_meal_item_dto.dart';

class NutritionRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NutritionApiService api;

  NutritionRepository({NutritionApiService? api})
      : api = api ?? NutritionApiService();

  // --- User profile (must expose weightKg/heightCm/age/activity) ---
  Future<UserProfile> getUserProfile(String userId) async {
    try {
      final doc = await _firestore.collection('Users').doc(userId).get();
      if (!doc.exists) {
        throw Exception('User profile not found');
      }
      return UserProfile.fromFirestore(doc.data()!);
    } catch (e, st) {
      dev.log('Error getting user profile',
          name: 'NutritionRepository', error: e, stackTrace: st);
      throw Exception('Failed to get user profile: $e');
    }
  }

  // --- Old "free text" add; keeps your old UI working if needed ---
  Future<void> addMealEntry({
    required String userId,
    required MealType mealType,
    required List<String> foods,
  }) async {
    try {
      final loggedItems = <LoggedMealItem>[];
      double tCal = 0, tP = 0, tF = 0, tC = 0;

      for (final raw in foods) {
        final q = raw.trim();
        if (q.isEmpty) continue;

        final results = await api.searchAll(q);
        if (results.isEmpty) {
          dev.log('No match for "$q"');
          continue;
        }
        final f = results.first;

        // Default: 1 "serving" if defined, else 100 g
        final unit = f.defaultServing ?? '100g';
        final grams = unit == '100g' ? 100.0 : (f.servingSizeGrams(unit) ?? 100.0);

        final n = f.nutrientsForGrams(grams);
        tCal += n['calories'] ?? 0;
        tP += n['protein'] ?? 0;
        tF += n['fat'] ?? 0;
        tC += n['carbs'] ?? 0;

        loggedItems.add(
          LoggedMealItem(
            name: f.name,
            amount: 1.0,
            unit: unit,
            nutrients: n,
          ),
        );
      }

      if (loggedItems.isEmpty) {
        throw Exception('No recognized foods to log.');
      }

      final mealEntry = <String, dynamic>{
        'mealType': mealType.apiKey,
        'foods': loggedItems.map((e) => e.toFirestore()).toList(),
        'timestamp': FieldValue.serverTimestamp(),
        'totalCalories': double.parse(tCal.toStringAsFixed(2)),
        'totalProtein': double.parse(tP.toStringAsFixed(2)),
        'totalFat': double.parse(tF.toStringAsFixed(2)),
        'totalCarbs': double.parse(tC.toStringAsFixed(2)),
        'userId': userId,
      };

      await _firestore.collection('meal_entries').add(mealEntry);
      dev.log('Meal entry added (free text)',
          name: 'NutritionRepository',
          error: {'userId': userId, 'mealType': mealType.apiKey, 'kcal': tCal});
    } catch (e, st) {
      dev.log('Error adding meal entry',
          name: 'NutritionRepository', error: e, stackTrace: st);
      throw Exception('Failed to add meal entry: $e');
    }
  }

  // --- New: exact add from dialog (units, servings, grams override) ---
  Future<void> addMealEntryExact({
    required String userId,
    required MealType mealType,
    required List<PendingMealItemDTO> items,
  }) async {
    try {
      final loggedItems = <LoggedMealItem>[];
      double tCal = 0, tP = 0, tF = 0, tC = 0;

      for (final it in items) {
        final results = await api.searchAll(it.name);
        if (results.isEmpty) {
          dev.log('No match for "${it.name}"');
          continue;
        }
        final f = results.first;

        // Decide grams
        double grams;
        if (it.gramsOverride != null && it.gramsOverride! > 0) {
          grams = it.gramsOverride!;
        } else if (it.unit != null) {
          final perUnit = f.servingSizeGrams(it.unit!) ?? 0.0;
          grams = (perUnit > 0 ? perUnit : 100.0) * (it.servings > 0 ? it.servings : 1.0);
        } else {
          grams = 100.0 * (it.servings > 0 ? it.servings : 1.0);
        }

        final n = f.nutrientsForGrams(grams);
        tCal += n['calories'] ?? 0;
        tP += n['protein'] ?? 0;
        tF += n['fat'] ?? 0;
        tC += n['carbs'] ?? 0;

        // Store friendly amount/unit for display
        final displayUnit = (it.gramsOverride != null) ? 'g' : (it.unit ?? '100g');
        final displayAmount = (it.gramsOverride != null) ? grams : it.servings;

        loggedItems.add(
          LoggedMealItem(
            name: f.name,
            amount: displayAmount,
            unit: displayUnit,
            nutrients: n,
          ),
        );
      }

      if (loggedItems.isEmpty) {
        throw Exception('No recognized foods to log.');
      }

      final mealEntry = <String, dynamic>{
        'mealType': mealType.apiKey,
        'foods': loggedItems.map((e) => e.toFirestore()).toList(),
        'timestamp': FieldValue.serverTimestamp(),
        'totalCalories': double.parse(tCal.toStringAsFixed(2)),
        'totalProtein': double.parse(tP.toStringAsFixed(2)),
        'totalFat': double.parse(tF.toStringAsFixed(2)),
        'totalCarbs': double.parse(tC.toStringAsFixed(2)),
        'userId': userId,
      };

      await _firestore.collection('meal_entries').add(mealEntry);
      dev.log('Meal entry added (exact)',
          name: 'NutritionRepository',
          error: {'userId': userId, 'mealType': mealType.apiKey, 'kcal': tCal});
    } catch (e, st) {
      dev.log('Error adding exact meal',
          name: 'NutritionRepository', error: e, stackTrace: st);
      throw Exception('Failed to add meal entry: $e');
    }
  }

  // --- Stream for a specific date ---
  Stream<List<MealEntry>> getMealEntriesForDate({
    required String userId,
    required DateTime date,
  }) {
    final start = DateTime(date.year, date.month, date.day);
    final end = DateTime(date.year, date.month, date.day, 23, 59, 59);

    final query = _firestore
        .collection('meal_entries')
        .where('userId', isEqualTo: userId)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .orderBy('timestamp', descending: true);

    return query.snapshots().handleError((e, st) {
      dev.log('meal_entries stream error',
          name: 'NutritionRepository', error: e, stackTrace: st);
    }).map((snap) => snap.docs.map((d) => MealEntry.fromFirestore(d)).toList());
  }

  // --- Daily summary (now awaits your API helper) ---
  Future<DailyNutritionSummary> getDailySummary({
    required String userId,
    required DateTime date,
  }) async {
    try {
      final start = DateTime(date.year, date.month, date.day);
      final end = DateTime(date.year, date.month, date.day, 23, 59, 59);

      final profile = await getUserProfile(userId);

      double recommendedCalories;
      try {
        recommendedCalories = await api.recommendedCaloriesForProfile(
          weightKg: profile.weightKg,
          heightCm: profile.heightCm,
          age: profile.age,
          activity: profile.activity,
        );
      } catch (_) {
        // Fallback if profile incomplete
        recommendedCalories = 1600.0;
      }

      final snapshot = await _firestore
          .collection('meal_entries')
          .where('userId', isEqualTo: userId)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();

      if (snapshot.docs.isEmpty) {
        return DailyNutritionSummary.empty(date, recommendedCalories);
      }

      double cals = 0, p = 0, f = 0, c = 0;
      double _d(v) => (v is int) ? v.toDouble() : (v as num?)?.toDouble() ?? 0.0;

      for (final d in snapshot.docs) {
        final data = d.data();
        cals += _d(data['totalCalories']);
        p += _d(data['totalProtein']);
        f += _d(data['totalFat']);
        c += _d(data['totalCarbs']);
      }

      return DailyNutritionSummary(
        totalCalories: cals,
        totalProtein: p,
        totalFat: f,
        totalCarbs: c,
        recommendedCalories: recommendedCalories,
        date: date,
      );
    } catch (e, st) {
      dev.log('Error getting daily summary',
          name: 'NutritionRepository', error: e, stackTrace: st);
      return DailyNutritionSummary.empty(date, 1600);
    }
  }

  // --- Delete ---
  Future<void> deleteMealEntry(String entryId) async {
    await _firestore.collection('meal_entries').doc(entryId).delete();
  }
}
