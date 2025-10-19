// lib/health_check_module.dart
// ----------------------------------------------------------
// REQUIREMENTS (pubspec.yaml)
// (same as your original)
// ----------------------------------------------------------

import 'dart:async';
import 'dart:math';

import 'package:famina/navigation_menu.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ===============================
// Models
// ===============================
class _BadgeStyle {
  final Color bg;
  final Color fg;
  const _BadgeStyle(this.bg, this.fg);
}

/// Maps indicator/status text → chip colors
/// NOTE: As you requested for thyroid, Normal/Low = green, Moderate = orange, High = red.
/// "Ambiguous" is treated as orange (attention).
_BadgeStyle _badgeStyleFor(String raw, {bool hyperAsOrange = true}) {
  final s = (raw).toString().trim().toLowerCase();

  // Generic risk levels
  if (s.contains('high')) {
    return const _BadgeStyle(Color(0xFFFFE8EA), Color(0xFFB90F3A)); // red
  }
  if (s.contains('moderate') || s.contains('medium') || s.contains('borderline')) {
    return const _BadgeStyle(Color(0xFFFFF3E0), Color(0xFF9C6A00)); // orange
  }
  if (s.contains('low') || s.contains('none') || s.contains('not detected') || s.contains('normal function')) {
    return const _BadgeStyle(Color(0xFFEAF7EE), Color(0xFF1B7F41)); // green
  }

  // Thyroid-specific labels (kept for compatibility)
  if (s.contains('normal')) {
    return const _BadgeStyle(Color(0xFFEAF7EE), Color(0xFF1B7F41)); // green
  }
  if (s.contains('hypo')) {
    // falls back to generic high/moderate mapping above, but safe color if just label
    return const _BadgeStyle(Color(0xFFFFF3E0), Color(0xFF9C6A00));
  }
  if (s.contains('hyper')) {
    return hyperAsOrange
        ? const _BadgeStyle(Color(0xFFFFF3E0), Color(0xFF9C6A00))   // orange (your ask)
        : const _BadgeStyle(Color(0xFFFFE8EA), Color(0xFFB90F3A));  // red (optional)
  }

  // Ambiguous case
  if (s.contains('ambiguous')) {
    return const _BadgeStyle(Color(0xFFFFF3E0), Color(0xFF9C6A00)); // orange
  }

  // Fallback neutral
  return _BadgeStyle(Colors.black.withOpacity(0.06), Colors.black87);
}

class ConditionResult {
  final String name; // e.g., anemia, pcos, thyroid, endometriosis
  final String indicator; // "Low" | "Moderate" | "High" or custom labels like "High Hypothyroid Risk"
  final List<String> reasons; // bullets for UI
  final double? percentage; // kept internal; not shown to users

  ConditionResult({
    required this.name,
    required this.indicator,
    required this.reasons,
    this.percentage,
  });
}

class HealthCheckResult {
  final List<ConditionResult> conditions;
  final String? summary; // server summary line (we don't render it to avoid %)
  final String? recommendation; // Gemini-generated

  HealthCheckResult({required this.conditions, this.summary, this.recommendation});
}

// ===============================
// Services: API
// ===============================
class HealthApiService {
  final Dio _dio;
  final String baseUrl;
  final String? fullPredictUrl;

  HealthApiService({
    required this.baseUrl,
    this.fullPredictUrl,
  }) : _dio = Dio(
    BaseOptions(
      headers: {'Content-Type': 'application/json'},
      validateStatus: (_) => true,
      connectTimeout: const Duration(seconds: 90),
      receiveTimeout: const Duration(seconds: 90),
    ),
  );

  Future<Map<String, dynamic>> predictAllWithDefaults(Map<String, dynamic> payload) async {
    final url = fullPredictUrl ?? ('$baseUrl/predict_all_with_defaults');
    // ignore: avoid_print
    print('POST -> $url');
    final res = await _dio.post(url, data: payload);
    if (res.statusCode != 200) {
      throw Exception('API ${res.statusCode}: ${res.data}');
    }
    return (res.data as Map<String, dynamic>);
  }
}

// ===============================
// Services: Gemini (reads .env)
// ===============================
class GeminiService {
  final GenerativeModel? _model;

  GeminiService(String apiKey)
      : _model = (apiKey.isNotEmpty)
      ? GenerativeModel(
    model: 'gemini-2.0-flash', // keep as requested
    apiKey: apiKey,
  )
      : null;

  Future<String> makeRecommendation({
    required String age,
    required String bmi,
    required Map<String, Map<String, dynamic>> details,
  }) async {
    if (_model == null) return '';

    final sb = StringBuffer()
      ..writeln('User profile: age=$age, BMI=$bmi.')
      ..writeln("""
You are Famina AI, a compassionate women’s health assistant specializing in menstrual wellness, hormonal balance, and lifestyle guidance.  
Your role is to give clear, supportive, and non-diagnostic lifestyle suggestions based on user indicators.

Guidelines:
1. Provide strictly 2–4 concise bullet points only — do not exceed this limit.  
2. Keep tone empathetic, culturally sensitive, and non-judgmental.  
3. If risk appears serious, recommend consulting a clinician and clearly mention the expert in **bold letters** (e.g., **Gynecologist**, **Endocrinologist**, **Nutritionist**, **Hematologist**).  
4. For activity, specify exact forms like brisk walking, cycling, or yoga asanas (e.g., **Surya Namaskar**, **Baddha Konasana**).  
5. If recommending fruits/vegetables, specify exact items and Indian, affordable foods (e.g., spinach, lentils, curd, coconut water, fruits, jaggery).  
6. Do not give medical claims, prescriptions, or diagnostics.  
7. Never include probabilities, technical reasoning, or confidence scores.  
8. Keep the entire response supportive, easy to read, and under 300 words.

Example Output:
• Try light walking or yoga poses such as **Baddha Konasana** and **Balasana** to ease cramps.  
• Include **iron-rich Indian foods** like spinach, lentils, jaggery, and dates to reduce fatigue.  
• Practice **deep breathing or meditation** to calm stress and mood swings.  
• If symptoms persist, consult a **Gynecologist**.  
""")
      ..writeln('Respond in Markdown with bullets like "* **Heading**: explanation".')
      ..writeln('\nIndicators detail (thyroid can be Ambiguous/Hyper/Hypo/Low):');

    details.forEach((k, v) {
      final indicator = v['indicator'];
      final reasons = (v['reasons'] as List).join('; ');
      sb.writeln('$k -> indicator: $indicator; reasons: $reasons');
    });

    try {
      final resp = await _model!.generateContent([Content.text(sb.toString())]);
      return resp.text?.trim() ?? '';
    } catch (e) {
      // ignore: avoid_print
      print('Gemini recommendation failed: $e');
      return '';
    }
  }
}

// ===============================
// Controller
// ===============================
class HealthCheckController extends GetxController {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;
  DateTime? _lastPrefillAt;
  final HealthApiService api;
  final GeminiService gemini;
  HealthCheckController({required this.api, required this.gemini});

  // --- Form State ---
  final age = RxnInt();        // no default
  final bmi = RxnDouble();     // no default
  final isPrefilling = true.obs;

  // Menstrual/flow & general
  final cycleRegular = true.obs; // true=regular, false=irregular
  final flow = 'Normal'.obs; // Light/Normal/Heavy

  // Severity chips
  final cramps = 'Never'.obs; // Never/Mild/Moderate/Severe  (pelvic pain during periods)
  final fatigueDizzyWeak = 'Never'.obs; // Never/Sometimes/Often (fatigue + breathing/dizziness)
  final periodBloating = 'Never'.obs; // Never/Sometimes/Often
  final dyspareuniaBowelPain = 'Never'.obs; // Never/Occasionally/Frequently
  final interCoursePain = 'Never'.obs; // Never/Occasionally/Frequently

  // Sleep
  final sleepLessThan6 = false.obs;

  // PCOS Indicators
  final hairGrowthYes = false.obs;
  final acneSkinYes = false.obs;
  final weightGainYes = false.obs;
  final sugarCravingsYes = false.obs;
  final weightLossDifficultyYes = false.obs;
  final hungerAfterEatingYes = false.obs;

  // Anemia Indicators
  final nailsHairYes = false.obs; // brittle nails / hair loss
  final iceCravingsYes = false.obs; // pica
  final tiredAfterRestYes = false.obs;
  final coldIntoleranceYes = false.obs; // 🔁 used by Thyroid-Hypo too

  // Thyroid Indicators (reworked)
  final heatIntoleranceYes = false.obs;        // Hyper
  final constipationYes = false.obs;           // Hypo (part of derived flag too)
  final drySkinYes = false.obs;                // (kept; still contributes to backend's constipation_yes)
  final regularAnxietyYes = false.obs;         // Hyper (renamed from heartRateTremorsYes)
  final puffyEyesYes = false.obs;              // Hypo (new)

  // Endometriosis Indicators
  final infertilityYes = false.obs;
  final intercoursePainYes = false.obs;

  // --- Prefill from Firestore ---
  @override
  void onInit() {
    super.onInit();

    // 1) Start listening to auth changes — reattach user doc listener on login switch.
    FirebaseAuth.instance.authStateChanges().listen((user) {
      _attachUserDocListener();
    });

    // 2) Also do an immediate fetch so first paint shows values ASAP.
    refreshProfile(); // public method; see below
  }



  // Public: call this to force a Firestore fetch now (used on page-enter & pull-to-refresh)
  Future<void> refreshProfile() async {
    isPrefilling.value = true;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final doc = await FirebaseFirestore.instance.collection('Users').doc(uid).get();
      if (!doc.exists) return;
      final data = doc.data() ?? {};

      // Age
      final num? ageNum = data['age'] is num ? data['age'] as num : null;
      if (ageNum != null) {
        age.value = ageNum.toInt();
      } else if (data['age'] is String) {
        final n = int.tryParse(data['age']);
        if (n != null) age.value = n;
      }

      // BMI (metric preferred; fallback imperial)
      double? calcBMI;
      final num? weightKg = data['weight_kg'] is num ? data['weight_kg'] as num : null;
      final num? heightCm = data['height_cm'] is num ? data['height_cm'] as num : null;
      if (weightKg != null && heightCm != null && heightCm > 0) {
        final hM = heightCm / 100.0;
        calcBMI = (weightKg / (hM * hM)).toDouble();
      } else {
        final num? weightLb = data['weight_lb'] is num ? data['weight_lb'] as num : null;
        final num? heightIn = data['height_in'] is num ? data['height_in'] as num : null;
        if (weightLb != null && heightIn != null && heightIn > 0) {
          calcBMI = (703.0 * weightLb / (heightIn * heightIn)).toDouble();
        }
      }
      if (calcBMI != null && calcBMI.isFinite) {
        bmi.value = double.parse(calcBMI.toStringAsFixed(1));
      }

      _lastPrefillAt = DateTime.now();
    } catch (e) {
      // ignore: avoid_print
      print('refreshProfile failed: $e');
    } finally {
      isPrefilling.value = false;
    }
  }


  // Attaches a realtime listener so Age/BMI update if the user doc changes while page is open.
  void _attachUserDocListener() {
    _userDocSub?.cancel(); // clean any previous
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _userDocSub = FirebaseFirestore.instance
        .collection('Users')
        .doc(uid)
        .snapshots()
        .listen((snap) {
      if (!snap.exists) return;
      final data = snap.data() ?? {};

      // age
      final num? ageNum = data['age'] is num ? data['age'] as num : null;
      if (ageNum != null) {
        age.value = ageNum.toInt();
      } else if (data['age'] is String) {
        final n = int.tryParse(data['age']);
        if (n != null) age.value = n;
      }

      // bmi
      double? calcBMI;
      final num? weightKg = data['weight_kg'] is num ? data['weight_kg'] as num : null;
      final num? heightCm = data['height_cm'] is num ? data['height_cm'] as num : null;
      if (weightKg != null && heightCm != null && heightCm > 0) {
        final hM = heightCm / 100.0;
        calcBMI = (weightKg / (hM * hM)).toDouble();
      } else {
        final num? weightLb = data['weight_lb'] is num ? data['weight_lb'] as num : null;
        final num? heightIn = data['height_in'] is num ? data['height_in'] as num : null;
        if (weightLb != null && heightIn != null && heightIn > 0) {
          calcBMI = (703.0 * weightLb / (heightIn * heightIn)).toDouble();
        }
      }
      if (calcBMI != null && calcBMI.isFinite) {
        bmi.value = double.parse(calcBMI.toStringAsFixed(1));
      }

      isPrefilling.value = false; // any live update means we’re done “loading”
    });
  }

  @override
  void onClose() {
    _userDocSub?.cancel();
    super.onClose();
  }


  // --- Duplicate-question mapping (for clarity/documentation) ---
  static const Map<String, List<String>> questionMapping = {
    'flow_volume': ['Anemia', 'Endometriosis'],
    'tired_after_rest': ['Anemia', 'Thyroid'],
    'brittle_nails': ['Anemia', 'Thyroid'],
    'cold_intolerance': ['Anemia', 'Thyroid'], // shared; appears once in UI
    'recent_weight_gain': ['PCOS', 'Thyroid'],
    'fatigue_score': ['Anemia', 'Endometriosis'],
    // 'constipation_yes' is derived from two separate toggles (constipation OR dry skin)
  };

  // Helpers: map to ints
  int _lvl3(String v) {
    switch (v) {
      case 'Sometimes':
        return 1;
      case 'Often':
        return 2;
      default:
        return 0;
    }
  }

  int _lvlPain(String v) {
    switch (v) {
      case 'Mild':
        return 1;
      case 'Moderate':
      case 'Severe':
        return 2;
      default:
        return 0;
    }
  }

  int _lvlOccasion(String v) {
    switch (v) {
      case 'Occasionally':
        return 1;
      case 'Frequently':
        return 2;
      default:
        return 0;
    }
  }

  int _flowHeavy() => flow.value == 'Heavy' ? 1 : 0;

  // Build payload for /predict_all_with_defaults
  Map<String, dynamic> buildPayload() {
    if (age.value == null || bmi.value == null) {
      throw Exception('Please wait while we load your profile (Age/BMI).');
    }

    final bmiOverweight = bmi.value! >= 25 ? 1 : 0;

    return {
      // common
      'age': age.value!,
      'BMI': double.parse(bmi.value!.toStringAsFixed(1)),

      // anemia features
      'flow_volume_heavy': _flowHeavy(),
      'fatigue_score': _lvl3(fatigueDizzyWeak.value),
      'breathing_dizziness_score': _lvl3(fatigueDizzyWeak.value), // shares control with fatigue
      'nails_hair_yes': nailsHairYes.value ? 1 : 0,
      'ice_cravings_yes': iceCravingsYes.value ? 1 : 0,
      'tired_after_rest_yes': tiredAfterRestYes.value ? 1 : 0,
      'cold_intolerance': coldIntoleranceYes.value ? 1 : 0, // also used by Thyroid-Hypo (local)

      // pcos features
      'cycle_regularity_irregular': cycleRegular.value ? 0 : 1,
      'hair_growth_yes': hairGrowthYes.value ? 1 : 0,
      'acne_skin_yes': acneSkinYes.value ? 1 : 0,
      'weight_gain_yes': weightGainYes.value ? 1 : 0,
      'sugar_cravings_yes': sugarCravingsYes.value ? 1 : 0,
      'weight_loss_difficulty_yes': weightLossDifficultyYes.value ? 1 : 0,
      'hunger_after_eating_yes': hungerAfterEatingYes.value ? 1 : 0,
      'bmi_overweight': bmiOverweight,

      // thyroid features for backend (kept as-is)
      'heat_intolerance': heatIntoleranceYes.value ? 1 : 0,
      'constipation_yes': (constipationYes.value || drySkinYes.value) ? 1 : 0,
      'heart_rate_tremors_yes': regularAnxietyYes.value ? 1 : 0,
      'sleep_less_than_6': sleepLessThan6.value ? 1 : 0,

      // endometriosis features
      'pelvic_pain_score': _lvlPain(cramps.value),
      'intercourse_pain_score': _lvlOccasion(interCoursePain.value),
      'bowel_movement_pain': _lvlOccasion(dyspareuniaBowelPain.value),
      'bloating_score': _lvl3(periodBloating.value),

      // Will stay false if not shown (age ≤ 30)
      'infertility_yes': infertilityYes.value ? 1 : 0,
      'intercourse_pain_yes': intercoursePainYes.value ? 1 : 0,
    };
  }

  /// Remove any model probability/confidence lines from reasons (and stray % mentions).
  List<String> _sanitizeReasons(List<String> reasons) {
    final blocked = RegExp(
      r'(model\s+(high-?risk\s+)?probability|model\s+confidence|\b\d+(\.\d+)?\s*%)',
      caseSensitive: false,
    );
    return reasons.where((r) => !blocked.hasMatch(r)).toList();
  }

  // ======= New: Apply your Python assess_health logic locally =======
  Map<String, String> _computeLocalIndicators() {
    // ---------------- PCOS ----------------
    final pcosBools = <bool>[
      !cycleRegular.value, // irregular_cycles
      hairGrowthYes.value,
      acneSkinYes.value,
      sugarCravingsYes.value,
      weightLossDifficultyYes.value,
      hungerAfterEatingYes.value,
      weightGainYes.value,
    ];
    final pcosCount = pcosBools.where((v) => v).length;
    String pcosLabel;
    if (pcosCount >= 3) {
      pcosLabel = 'High';
    } else if (pcosCount == 2) {
      pcosLabel = 'Moderate';
    } else {
      pcosLabel = 'Low';
    }

    // ---------------- Anemia ----------------
    int anemiaCount = 0;
    if (_flowHeavy() == 1) anemiaCount += 1;
    if (_lvl3(fatigueDizzyWeak.value) > 0) anemiaCount += 1; // fatigue or dizziness proxy
    if (nailsHairYes.value) anemiaCount += 1; // brittle nails
    if (iceCravingsYes.value) anemiaCount += 1; // pica
    if (tiredAfterRestYes.value) anemiaCount += 1;

    String anemiaLabel;
    if (anemiaCount >= 3) {
      anemiaLabel = 'High';
    } else if (anemiaCount == 2) {
      anemiaLabel = 'Moderate';
    } else {
      anemiaLabel = 'Low';
    }

    // ---------------- Thyroid ----------------
    // Hypo: cold intolerance, constipation/dry skin, puffy eyes
    final hypoCount = [
      coldIntoleranceYes.value,
      (constipationYes.value || drySkinYes.value),
      puffyEyesYes.value,
    ].where((v) => v).length;

    // Hyper: heat intolerance, regular anxiety, sleep < 6h
    final hyperCount = [
      heatIntoleranceYes.value,
      regularAnxietyYes.value,
      sleepLessThan6.value,
    ].where((v) => v).length;

    String thyroidLabel;
    if (hypoCount >= 2 && hyperCount >= 2) {
      thyroidLabel = 'Ambiguous – Please do TSH/T3/T4 tests';
    } else if (hypoCount >= 2) {
      thyroidLabel = 'High Hypothyroid Risk';
    } else if (hyperCount >= 2) {
      thyroidLabel = 'High Hyperthyroid Risk';
    } else if (hypoCount == 1) {
      thyroidLabel = 'Moderate Hypothyroid Risk';
    } else if (hyperCount == 1) {
      thyroidLabel = 'Moderate Hyperthyroid Risk';
    } else {
      thyroidLabel = 'Low Thyroid Risk';
    }

    // ---------------- Endometriosis ----------------
    int endoCount = 0;

// 1. Pelvic pain during periods (cramps)
    if (_lvlPain(cramps.value) >= 1) endoCount += 1; // Any pain level (Mild/Moderate/Severe)

// 2. Intercourse pain
    if (interCoursePain.value == 'Occasionally' ||
        interCoursePain.value == 'Frequently' ||
        intercoursePainYes.value) {
      endoCount += 1;
    }

// 3. Bowel movement pain
    if (_lvlOccasion(dyspareuniaBowelPain.value) > 0) endoCount += 1;

// 4. Period bloating
    if (_lvl3(periodBloating.value) > 0) endoCount += 1;

    String endoLabel;
    if (endoCount >= 3) {
      endoLabel = 'High';
    } else if (endoCount == 2) {
      endoLabel = 'Moderate';
    } else {
      endoLabel = 'Low';
    }

    return {
      'pcos': pcosLabel,
      'anemia': anemiaLabel,
      'thyroid': thyroidLabel,
      'endometriosis': endoLabel,
    };
  }

  List<String> _thyroidReasonsForUI() {
    final reasons = <String>[];
    if (coldIntoleranceYes.value) reasons.add('Yes to cold intolerance');
    if (constipationYes.value || drySkinYes.value) reasons.add('Constipation and/or dry skin');
    if (puffyEyesYes.value) reasons.add('Puffy eyes / facial swelling');
    if (heatIntoleranceYes.value) reasons.add('Yes to heat intolerance');
    if (regularAnxietyYes.value) reasons.add('Regular anxiety');
    if (sleepLessThan6.value) reasons.add('Sleep less than 6 hours');
    return reasons;
  }

  // Replace the submitAndGetResults() method in HealthCheckController
// Starting around line 320 in health_check_module.dart

  Future<HealthCheckResult> submitAndGetResults() async {
    final payload = buildPayload();
    final localIndicators = _computeLocalIndicators();

    // Call API for details (to harvest sanitized reasons, summary)
    final apiRes = await api.predictAllWithDefaults(payload);
    final rawDetails = (apiRes['details'] as Map<String, dynamic>? ?? {});
    final conditions = <ConditionResult>[];

    // FIXED: Always prioritize local indicators, never fall back to API indicators
    // Add models with API reasons but ALWAYS use local labels
    for (final key in ['anemia', 'pcos', 'endometriosis']) {
      final d = rawDetails[key] as Map<String, dynamic>?;
      final apiReasons = _sanitizeReasons(((d?['reasons'] as List?)?.cast<String>()) ?? []);

      // CRITICAL FIX: Use local indicator directly, no fallback to API
      final indicator = localIndicators[key] ?? 'Low';

      final pct = (d?['high_risk_percentage'] is num) ? (d!['high_risk_percentage'] as num).toDouble() : null;

      conditions.add(
        ConditionResult(
          name: key,
          indicator: indicator,
          reasons: apiReasons.isEmpty ? ['No specific indicators detected'] : apiReasons,
          percentage: pct,
        ),
      );
    }

    // Thyroid — single card using your logic (Ambiguous/Hyper/Hypo/Low)
    final thyroidIndicator = localIndicators['thyroid']!;
    final thyroidReasons = _thyroidReasonsForUI();
    conditions.add(
      ConditionResult(
        name: 'Thyroid',
        indicator: thyroidIndicator,
        reasons: thyroidReasons.isEmpty ? ['No thyroid indicators detected'] : thyroidReasons.take(4).toList(),
        percentage: null,
      ),
    );

    // Prepare details for Gemini (override thyroid & indicators)
    final detailsForGemini = <String, Map<String, dynamic>>{};
    rawDetails.forEach((k, v) {
      final vv = (v as Map<String, dynamic>).map((kk, vv) => MapEntry(kk, vv));
      final sanitized = <String, dynamic>{
        ...vv,
        'reasons': _sanitizeReasons(((vv['reasons'] as List?)?.cast<String>()) ?? []),
        // FIXED: Always override with local indicators
        'indicator': localIndicators[k] ?? vv['indicator'],
      };
      detailsForGemini[k] = sanitized;
    });

    // ensure thyroid reflects single-card indicator + reasons
    detailsForGemini.remove('thyroid_hypo');
    detailsForGemini.remove('thyroid_hyper');
    detailsForGemini['thyroid'] = {
      'indicator': thyroidIndicator,
      'reasons': thyroidReasons,
    };

    final recText = await gemini.makeRecommendation(
      age: age.value!.toString(),
      bmi: bmi.value!.toStringAsFixed(1),
      details: detailsForGemini,
    );

    await _saveToFirestore(
      {
        ...apiRes,
        'local_indicators': localIndicators,
      },
      recText,
    );

    // Order: Anemia, PCOS, Thyroid, Endometriosis
    final ordered = <String>['anemia', 'pcos', 'Thyroid', 'endometriosis'];
    conditions.sort((a, b) => ordered.indexOf(a.name).compareTo(ordered.indexOf(b.name)));

    return HealthCheckResult(
      conditions: conditions,
      summary: apiRes['summary'] as String?,
      recommendation: recText,
    );
  }



  Future<void> _saveToFirestore(Map<String, dynamic> apiRes, String recommendation) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
      final col = FirebaseFirestore.instance.collection('Health Check');
      final input = buildPayload(); // may throw if age/bmi missing
      await col.add({
        'uid': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'input': input,
        'apiResponse': apiRes,
        'recommendation': recommendation,
      });
    } catch (e) {
      // log, but don’t crash the flow
      // ignore: avoid_print
      log('Save failed: $e' as num);
    }
  }

}

// ===============================
// Formatter for Gemini recommendation
// ===============================
List<String> formatRecommendation(String raw) {
  if (raw.isEmpty) return [];

  final lines = raw
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  final boldRegex = RegExp(r'\*\*([^*]+)\*\*');
  final result = <String>[];

  for (var line in lines) {
    // Skip intro/filler lines like "Okay, I understand..." or lines without bullets/bold
    if (line.toLowerCase().contains('okay') ||
        line.toLowerCase().contains('here\'s a response') ||
        line.toLowerCase().contains('based on your indicators') ||
        (!line.startsWith('*') && !line.startsWith('•') && !boldRegex.hasMatch(line))) {
      continue;
    }

    // Remove bullet markers (* or •)
    var cleanLine = line.replaceFirst(RegExp(r'^[\*•]\s*'), '');

    final match = boldRegex.firstMatch(cleanLine);
    if (match != null) {
      final heading = match.group(1)!.trim();
      final rest = cleanLine.replaceFirst(match.group(0)!, '').trim();
      if (rest.isEmpty) {
        result.add(heading);
      } else {
        final cleanedRest = rest.replaceFirst(RegExp(r'^[:\-–—]\s*'), '');
        result.add('$heading — $cleanedRest');
      }
    } else {
      result.add(cleanLine);
    }
  }
  return result;
}

// ===============================
// UI: Tiny shimmer (no package)
// ===============================
class ShimmerBox extends StatefulWidget {
  final double width, height;
  const ShimmerBox({super.key, required this.width, required this.height});

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
  AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: LinearGradient(
              begin: Alignment(-1 + 2 * _c.value, 0),
              end: Alignment(1 + 2 * _c.value, 0),
              colors: [Colors.grey.shade200, Colors.grey.shade300, Colors.grey.shade200],
              stops: const [0.2, 0.5, 0.8],
            ),
          ),
        );
      },
    );
  }
}

// ===============================
// UI: Survey Page (flat list, no headers; asks each question once)
// ===============================
class HealthSurveyPage extends StatefulWidget {
  const HealthSurveyPage({super.key});

  @override
  State<HealthSurveyPage> createState() => _HealthSurveyPageState();
}

class _HealthSurveyPageState extends State<HealthSurveyPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      c.isPrefilling.value = true;
      await c.refreshProfile();
    });
  }



  final c = Get.find<HealthCheckController>();

  Widget _chipRow(String label, List<String> options, RxString sel) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: options
            .map(
              (o) => Obx(
                () => ChoiceChip(
              label: Text(o),
              selected: sel.value == o,
              onSelected: (_) => sel.value = o,
            ),
          ),
        )
            .toList(),
      ),
    ],
  );

  Widget _boolRow(String label, RxBool sel) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Expanded(child: Text(label, maxLines: 2)),
      Obx(() => Switch(value: sel.value, onChanged: (v) => sel.value = v)),
    ],
  );

  Widget _statPill({required String label, String? value, bool loading = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.2)),
          if (loading)
            const ShimmerBox(width: 36, height: 14)
          else
            Text(value ?? '-', style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  String _formatBmiForDisplay(double? v) {
    if (v == null) return '-';
    return v.toStringAsFixed(1);
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: () => Get.offAll(NavigationMenu()), icon: const Icon(Icons.arrow_back)),
        title: const Text('Quick Symptom Check'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          c.isPrefilling.value = true;
          await c.refreshProfile();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Common stats: Age & BMI
            Row(
              children: [
                Expanded(
                  child: Obx(() => _statPill(
                    label: 'Age',
                    value: c.age.value?.toString(),
                    loading: c.age.value == null && c.isPrefilling.value,
                  )),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Obx(() => _statPill(
                    label: 'BMI',
                    value: _formatBmiForDisplay(c.bmi.value),
                    loading: c.bmi.value == null && c.isPrefilling.value,
                  )),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ——— PCOS Model ———
            Row(
              children: [
                const Text('Cycles Regular?'),
                const SizedBox(width: 8),
                Obx(() => Switch(value: c.cycleRegular.value, onChanged: (v) => c.cycleRegular.value = v)),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Flow volume'),
            Obx(
                  () => DropdownButton<String>(
                value: c.flow.value,
                items: const [
                  DropdownMenuItem(value: 'Light', child: Text('Light')),
                  DropdownMenuItem(value: 'Normal', child: Text('Normal')),
                  DropdownMenuItem(value: 'Heavy', child: Text('Heavy')),
                ],
                onChanged: (v) {
                  if (v != null) c.flow.value = v;
                },
              ),
            ),

            // ——— PCOS Model ———
            _boolRow('Do you have excessive hair growth on face, chin, or chest?', c.hairGrowthYes),
            _boolRow('Do you have acne or skin darkening?', c.acneSkinYes),
            _boolRow('Have you experienced recent weight gain?', c.weightGainYes),
            _boolRow('Do you often crave sugar?', c.sugarCravingsYes),
            // _boolRow('Do you find it difficult to lose weight?', c.weightLossDifficultyYes),
            _boolRow('Do you feel hungry even after a meal?', c.hungerAfterEatingYes),

            // ——— Anemia Model ———
            _boolRow('Do you have brittle nails or hair loss?', c.nailsHairYes),
            _boolRow('Do you crave ice or non-food items?', c.iceCravingsYes),
            _boolRow('Do you feel tired even after rest?', c.tiredAfterRestYes),

            // NOTE: Cold intolerance is asked once (here) and reused by Thyroid-Hypo scoring too.
            _boolRow('Do you feel unusually cold (cold intolerance)?', c.coldIntoleranceYes),

            // ——— Thyroid Model ———
            _boolRow('Do you feel heat intolerance?', c.heatIntoleranceYes),
            _boolRow('Do you experience constipation?', c.constipationYes),
            _boolRow('Do you have dry skin?', c.drySkinYes), // contributes to constipation rule
            _boolRow('Do you experience regular anxiety?', c.regularAnxietyYes),
            _boolRow('Do you usually sleep less than 6 hours?', c.sleepLessThan6),
            _boolRow('Do you have puffy eyes or swelling around your face?', c.puffyEyesYes),

            // ——— Endometriosis Model ———
            Obx(() {
              final a = c.age.value;
              if (a != null && a > 20) {
                return _boolRow('Infertility (Optional to answer)', c.infertilityYes);
              }
              return const SizedBox.shrink();
            }),
            // _chipRow('How often do you feel fatigued, dizzy, or weak?', ['Never', 'Sometimes', 'Often'], c.fatigueDizzyWeak),
            _chipRow('How often do you experience pelvic pain during periods?', ['Never', 'Mild', 'Moderate', 'Severe'], c.cramps),
            _chipRow('Do you experience pain during bowel movements?', ['Never', 'Occasionally', 'Frequently'], c.dyspareuniaBowelPain),
            _chipRow('How often do you feel bloating or discomfort around your period?', ['Never', 'Sometimes', 'Often'], c.periodBloating),

            // intercourse question appears for age above 20
            Obx(() {
              final a = c.age.value;
              if (a != null && a > 20) {
                return _chipRow('Do you experience pain during intercourse? (Optional to answer)',
                    ['Never', 'Occasionally', 'Frequently'], c.interCoursePain);
              }
              return const SizedBox.shrink();
            }),

            const SizedBox(height: 16),
            Obx(() {
              final ready = !c.isPrefilling.value && c.age.value != null && c.bmi.value != null;
              return ElevatedButton.icon(
                icon: const Icon(Icons.health_and_safety),
                label: const Text('Get My Health Snapshot'),
                onPressed: ready
                    ? () async {
                  FocusScope.of(context).unfocus();
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => const Center(child: CircularProgressIndicator()),
                  );
                  try {
                    final res = await c.submitAndGetResults();
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      Get.to(() => HealthResultPage(result: res));
                    }
                  } catch (e) {
                    if (context.mounted) Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
                    // ignore: avoid_print
                    print(e);
                  }
                }
                    : null,
              );
            }),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// helper: parse **bold** spans inside text
List<InlineSpan> _parseBoldSpans(String text, {TextStyle? base}) {
  final spans = <InlineSpan>[];
  // This regex matches either *word* or **word**
  final reg = RegExp(r'(\*{1,2})(.+?)\1');
  int idx = 0;

  for (final m in reg.allMatches(text)) {
    if (m.start > idx) {
      spans.add(TextSpan(text: text.substring(idx, m.start), style: base));
    }
    spans.add(TextSpan(
      text: m.group(2), // the actual text inside *...*
      style: (base ?? const TextStyle()).merge(
        const TextStyle(fontWeight: FontWeight.bold),
      ),
    ));
    idx = m.end;
  }

  if (idx < text.length) {
    spans.add(TextSpan(text: text.substring(idx), style: base));
  }

  return spans;
}

// ===============================
// UI: Result Page
// ===============================
class HealthResultPage extends StatelessWidget {
  final HealthCheckResult result;
  const HealthResultPage({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final formattedRecs = formatRecommendation(result.recommendation ?? '');

    // Detect if thyroid is present
    final hasThyroid = result.conditions.any(
          (c) => c.name.toLowerCase().contains('thyroid'),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Get.offAll(NavigationMenu()),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Your Health Snapshot'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 12),

          // ===== condition cards =====
          for (final c in result.conditions) ...[
            Card(
              color: Colors.grey.shade50,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 1.5,
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Builder(
                  builder: (_) {
                    final style = _badgeStyleFor(c.indicator, hyperAsOrange: true);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // inside the Card builder, replace the existing header Row with this:

                        Builder(
                          builder: (_) {
                            final style = _badgeStyleFor(c.indicator, hyperAsOrange: true);

                            // decide if we should move the pill to the next line
                            final bool isLongBadge =
                                c.indicator.length > 26 || c.indicator.toLowerCase().contains('ambiguous');

                            Widget badge() => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: style.bg,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: style.fg.withOpacity(0.5)),
                              ),
                              child: Text(
                                c.indicator,
                                style: TextStyle(color: style.fg, fontWeight: FontWeight.w600),
                                softWrap: true,
                                maxLines: 2, // allow wrap inside the pill
                                overflow: TextOverflow.visible,
                              ),
                            );

                            if (isLongBadge) {
                              // Title on first line, pill on the next line (left-aligned by default)
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.name[0].toUpperCase() + c.name.substring(1),
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 8),
                                  badge(),
                                ],
                              );
                            } else {
                              // Short labels stay inline
                              return Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Flexible(
                                    fit: FlexFit.loose,
                                    child: Text(
                                      c.name[0].toUpperCase() + c.name.substring(1),
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(child: badge()),
                                ],
                              );
                            }
                          },
                        ),

                        const SizedBox(height: 8),
                        const SizedBox(height: 6),
                        for (final r in c.reasons.take(3))
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('• '),
                                Expanded(child: Text(r)),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),

            // ===== thyroid disclaimer (appears right after Thyroid card) =====
            if (c.name.toLowerCase().contains('thyroid')) ...[
              const SizedBox(height: 6),
              _thyroidDisclaimerCard(),
            ],
          ],

          // ===== Personalized suggestions =====
          if (formattedRecs.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Personalized Suggestions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.indigo.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.indigo.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final suggestion in formattedRecs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• ', style: TextStyle(fontSize: 16)),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                children: _parseBoldSpans(
                                  suggestion,
                                  base: const TextStyle(fontSize: 14, color: Colors.black87),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Compact disclaimer card for Thyroid
  Widget _thyroidDisclaimerCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6), // soft amber
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE2B2)),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFF9C6A00)),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: const TextSpan(
                style: TextStyle(color: Colors.black87, fontSize: 13.5, height: 1.3),
                children: [
                  TextSpan(
                    text: 'Heads up — Thyroid notice:\n',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  TextSpan(
                    text:
                    'This is a screening based on a short symptom checklist and is not a diagnosis. '
                        'For an accurate assessment, please get appropriate tests (e.g., TSH, Free T4/T3) '
                        'and consult an ',
                  ),
                  TextSpan(text: 'Endocrinologist', style: TextStyle(fontWeight: FontWeight.w800)),
                  TextSpan(text: '. If symptoms are severe, new, or you are pregnant, seek care promptly.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===============================
// Bootstrap / DI: call this once in main()
// ===============================
void initHealthFlow() {
  final geminiApiKey = dotenv.maybeGet('GEMINI_API_KEY') ?? '';
  if (geminiApiKey.isEmpty) {
    // ignore: avoid_print
    print('⚠️ GEMINI_API_KEY missing or empty. Recommendations will be disabled.');
  }

  Get.put(
    HealthApiService(
      baseUrl: 'https://famin-api-506773688937.asia-south1.run.app',
      fullPredictUrl: 'https://famin-api-506773688937.asia-south1.run.app/predict_all_with_defaults',
    ),
    permanent: true,
  );

  Get.put(GeminiService(geminiApiKey), permanent: true);
  Get.put(HealthCheckController(api: Get.find(), gemini: Get.find()), permanent: true);
}
