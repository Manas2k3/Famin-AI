// lib/health_check_module.dart
// ----------------------------------------------------------
// REQUIREMENTS (pubspec.yaml)
// (same as your original)
// ----------------------------------------------------------

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
class ConditionResult {
  final String name; // anemia, pcos, thyroid, endometriosis
  final String indicator; // "Low Risk" | "High Risk" | "Normal Function"
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
      ..writeln(
          'Provide concise, supportive, non-diagnostic lifestyle suggestions (2-4 bullets) based on the indicators and reasons below. Avoid medical claims; recommend seeing a clinician if risk is high.')
      ..writeln('Respond in Markdown with bullets like "* **Heading**: explanation".');

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
  final HealthApiService api;
  final GeminiService gemini;
  HealthCheckController({required this.api, required this.gemini});

  // --- Form State ---
  final age = RxnInt();        // no default
  final bmi = RxnDouble();     // no default
  final isPrefilling = true.obs;

  // Section 2: Menstrual
  final menarcheAge = 13.obs;
  final cycleRegular = true.obs; // true=regular, false=irregular
  final avgCycleLenDays = 28.obs;
  final periodDays = 5.obs;
  final flow = 'Normal'.obs; // Light/Normal/Heavy
  final clottingYes = false.obs;
  final spotting = 'Never'.obs; // Never/Occasionally/Frequently

  // Section 3: General symptoms
  final cramps = 'Never'.obs; // Never/Mild/Moderate/Severe
  final fatigueDizzyWeak = 'Never'.obs; // Never/Sometimes/Often
  final mood = 'Never'.obs; // Never/Sometimes/Often
  final sleepLessThan6 = false.obs;

  // PCOS Indicators
  final hairGrowthYes = false.obs;
  final acneSkinYes = false.obs;
  final weightGainYes = false.obs;
  final fertilityIssuesYes = false.obs; // irregular ovulation/fertility issues
  final sugarCravingsYes = false.obs;
  final weightLossDifficultyYes = false.obs;
  final hungerAfterEatingYes = false.obs;

  // Anemia Indicators
  final nailsHairYes = false.obs;
  final iceCravingsYes = false.obs;

  // Thyroid Indicators
  final diagnosedThyroidBefore = false.obs;
  final tiredAfterRestYes = false.obs;
  final heartRateTremorsYes = false.obs;
  final coldIntoleranceYes = false.obs;
  final heatIntoleranceYes = false.obs;
  final constipationOrDrySkinYes = false.obs; // maps to constipation_yes

  // Endometriosis Indicators
  final chronicPelvicPain = 'Never'.obs; // Never/Occasionally/Frequently
  final dyspareuniaBowelPain = 'Never'.obs; // Never/Occasionally/Frequently
  final periodBloating = 'Never'.obs; // Never/Sometimes/Often
  final infertilityYes = false.obs;

  // Section 4 (not sent to model now)
  final exercise = '2–4 days/week'.obs;
  final junkFood = 'Occasionally'.obs;
  final familyHistory = 'Not Sure'.obs;
  final medsRecentlyYes = false.obs;

  // --- Prefill from Firestore ---
  @override
  void onInit() {
    super.onInit();
    _prefillFromFirestore();
  }

  Future<void> _prefillFromFirestore() async {
    isPrefilling.value = true;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      // Assuming collection is "Users" and doc id == uid
      final doc = await FirebaseFirestore.instance.collection('Users').doc(uid).get();
      if (!doc.exists) return;

      final data = doc.data() ?? {};

      // Age (direct or string)
      final num? ageNum = data['age'] is num ? data['age'] as num : null;
      if (ageNum != null) {
        age.value = ageNum.toInt();
      } else if (data['age'] is String) {
        final n = int.tryParse(data['age']);
        if (n != null) age.value = n;
      }

      // BMI from metric (preferred), else imperial
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
    } catch (e) {
      // ignore: avoid_print
      print('Prefill failed: $e');
    } finally {
      isPrefilling.value = false;
    }
  }

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
      'breathing_dizziness_score': _lvl3(fatigueDizzyWeak.value),
      'nails_hair_yes': nailsHairYes.value ? 1 : 0,
      'ice_cravings_yes': iceCravingsYes.value ? 1 : 0,
      'tired_after_rest_yes': tiredAfterRestYes.value ? 1 : 0,
      'cold_intolerance': coldIntoleranceYes.value ? 1 : 0,

      // pcos features
      'cycle_regularity_irregular': cycleRegular.value ? 0 : 1,
      'hair_growth_yes': hairGrowthYes.value ? 1 : 0,
      'acne_skin_yes': acneSkinYes.value ? 1 : 0,
      'weight_gain_yes': weightGainYes.value ? 1 : 0,
      'sugar_cravings_yes': sugarCravingsYes.value ? 1 : 0,
      'weight_loss_difficulty_yes': weightLossDifficultyYes.value ? 1 : 0,
      'hunger_after_eating_yes': hungerAfterEatingYes.value ? 1 : 0,
      'bmi_overweight': bmiOverweight,

      // thyroid features
      'heat_intolerance': heatIntoleranceYes.value ? 1 : 0,
      'constipation_yes': constipationOrDrySkinYes.value ? 1 : 0,
      'heart_rate_tremors_yes': heartRateTremorsYes.value ? 1 : 0,
      'sleep_less_than_6': sleepLessThan6.value ? 1 : 0,

      // endometriosis features
      'pelvic_pain_score': _lvlPain(cramps.value),
      'intercourse_pain_score': _lvlOccasion(dyspareuniaBowelPain.value),
      'bloating_score': _lvl3(periodBloating.value),
      'infertility_yes': (infertilityYes.value || fertilityIssuesYes.value) ? 1 : 0,
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

  Future<HealthCheckResult> submitAndGetResults() async {
    final payload = buildPayload();
    final apiRes = await api.predictAllWithDefaults(payload);
    final details = (apiRes['details'] as Map<String, dynamic>);
    final conditions = <ConditionResult>[];

    for (final key in ['anemia', 'pcos', 'thyroid', 'endometriosis']) {
      final d = details[key] as Map<String, dynamic>?;
      if (d == null) continue;

      String indicator;
      List<String> reasons;
      double? pct;

      if (key == 'thyroid') {
        indicator = (d['indicator'] ?? 'Normal Function') as String;
        pct = (d['predicted_class_percentage'] as num?)?.toDouble(); // kept internal
        reasons = ((d['reasons'] as List?)?.cast<String>()) ?? [];
      } else {
        indicator = (d['indicator'] ?? 'Low Risk') as String;
        pct = (d['high_risk_percentage'] as num?)?.toDouble(); // kept internal
        reasons = ((d['reasons'] as List?)?.cast<String>()) ?? [];
      }

      // 🚫 Strip confidence/probability/% lines before storing/displaying
      reasons = _sanitizeReasons(reasons);

      conditions.add(
        ConditionResult(
          name: key,
          indicator: indicator,
          reasons: reasons,
          percentage: pct,
        ),
      );
    }

    final recText = await gemini.makeRecommendation(
      age: age.value!.toString(),
      bmi: bmi.value!.toStringAsFixed(1),
      details: details.map((k, v) => MapEntry(k, (v as Map<String, dynamic>))),
    );

    await _saveToFirestore(apiRes, recText);

    return HealthCheckResult(
      conditions: conditions,
      summary: apiRes['summary'] as String?,
      recommendation: recText,
    );
  }

  Future<void> _saveToFirestore(Map<String, dynamic> apiRes, String recommendation) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
    final col = FirebaseFirestore.instance.collection('Health Check');
    await col.add({
      'uid': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'input': buildPayload(),
      'apiResponse': apiRes,
      'recommendation': recommendation,
    });
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
      .map((l) => l.startsWith('*') ? l.replaceFirst(RegExp(r'^\*\s*'), '') : l)
      .toList();

  final boldRegex = RegExp(r'\*\*([^*]+)\*\*');
  final result = <String>[];

  for (var line in lines) {
    final match = boldRegex.firstMatch(line);
    if (match != null) {
      final heading = match.group(1)!.trim();
      final rest = line.replaceFirst(match.group(0)!, '').trim();
      if (rest.isEmpty) {
        result.add(heading);
      } else {
        final cleanedRest = rest.replaceFirst(RegExp(r'^[:\-–—]\s*'), '');
        result.add('$heading — $cleanedRest');
      }
    } else {
      result.add(line);
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
// UI: Survey Page
// ===============================
class HealthSurveyPage extends StatelessWidget {
  HealthSurveyPage({super.key});
  final c = Get.find<HealthCheckController>();

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
  );

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

  // ---------- stat pill with loading ----------
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
    final s = v.toStringAsFixed(1); // e.g., 19.0
    return s.endsWith('.0') ? '${s.substring(0, s.length - 1)}.' : s; // -> 19.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          leading: IconButton(onPressed: () => Get.offAll(NavigationMenu()), icon: const Icon(Icons.arrow_back)),
          title: const Text('Quick Symptom Check')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('Menstrual Cycle'),
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

          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Cycles Regular?'),
              const SizedBox(width: 8),
              Obx(() => Switch(value: c.cycleRegular.value, onChanged: (v) => c.cycleRegular.value = v)),
              const SizedBox(width: 12),
              const Text('Flow:'),
              const SizedBox(width: 8),
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
            ],
          ),

          _sectionTitle('Symptoms & Health'),
          _chipRow('Cramps / pelvic pain during periods', ['Never', 'Mild', 'Moderate', 'Severe'], c.cramps),
          _chipRow('Fatigued / dizzy / weak', ['Never', 'Sometimes', 'Often'], c.fatigueDizzyWeak),
          _boolRow('Sleep less than 6 hours?', c.sleepLessThan6),

          _sectionTitle('PCOS Indicators'),
          _boolRow('Excessive hair growth (face/chin/chest)', c.hairGrowthYes),
          _boolRow('Acne or skin darkening', c.acneSkinYes),
          _boolRow('Recent weight gain', c.weightGainYes),
          // _boolRow('Irregular ovulation / fertility issues', c.fertilityIssuesYes),
          _boolRow('Sugar cravings', c.sugarCravingsYes),
          _boolRow('Difficulty losing weight', c.weightLossDifficultyYes),
          _boolRow('Hunger soon after eating', c.hungerAfterEatingYes),

          _sectionTitle('Anemia Indicators'),
          _boolRow('Brittle nails or frequent hair loss', c.nailsHairYes),
          _boolRow('Craving ice or non-food items (pica)', c.iceCravingsYes),

          _sectionTitle('Thyroid Indicators'),
          _boolRow('Tired even after rest', c.tiredAfterRestYes),
          _boolRow('Frequent anxiety', c.heartRateTremorsYes),
          _boolRow('Cold intolerance', c.coldIntoleranceYes),
          _boolRow('Heat intolerance', c.heatIntoleranceYes),
          _boolRow('Constipation or dry skin', c.constipationOrDrySkinYes),

          _sectionTitle('Endometriosis Indicators'),
          _chipRow('Chronic pelvic pain (outside periods)', ['Never', 'Occasionally', 'Frequently'], c.chronicPelvicPain),
          _chipRow('Pain during intercourse or bowel movements', ['Never', 'Occasionally', 'Frequently'], c.dyspareuniaBowelPain),
          _chipRow('Bloating / nausea / back pain around period', ['Never', 'Sometimes', 'Often'], c.periodBloating),
          _boolRow('Infertility or multiple miscarriages', c.infertilityYes),

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
    );
  }
}

// ===============================
// UI: Result Page
// ===============================
class HealthResultPage extends StatelessWidget {
  final HealthCheckResult result;
  const HealthResultPage({super.key, required this.result});

  Color _accent(String indicator, String name) {
    if (name == 'thyroid' && indicator == 'Normal Function') return Colors.teal;
    if (indicator.toLowerCase().contains('high')) return Colors.red;
    if (indicator.toLowerCase().contains('normal')) return Colors.teal;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    final formattedRecs = formatRecommendation(result.recommendation ?? '');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
          leading: IconButton(onPressed: () => Get.offAll(NavigationMenu()), icon: const Icon(Icons.arrow_back)),
          title: const Text('Your Health Snapshot')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 12),
          for (final c in result.conditions)
            Card(
              color: Colors.grey.shade50,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 1.5,
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        c.name[0].toUpperCase() + c.name.substring(1),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _accent(c.indicator, c.name).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _accent(c.indicator, c.name).withOpacity(0.5)),
                      ),
                      child: Text(
                        c.indicator,
                        style: TextStyle(color: _accent(c.indicator, c.name), fontWeight: FontWeight.w600),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  const SizedBox(height: 6),
                  for (final r in c.reasons.take(3))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [const Text('• '), Expanded(child: Text(r))],
                      ),
                    ),
                ]),
              ),
            ),

          // Personalized suggestions (Gemini)
          if (formattedRecs.isNotEmpty) ...[
            const SizedBox(height: 8),
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
                          Expanded(child: Text(suggestion, style: const TextStyle(fontSize: 14))),
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
