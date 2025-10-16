// lib/services/nutrition_api_service.dart
// Hybrid fetcher: loads your local JSON (assets/cleaned_indian_food_dataset.json)
// and queries USDA FDC, normalizing everything to per 100 g with serving info.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:developer' as dev;

import '../modules/home/widgets/calorie_track/meal_model.dart';

class NutritionApiService {
  final String usdaApiKey;
  final String localAssetPath; // e.g., 'assets/cleaned_indian_food_dataset.json'

  NutritionApiService({
    String? usdaApiKey,
    String? localAssetPath,
  })  : usdaApiKey = usdaApiKey ?? (dotenv.env['USDA_API_KEY'] ?? ''),
        localAssetPath = localAssetPath ?? 'assets/cleaned_indian_food_dataset.json';

  Future<Map<String, dynamic>> _loadLocalJson() async {
    try {
      final txt = await rootBundle.loadString(localAssetPath);
      final data = jsonDecode(txt);
      if (data is Map<String, dynamic>) return data;
      return {};
    } catch (e, st) {
      dev.log('Local JSON load failed', error: e, stackTrace: st);
      return {};
    }
  }

  // Computes daily recommended calories using Mifflin–St Jeor + activity factor.
// Defaults to 'female' (to match your earlier pipeline), but you can pass 'male'.
  Future<double> recommendedCaloriesForProfile({
    required double weightKg,
    required double heightCm,
    required int age,
    required String activity,
    String sex = 'female',
  }) async {
    // Mifflin–St Jeor BMR
    final bmr = 10 * weightKg + 6.25 * heightCm - 5 * age + (sex.toLowerCase() == 'male' ? 5 : -161);

    // Activity factors
    const factors = {
      'sedentary': 1.2,
      'light': 1.375,
      'moderate': 1.55,
      'active': 1.725,
      'very active': 1.9,
    };
    final k = activity.toLowerCase().trim();
    final factor = factors[k] ?? 1.2;

    final total = bmr * factor;
    // return a clean rounded value (no need for high precision here)
    return double.parse(total.toStringAsFixed(0));
  }



  Future<List<FoodItem>> searchLocal(String query) async {
    final db = await _loadLocalJson();
    final q = query.toLowerCase().trim();
    final out = <FoodItem>[];
    db.forEach((key, val) {
      if (key.toLowerCase().contains(q)) {
        out.add(FoodItem.fromJsonEntry(
          key,
          Map<String, dynamic>.from(val as Map),
        ));
      }
    });
    return out;
  }

  Future<List<FoodItem>> searchUSDA(String query) async {
    if (usdaApiKey.isEmpty) return [];
    final url = Uri.parse(
        'https://api.nal.usda.gov/fdc/v1/foods/search?query=${Uri.encodeComponent(query)}&api_key=$usdaApiKey&pageSize=20');
    final res = await http.get(url);
    if (res.statusCode != 200) {
      dev.log('USDA search failed: ${res.statusCode} ${res.body}');
      return [];
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final foods = (json['foods'] as List<dynamic>? ?? []);
    final items = <FoodItem>[];

    for (final f in foods) {
      final m = f as Map<String, dynamic>;
      final fdcId = m['fdcId'].toString();
      final desc = (m['description'] ?? '').toString();

      double? servingG;
      String? servingLabel;

      if (m['servingSize'] != null && m['servingSizeUnit'] != null) {
        final sz = (m['servingSize'] as num).toDouble();
        final unit = (m['servingSizeUnit'] ?? '').toString().toLowerCase();
        if (unit == 'g' || unit == 'ml') servingG = sz;
        servingLabel = '1 serving';
      }
      if (m['householdServingFullText'] != null) {
        servingLabel = m['householdServingFullText'].toString();
      }

      final nutrients = (m['foodNutrients'] as List<dynamic>? ?? []);
      final mapIdToAmt = <int, double>{};

      for (final n in nutrients) {
        final nm = n as Map<String, dynamic>;
        // Accept both schemas
        if (nm['nutrientId'] != null) {
          final id = (nm['nutrientId'] as num).toInt();
          final val = nm['value'] ?? nm['amount'];
          if (val is num) mapIdToAmt[id] = val.toDouble();
        } else if (nm['nutrient'] != null) {
          final nn = nm['nutrient'] as Map<String, dynamic>;
          final id = (nn['id'] ?? 0) is num ? (nn['id'] as num).toInt() : null;
          final val = nm['amount'];
          if (id != null && val is num) mapIdToAmt[id] = val.toDouble();
        }
      }

      double kcal = mapIdToAmt[1008] ?? 0;
      double prot = mapIdToAmt[1003] ?? 0;
      double fat  = mapIdToAmt[1004] ?? 0;
      double carb = mapIdToAmt[1005] ?? 0;

      // Heuristic: if serving present and numbers look per-serving, scale to per 100 g
      bool looksPerServing = false;
      if (servingG != null) {
        if (kcal > 500 || prot > 50 || carb > 100) looksPerServing = true;
      }
      if (looksPerServing && servingG != null && servingG > 0) {
        final factor = 100.0 / servingG;
        kcal *= factor;
        prot *= factor;
        fat *= factor;
        carb *= factor;
      }

      items.add(
        FoodItem(
          key: fdcId,
          name: desc,
          per100gCalories: kcal,
          per100gProtein: prot,
          per100gFat: fat,
          per100gCarbs: carb,
          servings: [
            if (servingG != null)
              ServingOption(unit: 'serving', grams: servingG, description: servingLabel),
          ],
          defaultServing: servingG != null ? 'serving' : null,
        ),
      );
    }

    return items;
  }

  Future<List<FoodItem>> searchAll(String query) async {
    final local = await searchLocal(query);
    final usda = await searchUSDA(query);
    return [...local, ...usda];
  }
}
