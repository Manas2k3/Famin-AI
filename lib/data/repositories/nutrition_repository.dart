// lib/data/repositories/nutrition_repository.dart
import 'dart:developer' as dev;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:famina/utils/string_title_case.dart';

// Your app models
import '../../modules/home/widgets/calorie_track/meal_model.dart';

// Service with getNutritionData
import '../../services/nutrition_api_service.dart';

class NutritionRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get user profile from Firestore
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

  /// Add a meal entry by calling the on-device USDA aggregator and storing results
  Future<void> addMealEntry({
    required String userId,
    required MealType mealType,
    required List<String> foods,
  }) async {
    try {
      // 1) Get user profile
      final profile = await getUserProfile(userId);

      // 2) Prepare meals map for API (single meal only)
      final Map<String, List<String>> mealsData = {
        mealType.apiKey: foods,
      };

      // 3) Call service to get nutrition data (USDA-only, on-device)
      final nutritionResponse = await NutritionService.getNutritionData(
        weightKg: profile.weightKg,
        heightCm: profile.heightCm,
        age: profile.age,
        activity: profile.activity,
        meals: mealsData,
      );

      // 4) Find this meal's summary
      MealNutrition? mealSummary;
      for (final m in nutritionResponse.meals) {
        if (m.meal.toLowerCase() == mealType.apiKey.toLowerCase()) {
          mealSummary = m;
          break;
        }
      }

      if (mealSummary == null || mealSummary.items.isEmpty) {
        throw Exception(
          'No nutrition data received for ${mealType.apiKey}.',
        );
      }

      // 5) Totals
      final totals = mealSummary.totals;

      // 6) Flatten items for Firestore (nested nutrition shape)
      final List<Map<String, dynamic>> foodsJson = mealSummary.items.map((f) {
        return {
          'name': f.name.toTitleCase(),
          'amount': (f.amount.isFinite && f.amount > 0) ? f.amount : 1.0,
          'unit': (f.unit.isNotEmpty) ? f.unit : 'serving',
          'nutrition': f.nutrition?.toJson(), // {kcal, protein, fat, carbs}
        };
      }).toList();

      // 7) Create meal entry document
      final mealEntry = <String, dynamic>{
        'mealType': mealType.apiKey, // 'breakfast' | 'lunch' | 'snacks' | 'dinner'
        'foods': foodsJson,
        'timestamp': FieldValue.serverTimestamp(),
        'totalCalories': totals.calories,
        'totalProtein': totals.protein,
        'totalFat': totals.fat,
        'totalCarbs': totals.carbs,
        'userId': userId,
      };

      // 8) Store in Firestore
      await _firestore.collection('meal_entries').add(mealEntry);
      dev.log('Meal entry added', name: 'NutritionRepository', error: {
        'userId': userId,
        'mealType': mealType.apiKey,
        'foodsCount': foodsJson.length,
        'kcal': totals.calories,
      });
    } catch (e, st) {
      dev.log('Error adding meal entry',
          name: 'NutritionRepository', error: e, stackTrace: st);
      throw Exception('Failed to add meal entry: $e');
    }
  }

  /// Stream meal entries for a specific date
  Stream<List<MealEntry>> getMealEntriesForDate({
    required String userId,
    required DateTime date,
  }) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

    final query = _firestore
        .collection('meal_entries')
        .where('userId', isEqualTo: userId)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
        .orderBy('timestamp', descending: true);

    return query.snapshots().handleError((e, st) {
      // Index/permission errors get logged to terminal
      dev.log('meal_entries stream error',
          name: 'NutritionRepository', error: e, stackTrace: st);
    }).map((snapshot) {
      return snapshot.docs.map((doc) => MealEntry.fromFirestore(doc)).toList();
    });
  }

  /// Daily nutrition summary
  ///
  /// We now read **recommendedCalories** from the same service that performs
  /// the USDA aggregation (so math matches your Flask logic exactly).
  Future<DailyNutritionSummary> getDailySummary({
    required String userId,
    required DateTime date,
  }) async {
    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

      // Get profile for BMR input
      final profile = await getUserProfile(userId);

      // Ask the service for recommended calories (meals empty = just BMR path)
      final recRes = await NutritionService.getNutritionData(
        weightKg: profile.weightKg,
        heightCm: profile.heightCm,
        age: profile.age,
        activity: profile.activity,
        meals: const {}, // no meals; we only want recommended here
      );
      final recommendedCalories = recRes.recommendedCalories;

      // Fetch all meals for the day
      final snapshot = await _firestore
          .collection('meal_entries')
          .where('userId', isEqualTo: userId)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .get();

      if (snapshot.docs.isEmpty) {
        return DailyNutritionSummary.empty(date, recommendedCalories);
      }

      // Accumulate totals with defensive parsing
      double totalCalories = 0;
      double totalProtein = 0;
      double totalFat = 0;
      double totalCarbs = 0;

      double _d(v) => (v is int) ? v.toDouble() : (v as num?)?.toDouble() ?? 0.0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        totalCalories += _d(data['totalCalories']);
        totalProtein += _d(data['totalProtein']);
        totalFat += _d(data['totalFat']);
        totalCarbs += _d(data['totalCarbs']);
      }

      return DailyNutritionSummary(
        totalCalories: totalCalories,
        totalProtein: totalProtein,
        totalFat: totalFat,
        totalCarbs: totalCarbs,
        recommendedCalories: recommendedCalories,
        date: date,
      );
    } catch (e, st) {
      dev.log('Error getting daily summary',
          name: 'NutritionRepository', error: e, stackTrace: st);

      // Graceful fallback: attempt to compute recommended again; else final default
      try {
        final profile = await getUserProfile(userId);
        final recRes = await NutritionService.getNutritionData(
          weightKg: profile.weightKg,
          heightCm: profile.heightCm,
          age: profile.age,
          activity: profile.activity,
          meals: const {},
        );
        return DailyNutritionSummary.empty(date, recRes.recommendedCalories);
      } catch (_) {
        return DailyNutritionSummary.empty(date, 1600); // final fallback
      }
    }
  }

  /// Delete a meal entry
  Future<void> deleteMealEntry(String entryId) async {
    try {
      await _firestore.collection('meal_entries').doc(entryId).delete();
    } catch (e) {
      throw Exception('Failed to delete meal entry: $e');
    }
  }
}
