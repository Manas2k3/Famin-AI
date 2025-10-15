import 'dart:convert';
import 'dart:developer' as dev;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// ===================== Service =====================
class NutritionService {
  // ---- .env values ----
  static final String _usdaApiKey = dotenv.env['USDA_API_KEY'] ?? '';
  static final String _usdaSearchUrl = dotenv.env['USDA_SEARCH_URL'] ??
      'https://api.nal.usda.gov/fdc/v1/foods/search';

  // ---- sample foods for spelling correction (same as Flask) ----
  static const List<String> _sampleDict = [
    "rice", "roti", "chapati", "dal", "upma", "poha", "dosa", "idli",
    "sambar", "curd", "paneer", "chicken curry", "fish curry", "salad",
    "bread", "egg", "milk", "banana", "apple", "cookies", "biscuits",
    "chocolate", "nuts", "tea", "coffee", "maggie", "chips", "samosa"
  ];

  /// ===================== Public entrypoint (Flask /daily-intake in Dart) =====================
  ///
  /// meals example:
  /// {
  ///   "breakfast": ["poha", "banana"],
  ///   "lunch": ["rice", "dal"],
  ///   "snacks": ["tea", "biscuits"],
  ///   "dinner": ["roti", "paneer"]
  /// }
  static Future<NutritionData> getNutritionData({
    required double weightKg,
    required double heightCm,
    required int age,
    required String activity, // "sedentary" | "light" | "moderate" | "active" | "very active"
    required Map<String, List<String>> meals,
  }) async {
    if (_usdaApiKey.isEmpty) {
      throw Exception('USDA_API_KEY missing in .env');
    }

    // Normalize meal keys to match Flask ordering/keys
    final Map<String, List<String>> normalized = {};
    meals.forEach((k, v) {
      normalized[_normalizeMealKey(k)] = v;
    });

    // Recommended calories (female, same as Flask)
    final recommended = _calculateBmrFemale(
      weightKg: weightKg,
      heightCm: heightCm,
      age: age,
      activity: activity,
    );

    final orderedMeals = const ['breakfast', 'lunch', 'snacks', 'dinner'];

    final List<MealNutrition> mealSummaries = [];
    double dayCal = 0, dayProt = 0, dayFat = 0, dayCarb = 0;

    for (final mealKey in orderedMeals) {
      final List<String> items = (normalized[mealKey] ?? const [])
          .where((s) => s.trim().isNotEmpty)
          .toList();

      final List<ParsedIngredient> parsedItems = [];
      double mCal = 0, mProt = 0, mFat = 0, mCarb = 0;

      for (final raw in items) {
        final corrected = _correctSpelling(raw);
        final usda = await _queryUsda(corrected);
        if (usda == null) {
          dev.log('USDA not found', name: 'NutritionService', error: {
            'meal': mealKey, 'item': raw, 'corrected': corrected,
          });
          continue;
        }

        final n = NutritionInfo(
          calories: usda['kcal'] ?? 0.0,
          protein: usda['protein'] ?? 0.0,
          fat: usda['fat'] ?? 0.0,
          carbs: usda['carbs'] ?? 0.0,
        );

        parsedItems.add(ParsedIngredient(
          name: (usda['name'] ?? corrected).toString(),
          amount: 1.0,
          unit: 'serving',
          nutrition: n,
        ));

        mCal += n.calories;
        mProt += n.protein;
        mFat  += n.fat;
        mCarb += n.carbs;
      }

      dayCal += mCal; dayProt += mProt; dayFat += mFat; dayCarb += mCarb;

      mealSummaries.add(
        MealNutrition(
          meal: mealKey,
          items: parsedItems,
          totals: NutritionInfo(
            calories: _round2(mCal),
            protein: _round2(mProt),
            fat: _round2(mFat),
            carbs: _round2(mCarb),
          ),
        ),
      );
    }

    return NutritionData(
      recommendedCalories: recommended,
      dailyTotals: NutritionInfo(
        calories: _round2(dayCal),
        protein: _round2(dayProt),
        fat: _round2(dayFat),
        carbs: _round2(dayCarb),
      ),
      meals: mealSummaries,
    );
  }

  /// ===================== USDA SEARCH (first hit, like Flask) =====================
  static Future<Map<String, dynamic>?> _queryUsda(String food) async {
    try {
      final uri = Uri.parse(_usdaSearchUrl).replace(queryParameters: {
        'api_key': _usdaApiKey,
        'query': food,
        'pageSize': '1',
      });

      final resp = await http.get(uri).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        dev.log('USDA non-200', name: 'NutritionService', error: resp.body);
        return null;
      }

      final root = jsonDecode(resp.body) as Map<String, dynamic>;
      final foods = (root['foods'] as List?) ?? const [];
      if (foods.isEmpty) return null;

      final item = foods[0] as Map<String, dynamic>;
      final nutrients = (item['foodNutrients'] as List?) ?? const [];

      double kcal = 0, protein = 0, carbs = 0, fat = 0;
      for (final n in nutrients) {
        final name = (n['nutrientName'] ?? '').toString().toLowerCase();
        final val  = ((n['value'] as num?) ?? 0).toDouble();

        if (name.contains('energy')) {
          kcal = val;
        } else if (name.contains('protein')) {
          protein = val;
        } else if (name.contains('carbohydrate')) {
          carbs = val;
        } else if (name.contains('fat') || name.contains('lipid')) {
          fat = val;
        }
      }

      return {
        'name': (item['description'] ?? food).toString(),
        'kcal': kcal,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
      };
    } catch (e, st) {
      dev.log('USDA query error', name: 'NutritionService', error: e, stackTrace: st);
      return null;
    }
  }

  /// ===================== Spelling correction (difflib.get_close_matches) =====================
  static String _correctSpelling(String food) {
    final f = food.toLowerCase().trim();
    if (f.isEmpty) return food;
    final matches = _getCloseMatches(f, _sampleDict, n: 1, cutoff: 0.7);
    return matches.isNotEmpty ? matches.first : food;
  }

  /// Rough equivalent of Python's get_close_matches with Levenshtein similarity.
  static List<String> _getCloseMatches(String word, List<String> possibilities,
      {int n = 3, double cutoff = 0.6}) {
    final scored = <_Score>[];
    for (final p in possibilities) {
      final s = _similarity(word, p.toLowerCase());
      if (s >= cutoff) scored.add(_Score(p, s));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(n).map((e) => e.value).toList();
  }

  /// Normalized Levenshtein similarity [0..1]
  static double _similarity(String a, String b) {
    final dist = _levenshtein(a, b);
    final maxLen = a.length > b.length ? a.length : b.length;
    if (maxLen == 0) return 1.0;
    return 1.0 - (dist / maxLen);
  }

  static int _levenshtein(String s, String t) {
    final m = s.length;
    final n = t.length;
    if (m == 0) return n;
    if (n == 0) return m;

    final dp = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));
    for (var i = 0; i <= m; i++) dp[i][0] = i;
    for (var j = 0; j <= n; j++) dp[0][j] = j;

    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        final cost = s[i - 1] == t[j - 1] ? 0 : 1;
        dp[i][j] = [
          dp[i - 1][j] + 1, // deletion
          dp[i][j - 1] + 1, // insertion
          dp[i - 1][j - 1] + cost, // substitution
        ].reduce((a, b) => a < b ? a : b);
      }
    }
    return dp[m][n];
  }

  /// ===================== BMR (female) same as Flask =====================
  static double _calculateBmrFemale({
    required double weightKg,
    required double heightCm,
    required int age,
    required String activity,
  }) {
    // Mifflin–St Jeor
    final bmr = 10 * weightKg + 6.25 * heightCm - 5 * age - 161;

    // Flask factors
    const factors = {
      'sedentary': 1.2,
      'light': 1.375,
      'moderate': 1.55,
      'active': 1.725,
      'very active': 1.9,
    };

    final k = activity.toLowerCase().trim();
    final factor = factors[k] ?? 1.2;
    return _round2(bmr * factor);
  }

  static String _normalizeMealKey(String key) {
    final k = key.toLowerCase().replaceAll('_', '');
    if (k == 'snack' || k == 'snacks' || k == 'quicksnack' || k == 'quicksnacks') {
      return 'snacks';
    }
    if (k == 'breakfast' || k == 'lunch' || k == 'dinner') return k;
    return key.toLowerCase();
  }

  static double _round2(double v) => (v * 100).roundToDouble() / 100.0;

  // ====== (Optional) USDA search + single food fetch you already had ======
  static Future<List<FoodSearchResult>> searchFood(String query) async {
    final uri = Uri.parse(_usdaSearchUrl).replace(queryParameters: {
      'api_key': _usdaApiKey, 'query': query, 'pageSize': '10',
    });
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to search food: ${response.statusCode}');
    }
    final data = json.decode(response.body);
    final foods = (data['foods'] as List?) ?? const [];
    return foods.map((food) => FoodSearchResult.fromJson(food)).toList();
  }

  static Future<NutritionInfo> getFoodNutrition(int fdcId) async {
    final uri = Uri.parse('https://api.nal.usda.gov/fdc/v1/food/$fdcId')
        .replace(queryParameters: {'api_key': _usdaApiKey});
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to get nutrition info: ${response.statusCode}');
    }
    final data = json.decode(response.body);
    return NutritionInfo.fromUsdaJson(data);
  }
}

/// ===================== Models (unchanged shapes) =====================
class FoodSearchResult {
  final int fdcId;
  final String description;
  final String? brandOwner;
  final List<FoodNutrient> foodNutrients;

  FoodSearchResult({
    required this.fdcId,
    required this.description,
    this.brandOwner,
    required this.foodNutrients,
  });

  factory FoodSearchResult.fromJson(Map<String, dynamic> json) {
    return FoodSearchResult(
      fdcId: json['fdcId'] ?? 0,
      description: json['description'] ?? '',
      brandOwner: json['brandOwner'],
      foodNutrients: (json['foodNutrients'] as List?)
          ?.map((n) => FoodNutrient.fromJson(n))
          .toList() ??
          [],
    );
  }
}

class FoodNutrient {
  final String nutrientName;
  final double value;
  final String unitName;

  FoodNutrient({
    required this.nutrientName,
    required this.value,
    required this.unitName,
  });

  factory FoodNutrient.fromJson(Map<String, dynamic> json) {
    return FoodNutrient(
      nutrientName: json['nutrientName'] ?? '',
      value: (json['value'] ?? 0).toDouble(),
      unitName: json['unitName'] ?? '',
    );
  }
}

class ParsedIngredient {
  final String name;
  final double amount;
  final String unit;
  final NutritionInfo? nutrition;

  const ParsedIngredient({
    required this.name,
    required this.amount,
    required this.unit,
    this.nutrition,
  });

  factory ParsedIngredient.fromJson(Map<String, dynamic> json) {
    return ParsedIngredient(
      name: json['name'] ?? '',
      amount: (json['amount'] ?? 1).toDouble(),
      unit: (json['unit'] ?? 'serving').toString(),
      nutrition: json['nutrition'] != null
          ? NutritionInfo.fromSpoonJson(json['nutrition']) // kept for compatibility
          : null,
    );
  }
}

class NutritionInfo {
  final double calories;
  final double protein;
  final double fat;
  final double carbs;

  const NutritionInfo({
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbs,
  });

  factory NutritionInfo.fromUsdaJson(Map<String, dynamic> json) {
    final nutrients = json['foodNutrients'] as List? ?? [];

    double getVal(bool Function(String) match) {
      for (final n in nutrients) {
        final name = (n['nutrient']?['name'] ?? n['nutrientName'] ?? '')
            .toString()
            .toLowerCase();
        if (match(name)) {
          return ((n['amount'] ?? n['value'] ?? 0) as num).toDouble();
        }
      }
      return 0.0;
    }

    return NutritionInfo(
      calories: getVal((s) => s.contains('energy')),
      protein: getVal((s) => s.contains('protein')),
      fat: getVal((s) => s.contains('fat') || s.contains('lipid')),
      carbs: getVal((s) => s.contains('carbohydrate')),
    );
  }

  // Kept for compatibility if you ever parse Spoon objects elsewhere.
  factory NutritionInfo.fromSpoonJson(Map<String, dynamic> json) {
    double getVal(String key) {
      final nutrients = json['nutrients'] as List? ?? [];
      final nutrient = nutrients.firstWhere(
            (n) => n['name'].toString().toLowerCase() == key.toLowerCase(),
        orElse: () => {'amount': 0.0},
      );
      return (nutrient['amount'] ?? 0).toDouble();
    }

    return NutritionInfo(
      calories: getVal('calories'),
      protein: getVal('protein'),
      fat: getVal('fat'),
      carbs: getVal('carbohydrates'),
    );
  }

  Map<String, dynamic> toJson() => {
    'kcal': calories,
    'protein': protein,
    'fat': fat,
    'carbs': carbs,
  };
}

class MealNutrition {
  final String meal; // 'breakfast' | 'lunch' | 'snacks' | 'dinner'
  final List<ParsedIngredient> items;
  final NutritionInfo totals;

  const MealNutrition({
    required this.meal,
    required this.items,
    required this.totals,
  });

  Map<String, dynamic> toJson() => {
    'meal': meal,
    'totals': totals.toJson(),
    'items': items
        .map((e) => {
      'name': e.name,
      'amount': e.amount,
      'unit': e.unit,
      'nutrition': e.nutrition?.toJson(),
    })
        .toList(),
  };
}

class NutritionData {
  final double recommendedCalories;
  final NutritionInfo dailyTotals;
  final List<MealNutrition> meals;

  const NutritionData({
    required this.recommendedCalories,
    required this.dailyTotals,
    required this.meals,
  });

  Map<String, dynamic> toJson() => {
    'recommendedCalories': recommendedCalories,
    'dailyTotals': dailyTotals.toJson(),
    'meals': meals.map((m) => m.toJson()).toList(),
  };
}

/// tiny helper for get_close_matches
class _Score {
  final String value;
  final double score;
  _Score(this.value, this.score);
}
