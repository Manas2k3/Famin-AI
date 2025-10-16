// lib/controllers/calendar_and_controller_patch.dart
// Drop-in file containing two classes to replace/upgrade your existing
// HomeController and CalendarStrip implementations.

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// ====== Controller ======
enum DayPhase { period, prePeriod, ovulation, fertile, safe, unknown }

/// Simple data holder returned for a reference date's computed cycle info.
class CycleInfo {
  final DateTime currentPeriodStart;
  final DateTime nextPeriodStart;
  final DateTime ovulationDate;
  final int daysSinceCurrentPeriodStart;
  final int daysUntilNextPeriod;
  final int daysUntilOvulation;
  final String phase;
  final int cycleLength;

  CycleInfo({
    required this.currentPeriodStart,
    required this.nextPeriodStart,
    required this.ovulationDate,
    required this.daysSinceCurrentPeriodStart,
    required this.daysUntilNextPeriod,
    required this.daysUntilOvulation,
    required this.phase,
    required this.cycleLength,
  });
}

/// Simple PeriodEntry model for storing period start/end pairs
class PeriodEntry {
  final String id;
  final DateTime start;
  final DateTime end;

  PeriodEntry({required this.id, required this.start, required this.end});

  Map<String, dynamic> toMap() => {
    'start_ts': Timestamp.fromDate(start),
    'end_ts': Timestamp.fromDate(end),
    'created_at': Timestamp.fromDate(DateTime.now()),
  };

  static PeriodEntry fromDoc(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    final start = data['start_ts'] is Timestamp
        ? (data['start_ts'] as Timestamp).toDate()
        : DateTime.parse(data['start_ts'].toString());
    final end = data['end_ts'] is Timestamp
        ? (data['end_ts'] as Timestamp).toDate()
        : DateTime.parse(data['end_ts'].toString());
    return PeriodEntry(
      id: doc.id,
      start: DateTime(start.year, start.month, start.day),
      end: DateTime(end.year, end.month, end.day),
    );
  }
}

class HomeController extends GetxController {
  final ScrollController calendarScrollCtrl = ScrollController();
  final auth = FirebaseAuth.instance;
  final db = FirebaseFirestore.instance;

  // Calendar
  var selectedCalendarDate = DateTime.now().obs;
  late DateTime initialCalendarDate;

  // UI state
  var isLoading = true.obs;

  /// Cards shown on the Tips carousel.
  /// Each card: { id, type:"mini", title, subtitle, category, icon }
  final cards = <Map<String, dynamic>>[].obs;
  late final PageController tipsPageCtrl;
  final currentTipPage = 0.obs;
  // Profile
  var userName = ''.obs;
  var avatarUrl = ''.obs;

  // Period data (from Firestore)
  Rxn<DateTime> lastPeriodStart = Rxn<DateTime>();
  Rxn<DateTime> lastPeriodEnd = Rxn<DateTime>();
  var lastPeriodLengthDays = 7.obs;

  Rxn<DateTime> predictedNextPeriodStart = Rxn<DateTime>();
  var predictedBy = 'fallback'.obs;

  // Settings: whether to compute ovulation from last-day-of-period
  var useLastDayForOvulation = false.obs;

  // Computed cycle info (relative to now)
  var daysUntilNextPeriod = (-1).obs;
  var daysUntilOvulation = (-1).obs;
  var currentPhase = ''.obs; // "period", "ovulation", "fertile", "safe", "unknown"

  // Computed cycle info (relative to selectedCalendarDate)
  var selectedDaysUntilNextPeriod = Rx<int?>(null);
  var selectedDaysUntilOvulation = Rx<int?>(null);
  var selectedPhase = ''.obs; // "period", "ovulation", "fertile", "safe", "unknown"

  // Period history
  var periodHistory = <PeriodEntry>[].obs; // sorted descending by start

  // NEW: range-selection state for user to log actual period ranges
  var rangeSelecting = false.obs;
  Rxn<DateTime> tempRangeStart = Rxn<DateTime>();

  // ===== Tips uniqueness memory (session-level) =====
  // Keep the last set of titles to bias against repeats on the next refresh.
  Set<String> _lastTipTitles = {};

  @override
  void onInit() {
    super.onInit();
    tipsPageCtrl = PageController(viewportFraction: 0.86); // peeking next card
    initialCalendarDate = selectedCalendarDate.value;

    // recompute when key values change
    ever(predictedNextPeriodStart, (_) => _recomputeCountdowns());
    ever(lastPeriodStart, (_) => _recomputeCountdowns());
    ever(lastPeriodLengthDays, (_) => _recomputeCountdowns());
    ever(selectedCalendarDate, (_) => _recomputeCountdownsForSelected());
    ever(useLastDayForOvulation, (_) => _recomputeCountdowns());

    fetchCards();
    fetchUserData();
    // initial compute
    _recomputeCountdowns();
    _recomputeCountdownsForSelected();
  }

  // =========================
  // TIPS: Gemini-powered cards
  // =========================
  Future<void> fetchCards() async {
    try {
      // 1) Try Gemini for fresh, diverse, non-repeating tips.
      final tips = await _getTipsFromGemini();
      if (tips.isNotEmpty) {
        _lastTipTitles = tips.map((m) => (m['title'] ?? '').toString()).toSet();
        cards.value = tips;
        return;
      }

      // 2) Fallback to curated local pool with enforced diversity & uniqueness.
      final fallback = _fallbackTipsUnique(count: 7);
      _lastTipTitles = fallback.map((m) => (m['title'] ?? '').toString()).toSet();
      cards.value = fallback;
    } catch (e) {
      debugPrint('fetchCards (tips) error: $e');
      final fb = _fallbackTipsUnique(count: 7);
      _lastTipTitles = fb.map((m) => (m['title'] ?? '').toString()).toSet();
      cards.value = fb;
    }
  }

  Future<List<Map<String, dynamic>>> _getTipsFromGemini() async {
    final key = dotenv.env['GEMINI_API_KEY'];
    if (key == null || key.isEmpty) {
      throw Exception('GEMINI_API_KEY missing in .env');
    }

    final endpoint = (dotenv.env['GEMINI_API_ENDPOINT']?.trim().isNotEmpty ?? false)
        ? dotenv.env['GEMINI_API_ENDPOINT']!.trim()
        : 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent';

    // A nonce nudges the model to produce a *new* set each refresh.
    final nonce = _rid();

    // We ask for guaranteed category coverage + unique titles and small supportive subtitles.
    // Also pass prior titles so the model avoids repeating them.
    final prior = _lastTipTitles.isEmpty ? '[]' : jsonEncode(_lastTipTitles.toList());

    final prompt = '''
Return ONLY JSON array with 7 objects. No prose. No code fences.

Goal: Fresh, friendly mini-cards about menstrual hygiene & wellness. Make them unique each call.

Hard rules:
- All 7 must be mutually different.
- Avoid any title in this previousTitles list: $prior
- Cover these 7 categories (exactly once each): 
  ["Hydration","Diet","Hygiene","Products","Movement","Sleep & Relax","Cramps & Comfort"]
- Tone: supportive, non-judgmental, no medical diagnosis/claims.
- Keep inclusive; avoid gendered assumptions.
- Keep tips general/safe (no medication advice).

Each object fields:
- id: short unique string
- type: "mini"
- title: catchy <= 22 chars
- subtitle: concrete, specific, <= 70 chars, max 1 emoji
- category: one of the 7 categories above
- icon: a single relevant emoji (e.g., 🫧, 🩸, 💧, 🥗, 🧘, 😴, 🌿)

Example shape only:
[
  {"id":"c1","type":"mini","title":"Change Often","subtitle":"Swap pads/tampons every 4–6 hrs.","category":"Hygiene","icon":"🫧"},
  {"id":"c2","type":"mini","title":"Breathable Layers","subtitle":"Cotton undies help airflow.","category":"Products","icon":"🩸"},
  {"id":"c3","type":"mini","title":"Water Goals","subtitle":"Aim ~8–10 glasses/day 💧","category":"Hydration","icon":"💧"},
  {"id":"c4","type":"mini","title":"Iron+Vitamin C","subtitle":"Pair spinach with citrus to boost iron.","category":"Diet","icon":"🥗"},
  {"id":"c5","type":"mini","title":"Gentle Walks","subtitle":"15–20 min light movement eases bloating.","category":"Movement","icon":"🚶"},
  {"id":"c6","type":"mini","title":"Wind-Down","subtitle":"Consistent bedtime supports energy 😴","category":"Sleep & Relax","icon":"😴"},
  {"id":"c7","type":"mini","title":"Cozy Heat","subtitle":"Warm pad or bath can soothe cramps.","category":"Cramps & Comfort","icon":"🌿"}
]

Nonce: $nonce
''';

    final payload = {
      "contents": [
        {
          "parts": [
            {"text": prompt}
          ]
        }
      ]
    };

    final res = await http.post(
      Uri.parse(endpoint),
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': key,
      },
      body: jsonEncode(payload),
    );

    if (res.statusCode != 200) {
      debugPrint('Gemini tips non-200: ${res.statusCode} ${res.body}');
      return [];
    }

    final Map<String, dynamic> body = jsonDecode(res.body);

    String? modelText;
    try {
      final candidates = (body['candidates'] as List);
      if (candidates.isNotEmpty) {
        modelText = candidates[0]['content']['parts'][0]['text'] as String?;
      }
    } catch (_) {
      modelText = jsonEncode(body);
    }

    final raw = modelText ?? '';
    final jsonText = _extractJsonArray(raw);
    final decoded = json.decode(jsonText);

    if (decoded is! List) return [];

    final List<Map<String, dynamic>> out = [];
    final titlesSeen = <String>{};
    for (final e in decoded) {
      if (e is Map) {
        final title = (e['title'] ?? '').toString().trim();
        if (title.isEmpty) continue;
        if (titlesSeen.contains(title)) continue; // ensure uniqueness in one batch
        titlesSeen.add(title);

        out.add({
          'id': (e['id'] ?? _rid()).toString(),
          'type': 'mini',
          'title': title,
          'subtitle': (e['subtitle'] ?? '').toString().trim(),
          'category': (e['category'] ?? '').toString().trim(),
          'icon': (e['icon'] ?? '💡').toString().trim(),
        });
      }
    }

    // If model missed fields, enrich minimally.
    for (final m in out) {
      m['type'] ??= 'mini';
      m['id'] ??= _rid();
      m['icon'] ??= '💡';
      m['category'] ??= 'Hygiene';
    }

    // Keep at least 5; otherwise fall back.
    return out.length >= 5 ? out : [];
  }

  String _extractJsonArray(String s) {
    final start = s.indexOf('[');
    final end = s.lastIndexOf(']');
    if (start != -1 && end != -1 && end > start) {
      return s.substring(start, end + 1);
    }
    return s.trim();
  }

  String _rid() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return 'c${List.generate(6, (_) => chars[r.nextInt(chars.length)]).join()}';
  }

  // ---------- Local curated pool + unique sampler ----------
  List<Map<String, dynamic>> _fallbackTipsUnique({int count = 7}) {
    final pool = _localTipPool();
    // Remove anything that matches last batch titles to strengthen "freshness"
    final pruned = pool.where((m) => !_lastTipTitles.contains(m['title'])).toList();

    // Ensure category coverage (one per required category), then fill rest randomly.
    const desiredCategories = [
      'Hydration',
      'Diet',
      'Hygiene',
      'Products',
      'Movement',
      'Sleep & Relax',
      'Cramps & Comfort',
      'Disposal & Environment',
      'Travel & Backup',
      'Tracking & Symptoms',
    ];

    final rand = Random.secure();
    final byCat = <String, List<Map<String, dynamic>>>{};
    for (final m in pruned) {
      final cat = (m['category'] ?? 'Hygiene').toString();
      byCat.putIfAbsent(cat, () => []).add(m);
    }

    // Pick up to one from the first 7 core categories for guaranteed coverage.
    final chosen = <Map<String, dynamic>>[];
    for (final cat in desiredCategories.take(7)) {
      final list = byCat[cat];
      if (list != null && list.isNotEmpty) {
        list.shuffle(rand);
        chosen.add(list.first);
      }
    }

    // If we still don't have "count", fill with random *other* unique ones.
    final titles = chosen.map((m) => m['title'] as String).toSet();
    final remaining = pruned.where((m) => !titles.contains(m['title'])).toList()..shuffle(rand);
    for (final m in remaining) {
      if (chosen.length >= count) break;
      chosen.add(m);
    }

    // Ensure at least 'count' even if pruned small.
    if (chosen.length < count) {
      final all = pool.where((m) => !titles.contains(m['title'])).toList()..shuffle(rand);
      for (final m in all) {
        if (chosen.length >= count) break;
        chosen.add(m);
      }
    }

    // Give fresh ids each refresh for UI uniqueness.
    for (final m in chosen) {
      m['id'] = _rid();
      m['type'] = 'mini';
    }
    return chosen.take(count).toList();
  }

  List<Map<String, dynamic>> _localTipPool() => [
    // Hydration
    {
      'title': 'Hydration Habit',
      'subtitle': 'Aim ~8–10 glasses/day; sip regularly 💧',
      'category': 'Hydration',
      'icon': '💧'
    },
    {
      'title': 'Electrolyte Boost',
      'subtitle': 'Add a pinch of salts/coconut water on sweaty days.',
      'category': 'Hydration',
      'icon': '🥥'
    },

    // Diet
    {
      'title': 'Iron + C Combo',
      'subtitle': 'Pair beans/spinach with citrus to aid iron use.',
      'category': 'Diet',
      'icon': '🥗'
    },
    {
      'title': 'Slow Carbs',
      'subtitle': 'Whole grains steady energy through the day.',
      'category': 'Diet',
      'icon': '🍞'
    },
    {
      'title': 'Go Easy on Salt',
      'subtitle': 'Less salt can help with bloating.',
      'category': 'Diet',
      'icon': '🧂'
    },

    // Hygiene
    {
      'title': 'Change On Time',
      'subtitle': 'Swap pads/tampons every 4–6 hrs for comfort.',
      'category': 'Hygiene',
      'icon': '🫧'
    },
    {
      'title': 'Gentle Wash',
      'subtitle': 'Use mild cleansers; skip harsh soaps or douching.',
      'category': 'Hygiene',
      'icon': '🫧'
    },
    {
      'title': 'Air Things Out',
      'subtitle': 'Choose breathable fabrics to reduce irritation.',
      'category': 'Hygiene',
      'icon': '🌬️'
    },

    // Products
    {
      'title': 'Right Absorbency',
      'subtitle': 'Pick light/regular/super based on flow that day.',
      'category': 'Products',
      'icon': '🩸'
    },
    {
      'title': 'Try Reusables',
      'subtitle': 'Cups/discs/panties can be comfy & low-waste.',
      'category': 'Products',
      'icon': '♻️'
    },
    {
      'title': 'Patch Test First',
      'subtitle': 'New product? Test briefly to avoid irritation.',
      'category': 'Products',
      'icon': '🧪'
    },

    // Movement
    {
      'title': 'Gentle Walk',
      'subtitle': '15–20 min light movement eases stiffness.',
      'category': 'Movement',
      'icon': '🚶'
    },
    {
      'title': 'Stretch & Breathe',
      'subtitle': 'Slow hip/low-back stretches can soothe cramps.',
      'category': 'Movement',
      'icon': '🧘'
    },

    // Sleep & Relax
    {
      'title': 'Wind-Down',
      'subtitle': 'Consistent bedtime supports energy 😴',
      'category': 'Sleep & Relax',
      'icon': '😴'
    },
    {
      'title': 'Screen Dimmer',
      'subtitle': 'Lower blue light 1 hr before bed.',
      'category': 'Sleep & Relax',
      'icon': '📵'
    },

    // Cramps & Comfort
    {
      'title': 'Cozy Heat',
      'subtitle': 'Warm pad/bath may ease cramps & relax muscles.',
      'category': 'Cramps & Comfort',
      'icon': '🌿'
    },
    {
      'title': 'Tea Time',
      'subtitle': 'Herbal teas (like ginger) feel soothing for many.',
      'category': 'Cramps & Comfort',
      'icon': '🍵'
    },

    // Disposal & Environment
    {
      'title': 'Wrap & Bin',
      'subtitle': 'Wrap used products; never flush. Keep a pouch.',
      'category': 'Disposal & Environment',
      'icon': '🗑️'
    },
    {
      'title': 'Low-Waste Swap',
      'subtitle': 'Consider cups/discs if they suit your routine.',
      'category': 'Disposal & Environment',
      'icon': '🌍'
    },

    // Travel & Backup
    {
      'title': 'Backup Kit',
      'subtitle': 'Keep a spare pad, wipes & underwear in your bag.',
      'category': 'Travel & Backup',
      'icon': '🎒'
    },
    {
      'title': 'Flow Forecast',
      'subtitle': 'Pack extras if a heavier day is due.',
      'category': 'Travel & Backup',
      'icon': '📅'
    },

    // Tracking & Symptoms
    {
      'title': 'Note Your Pattern',
      'subtitle': 'Track flow, cramps, mood to learn your rhythm.',
      'category': 'Tracking & Symptoms',
      'icon': '📝'
    },
    {
      'title': 'Tag Triggers',
      'subtitle': 'Noting foods/sleep helps spot patterns.',
      'category': 'Tracking & Symptoms',
      'icon': '🔎'
    },
  ];

  // =========================
  // END TIPS SECTION
  // =========================

  Future<void> fetchUserData() async {
    final user = auth.currentUser;
    if (user == null) {
      isLoading.value = false;
      return;
    }
    try {
      isLoading.value = true;
      final doc = await db.collection('Users').doc(user.uid).get();
      if (!doc.exists) {
        isLoading.value = false;
        return;
      }
      final data = doc.data()!;

      userName.value = (data['name'] ?? '').toString();
      avatarUrl.value = (data['avatarUrl'] ?? '').toString();

      if (data['last_period_start_ts'] != null) {
        if (data['last_period_start_ts'] is Timestamp) {
          lastPeriodStart.value =
              (data['last_period_start_ts'] as Timestamp).toDate();
        } else {
          lastPeriodStart.value =
              DateTime.tryParse(data['last_period_start_ts'].toString());
        }
      }

      if (data['last_period_end_ts'] != null &&
          data['last_period_end_ts'] is Timestamp) {
        lastPeriodEnd.value =
            (data['last_period_end_ts'] as Timestamp).toDate();
      }

      lastPeriodLengthDays.value =
      (data['last_period_length_days'] ?? lastPeriodLengthDays.value) is int
          ? (data['last_period_length_days'] ?? lastPeriodLengthDays.value)
          : lastPeriodLengthDays.value;

      if (data['predicted_next_period_start_ts'] != null) {
        predictedNextPeriodStart.value =
            (data['predicted_next_period_start_ts'] as Timestamp).toDate();
      } else if (data['predicted_next_period_start'] != null) {
        predictedNextPeriodStart.value = DateTime.tryParse(
            data['predicted_next_period_start'].toString());
      }

      predictedBy.value = (data['predicted_by'] ?? predictedBy.value).toString();

      // optional: read user's preference for ovulation rule
      if (data['use_last_day_for_ovulation'] != null) {
        useLastDayForOvulation.value =
        (data['use_last_day_for_ovulation'] == true);
      }

      // fetch period history as well
      await fetchPeriodHistory();

      _recomputeCountdowns();
      _recomputeCountdownsForSelected();
    } catch (e) {
      debugPrint('HomeController.fetchUserData error: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> fetchPeriodHistory() async {
    final user = auth.currentUser;
    if (user == null) return;
    try {
      final snap = await db
          .collection('Users')
          .doc(user.uid)
          .collection('periods')
          .orderBy('start_ts', descending: true)
          .get();
      periodHistory.value =
          snap.docs.map((d) => PeriodEntry.fromDoc(d)).toList();
    } catch (e) {
      debugPrint('fetchPeriodHistory error: $e');
    }
  }

  Future<void> logPeriod(DateTime start, DateTime end) async {
    final user = auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    final docRef =
    db.collection('Users').doc(user.uid).collection('periods').doc();
    await docRef.set({
      'start_ts':
      Timestamp.fromDate(DateTime(start.year, start.month, start.day)),
      'end_ts': Timestamp.fromDate(DateTime(end.year, end.month, end.day)),
      'created_at': Timestamp.fromDate(DateTime.now()),
    });
    await fetchPeriodHistory();

    // Update lastPeriodStart/End and lastPeriodLengthDays if this is latest start
    final latest = periodHistory.isNotEmpty ? periodHistory.first : null;
    if (latest != null && !latest.start.isBefore(start)) {
      lastPeriodStart.value = DateTime(start.year, start.month, start.day);
      lastPeriodEnd.value = DateTime(end.year, end.month, end.day);
      lastPeriodLengthDays.value = (end.difference(start).inDays + 1);
      // optionally update predictedNextPeriodStart via Gemini
      await callGeminiAndMaybeSavePrediction();
    }
  }

  Future<void> editPeriod(String id, DateTime start, DateTime end) async {
    final user = auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    final docRef =
    db.collection('Users').doc(user.uid).collection('periods').doc(id);
    await docRef.update({
      'start_ts':
      Timestamp.fromDate(DateTime(start.year, start.month, start.day)),
      'end_ts': Timestamp.fromDate(DateTime(end.year, end.month, end.day)),
    });
    await fetchPeriodHistory();
    await callGeminiAndMaybeSavePrediction();
  }

  Future<void> deletePeriod(String id) async {
    final user = auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    await db
        .collection('Users')
        .doc(user.uid)
        .collection('periods')
        .doc(id)
        .delete();
    await fetchPeriodHistory();
    // recompute local lastPeriod* values if needed
    if (periodHistory.isNotEmpty) {
      lastPeriodStart.value = periodHistory.first.start;
      lastPeriodEnd.value = periodHistory.first.end;
      lastPeriodLengthDays.value =
      (lastPeriodEnd.value!.difference(lastPeriodStart.value!).inDays + 1);
    } else {
      lastPeriodStart.value = null;
      lastPeriodEnd.value = null;
    }
    recomputeNow();
  }

  ///
  /// setPeriodRange - central helper to store user selected range (start..end),
  /// update `lastPeriodStart`/`lastPeriodEnd`/`lastPeriodLengthDays`, persist to Users doc,
  /// and append to `periods` collection (and recompute).
  ///
  Future<void> setPeriodRange(DateTime start, DateTime end,
      {bool fromUser = true, bool saveToHistory = true}) async {
    final user = auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    // normalize to start-of-day for start and end-of-day for end
    final s = DateTime(start.year, start.month, start.day, 5, 0);
    final e = DateTime(end.year, end.month, end.day, 23, 59);

    final daysLength = e.difference(s).inDays + 1;

    // Save to main user doc (summary fields) and set cycle_updated_at
    try {
      await db.collection('Users').doc(user.uid).set({
        'last_period_start_ts': Timestamp.fromDate(s),
        'last_period_end_ts': Timestamp.fromDate(e),
        'last_period_length_days': daysLength,
        'cycle_updated_at': DateTime.now().toIso8601String(),
        if (fromUser) 'predicted_by': 'user_range',
      }, SetOptions(merge: true));
    } catch (ex) {
      debugPrint('setPeriodRange: failed saving summary fields: $ex');
      rethrow;
    }

    // Optionally save to periods history
    if (saveToHistory) {
      try {
        final col =
        db.collection('Users').doc(user.uid).collection('periods');
        await col.add({
          'start_ts': Timestamp.fromDate(DateTime(s.year, s.month, s.day)),
          'end_ts': Timestamp.fromDate(DateTime(e.year, e.month, e.day)),
          'created_at': Timestamp.fromDate(DateTime.now()),
        });
      } catch (ex) {
        debugPrint('setPeriodRange: failed saving to history: $ex');
        // don't fail the whole flow - continue
      }
    }

    // update local reactive state
    lastPeriodStart.value = DateTime(s.year, s.month, s.day);
    lastPeriodEnd.value = DateTime(e.year, e.month, e.day);
    lastPeriodLengthDays.value = daysLength.clamp(1, 60);

    // refresh period history and recompute countdowns
    await fetchPeriodHistory();
    _recomputeCountdowns();
    _recomputeCountdownsForSelected();

    // Ask Gemini for a fresh prediction using the entire history (non-blocking)
    unawaited(callGeminiWithHistory());
  }

  /// Cancel an in-progress range selection
  void cancelRangeSelection() {
    rangeSelecting.value = false;
    tempRangeStart.value = null;
  }

  /// Called after user-saved ranges — decides whether to call Gemini; separated to keep control
  Future<void> maybeCallGeminiAfterRangeSaved() async {
    await callGeminiWithHistory();
  }

  /// Build a prompt from periodHistory and call Gemini; if prediction found, save it.
  Future<void> callGeminiWithHistory() async {
    final key = dotenv.env['GEMINI_API_KEY'];
    final endpoint = dotenv.env['GEMINI_API_ENDPOINT'];
    if (key == null || key.isEmpty) return;
    if (endpoint == null || endpoint.isEmpty) return;
    if (periodHistory.isEmpty) return;

    final buffer = StringBuffer();
    buffer.writeln('You are a helpful cycle predictor. Return JSON only.');
    buffer.writeln('User period history (oldest first):');

    final sorted = List<PeriodEntry>.from(periodHistory)
      ..sort((a, b) => a.start.compareTo(b.start));
    for (final e in sorted) {
      buffer.writeln(
          '- ${e.start.toIso8601String().split("T").first} to ${e.end.toIso8601String().split("T").first} (${(e.end.difference(e.start).inDays + 1)} days)');
    }

    buffer.writeln('');
    buffer.writeln(
        'Using this history, predict the next period start date (single date) after the latest entry, give a confidence percent and short notes. Return JSON only in the form: {"predicted_date":"YYYY-MM-DD","confidence_percent":80,"notes":"..."}');

    try {
      final url = Uri.parse(endpoint);
      final payload = {
        "contents": [
          {
            "parts": [
              {"text": buffer.toString()}
            ]
          }
        ]
      };

      final res = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': key,
        },
        body: jsonEncode(payload),
      );

      if (res.statusCode != 200) {
        debugPrint('Gemini API non-200: ${res.statusCode} ${res.body}');
        return;
      }

      final Map<String, dynamic> decoded = jsonDecode(res.body);
      String? contentText;
      try {
        contentText = (decoded['candidates'] as List).isNotEmpty
            ? (decoded['candidates'][0]['content']['parts'][0]['text']
        as String?)
            : null;
      } catch (_) {
        contentText = jsonEncode(decoded);
      }

      final payloadStr = contentText ?? jsonEncode(decoded);

      final jsonMatch = RegExp(r"\{[\s\S]*\}").firstMatch(payloadStr);
      if (jsonMatch != null) {
        final j = jsonDecode(jsonMatch.group(0)!);
        if (j['predicted_date'] != null) {
          final pred = DateTime.parse(j['predicted_date']);
          await _savePredictedFromGemini(pred, 'gemini');
          return;
        }
      }

      final dateMatch = RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch(payloadStr);
      if (dateMatch != null) {
        final pred = DateTime.parse(dateMatch.group(0)!);
        await _savePredictedFromGemini(pred, 'gemini');
      }
    } catch (e) {
      debugPrint('callGeminiWithHistory error: $e');
    }
  }

  /// Optional Gemini predictor call (kept for compatibility)
  Future<Map<String, dynamic>?> callGeminiPredictor(String prompt) async {
    final key = dotenv.env['GEMINI_API_KEY'];
    final endpoint = dotenv.env['GEMINI_API_ENDPOINT'];
    if (key == null || key.isEmpty) return null;
    if (endpoint == null || endpoint.isEmpty) return null;

    final url = Uri.parse(endpoint);
    final payload = {
      "contents": [
        {
          "parts": [
            {"text": prompt}
          ]
        }
      ]
    };

    final res = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': key,
      },
      body: jsonEncode(payload),
    );

    if (res.statusCode == 200) {
      try {
        final Map<String, dynamic> body =
        jsonDecode(res.body) as Map<String, dynamic>;
        return body;
      } catch (e) {
        debugPrint('callGeminiPredictor decode error: $e');
        return null;
      }
    }

    debugPrint('Gemini error ${res.statusCode}: ${res.body}');
    return null;
  }

  Future<void> callGeminiAndMaybeSavePrediction() async {
    await callGeminiWithHistory();
  }

  Future<void> _savePredictedFromGemini(
      DateTime predictedDate, String provider) async {
    final user = auth.currentUser;
    if (user == null) return;
    final dt =
    DateTime(predictedDate.year, predictedDate.month, predictedDate.day, 5, 30);
    predictedNextPeriodStart.value = dt;
    predictedBy.value = provider;
    try {
      await db.collection('Users').doc(user.uid).set({
        'predicted_next_period_start_ts': Timestamp.fromDate(dt),
        'predicted_next_period_start': dt.toIso8601String(),
        'predicted_by': provider,
        'cycle_updated_at': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
      _recomputeCountdowns();
      _recomputeCountdownsForSelected();
    } catch (e) {
      debugPrint('_savePredictedFromGemini failed: $e');
      rethrow;
    }
  }

  void _recomputeCountdowns() {
    final now = DateTime.now();
    _computeForReferenceDate(now, forNow: true);
  }

  void _recomputeCountdownsForSelected() {
    final sel = selectedCalendarDate.value;
    _computeForReferenceDate(sel, forNow: false);
  }

  /// Compute and return the DayPhase for a given date.
  DayPhase phaseForDate(DateTime day) {
    final p = predictedNextPeriodStart.value;
    if (p == null) return DayPhase.unknown;

    final cycleLen = estimateCycleLength();
    final int cl = (cycleLen >= 10 && cycleLen <= 60) ? cycleLen : 28;
    final lastLen = lastPeriodLengthDays.value;

    final pDate = DateTime(p.year, p.month, p.day);
    final dayStart = DateTime(day.year, day.month, day.day);

    final diff = dayStart.difference(pDate).inDays;
    final pos = ((diff % cl) + cl) % cl;

    if (pos >= 0 && pos < lastLen) return DayPhase.period;

    if (useLastDayForOvulation.value) {
      DateTime? lastEnd;
      if (lastPeriodEnd.value != null) {
        lastEnd = DateTime(lastPeriodEnd.value!.year, lastPeriodEnd.value!.month,
            lastPeriodEnd.value!.day);
      } else if (lastPeriodStart.value != null) {
        lastEnd = DateTime(lastPeriodStart.value!.year,
            lastPeriodStart.value!.month, lastPeriodStart.value!.day)
            .add(Duration(days: (lastLen - 1)));
      }

      if (lastEnd != null) {
        final nextAfterLastEnd = lastEnd.add(Duration(days: cl - lastLen));
        final remaining = (nextAfterLastEnd.difference(lastEnd).inDays);
        final offset = (remaining / 2).round();
        final ov = DateTime(lastEnd.year, lastEnd.month, lastEnd.day)
            .add(Duration(days: offset));
        final dToOv = ov.difference(dayStart).inDays;
        if (dToOv == 0) return DayPhase.ovulation;
        if (dToOv.abs() <= 3) return DayPhase.fertile;
      }
    }

    final ovPos = (cl / 2).round();
    if (pos == ovPos) return DayPhase.ovulation;
    if ((pos - ovPos).abs() <= 3) return DayPhase.fertile;

    final daysUntilNext = (cl - pos) % cl;
    if (daysUntilNext > 0 && daysUntilNext <= 10) return DayPhase.prePeriod;

    return DayPhase.safe;
  }

  /// Exposed helper: compute full cycle info for a given ref date.
  CycleInfo? getCycleInfo(DateTime refDate) {
    final p = predictedNextPeriodStart.value;
    if (p == null) return null;

    final refStart = DateTime(refDate.year, refDate.month, refDate.day);
    final cycleLen = estimateCycleLength();
    final int cl = (cycleLen >= 10 && cycleLen <= 60) ? cycleLen : 28;
    final lastLen = lastPeriodLengthDays.value;

    final pDate = DateTime(p.year, p.month, p.day);

    final diff = refStart.difference(pDate).inDays;
    final k = (diff / cl).floor();
    DateTime candidate = pDate.add(Duration(days: k * cl));
    if (candidate.isAfter(refStart)) {
      candidate = candidate.subtract(Duration(days: cl));
    }

    final currentPeriodStart = candidate;
    final nextPeriodStart = currentPeriodStart.add(Duration(days: cl));

    final daysSinceCurrentPeriodStart =
        refStart.difference(currentPeriodStart).inDays;
    final daysUntilP = nextPeriodStart.difference(refStart).inDays;

    DateTime ovulation;
    if (useLastDayForOvulation.value) {
      if (lastPeriodEnd.value != null) {
        final lastEnd = DateTime(lastPeriodEnd.value!.year,
            lastPeriodEnd.value!.month, lastPeriodEnd.value!.day);
        final remaining = (cl - lastLen);
        final offset = (remaining / 2).round();
        ovulation = lastEnd.add(Duration(days: offset));
      } else {
        ovulation =
            currentPeriodStart.add(Duration(days: (cl / 2).round()));
      }
    } else {
      ovulation = currentPeriodStart.add(Duration(days: (cl / 2).round()));
    }

    final daysUntilO = ovulation.difference(refStart).inDays;

    String phase;
    if (daysSinceCurrentPeriodStart >= 0 &&
        daysSinceCurrentPeriodStart < lastLen) {
      phase = "period";
    } else if (daysUntilO == 0) {
      phase = "ovulation";
    } else if (daysUntilO >= -3 && daysUntilO <= 3) {
      phase = "fertile";
    } else {
      phase = "safe";
    }

    return CycleInfo(
      currentPeriodStart: currentPeriodStart,
      nextPeriodStart: nextPeriodStart,
      ovulationDate: ovulation,
      daysSinceCurrentPeriodStart: daysSinceCurrentPeriodStart,
      daysUntilNextPeriod: daysUntilP,
      daysUntilOvulation: daysUntilO,
      phase: phase,
      cycleLength: cl,
    );
  }

  /// Core computation used for both "now" and "selected date". Uses phaseForDate
  /// to populate the public countdown fields.
  void _computeForReferenceDate(DateTime refDate, {required bool forNow}) {
    final p = predictedNextPeriodStart.value;
    if (p != null) {
      final info = getCycleInfo(refDate);
      if (info != null) {
        if (forNow) {
          daysUntilNextPeriod.value = info.daysUntilNextPeriod;
          daysUntilOvulation.value = info.daysUntilOvulation;
          currentPhase.value = info.phase;
        } else {
          selectedDaysUntilNextPeriod.value = info.daysUntilNextPeriod;
          selectedDaysUntilOvulation.value = info.daysUntilOvulation;
          selectedPhase.value = info.phase;
        }
        return;
      }
    }

    if (forNow) {
      daysUntilNextPeriod.value = -1;
      daysUntilOvulation.value = -1;
      currentPhase.value = "unknown";
    } else {
      selectedDaysUntilNextPeriod.value = null;
      selectedDaysUntilOvulation.value = null;
      selectedPhase.value = "unknown";
    }
  }

  /// Estimate cycle length using lastPeriodStart -> predictedNextPeriodStart when possible.
  int estimateCycleLength() {
    final a = lastPeriodStart.value;
    final b = predictedNextPeriodStart.value;
    if (a != null && b != null) {
      final diff = b.difference(a).inDays;
      if (diff > 10 && diff < 60) return diff;
    }
    return 28;
  }

  Future<void> updatePredictedNextPeriodStart(DateTime newDate) async {
    final user = auth.currentUser;
    if (user == null) return;
    final dt = DateTime(newDate.year, newDate.month, newDate.day, 5, 30);
    predictedNextPeriodStart.value = dt;
    try {
      await db.collection('Users').doc(user.uid).set({
        'predicted_next_period_start_ts': Timestamp.fromDate(dt),
        'predicted_next_period_start': dt.toIso8601String(),
        'predicted_by': 'user_edit',
        'cycle_updated_at': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
      _recomputeCountdowns();
      _recomputeCountdownsForSelected();
    } catch (e) {
      debugPrint('updatePredictedNextPeriodStart failed: $e');
      rethrow;
    }
  }

  // For manual recompute
  void recomputeNow() {
    _recomputeCountdowns();
    _recomputeCountdownsForSelected();
  }
}

/// ====== CalendarStrip (UI) ======
// (Unchanged from your structure, just kept here to preserve your flow)
class CalendarStrip extends StatefulWidget {
  final HomeController controller;
  final VoidCallback? onSettingsTap;
  const CalendarStrip({Key? key, required this.controller, this.onSettingsTap})
      : super(key: key);

  @override
  State<CalendarStrip> createState() => _CalendarStripState();
}

class _CalendarStripState extends State<CalendarStrip> {
  late final PageController _pageController;
  static const int _rangeSpan = 1081; // +/- 540 days (~1.5 years)
  late final int _middleIndex;

  final int _step = 7;

  static const double _tileHeight = 90.0;
  static const double _weekdayFontSize = 12.0;
  static const Color _accent = Color(0xFF0FA79A);

  late int _lastSettledIndex;
  bool _isAnimating = false;

  Timer? _settleTimer;

  bool _suppressControllerReaction = false;

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  int get _todayIndex {
    final init = widget.controller.initialCalendarDate;
    final today = _startOfDay(DateTime.now());
    final diff =
        today.difference(DateTime(init.year, init.month, init.day)).inDays;
    return (_middleIndex + diff).clamp(0, _rangeSpan - 1).toInt();
  }

  int get _minIndex => _todayIndex;

  @override
  void initState() {
    super.initState();
    _middleIndex = _rangeSpan ~/ 2;
    _lastSettledIndex = _middleIndex;
    _pageController = PageController(
      initialPage: _middleIndex,
      viewportFraction: 1 / 7,
    );

    ever<DateTime?>(widget.controller.selectedCalendarDate,
            (DateTime? newDate) async {
          if (newDate == null) return;

          if (_suppressControllerReaction) return;

          final mid = widget.controller.initialCalendarDate;
          final daysDiff =
              newDate.difference(DateTime(mid.year, mid.month, mid.day)).inDays;
          var targetIndex = (_middleIndex + daysDiff).clamp(0, _rangeSpan - 1);

          if (targetIndex < _minIndex) targetIndex = _minIndex;

          if (!_pageController.hasClients) return;
          final currentPage =
              _pageController.page ?? _pageController.initialPage.toDouble();
          if ((currentPage - targetIndex).abs() > 0.25) {
            _isAnimating = true;
            try {
              await _pageController.animateToPage(
                targetIndex,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
              _lastSettledIndex = targetIndex;
            } finally {
              _isAnimating = false;
            }
          }
        });
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> jumpWeek(int direction) async {
    if (!_pageController.hasClients) return;
    if (_isAnimating) return;
    final current = _pageController.page?.round() ?? _lastSettledIndex;
    var intended =
    (current + direction * _step).clamp(0, _rangeSpan - 1).toInt();
    if (intended < _minIndex) intended = _minIndex;
    if (intended == current) return;

    _isAnimating = true;
    try {
      await _pageController.animateToPage(
        intended,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
      );
      _lastSettledIndex = intended;
      final mid = widget.controller.initialCalendarDate;
      final day = mid.add(Duration(days: intended - _middleIndex));
      if (!_isSameDate(
          day, widget.controller.selectedCalendarDate.value)) {
        widget.controller.selectedCalendarDate.value = day;
        widget.controller.recomputeNow();
      }
    } finally {
      await Future.delayed(const Duration(milliseconds: 8));
      _isAnimating = false;
    }
  }

  Future<void> animateToDate(DateTime date, {int durationMs = 300}) async {
    final mid = widget.controller.initialCalendarDate;
    final daysDiff =
        date.difference(DateTime(mid.year, mid.month, mid.day)).inDays;
    var targetIndex = (_middleIndex + daysDiff).clamp(0, _rangeSpan - 1);

    if (targetIndex < _minIndex) targetIndex = _minIndex;

    if (!_pageController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        animateToDate(date, durationMs: durationMs);
      });
      return;
    }

    final currentPage =
    (_pageController.page ?? _pageController.initialPage.toDouble())
        .round();

    if (currentPage == targetIndex) {
      try {
        _pageController.jumpToPage(targetIndex);
      } catch (_) {}
      return;
    }

    _suppressControllerReaction = true;
    _isAnimating = true;
    try {
      try {
        await _pageController.animateToPage(
          targetIndex,
          duration: Duration(milliseconds: durationMs),
          curve: Curves.easeInOut,
        );
      } catch (_) {}
      final after =
      (_pageController.page ?? _pageController.initialPage.toDouble())
          .round();
      if (after != targetIndex) {
        try {
          _pageController.jumpToPage(targetIndex);
        } catch (_) {}
      }
      _lastSettledIndex = targetIndex;
    } finally {
      await Future.delayed(const Duration(milliseconds: 10));
      _suppressControllerReaction = false;
      _isAnimating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    const tileMargin = 6.0;
    final totalHeight = _tileHeight + 36.0;

    return SizedBox(
      height: totalHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Obx(() => Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatMonthYear(
                        widget.controller.selectedCalendarDate.value),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  IconButton(
                    icon: const Icon(Icons.tune),
                    tooltip: 'Ovulation settings',
                    onPressed: () {
                      if (widget.onSettingsTap != null) {
                        widget.onSettingsTap!();
                      } else {
                        if (Get.context != null) {
                          Get.snackbar('Settings',
                              'No settings handler attached',
                              snackPosition: SnackPosition.BOTTOM);
                        }
                      }
                    },
                  ),
                ],
              )),
              const SizedBox(height: 4),
              Expanded(
                child: Obx(() {
                  final mid = widget.controller.initialCalendarDate;
                  final p =
                      widget.controller.predictedNextPeriodStart.value;
                  final markedDate =
                  p != null ? DateTime(p.year, p.month, p.day) : null;

                  return NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification is ScrollStartNotification) {
                        _settleTimer?.cancel();
                      }
                      return false;
                    },
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: _rangeSpan,
                      padEnds: true,
                      physics: const PageScrollPhysics(
                          parent: BouncingScrollPhysics()),
                      onPageChanged: (int pageIndex) {
                        _settleTimer?.cancel();
                        _settleTimer =
                            Timer(const Duration(milliseconds: 120), () async {
                              if (_isAnimating) return;

                              if (pageIndex < _minIndex) {
                                try {
                                  _isAnimating = true;
                                  await _pageController.animateToPage(
                                    _minIndex,
                                    duration:
                                    const Duration(milliseconds: 220),
                                    curve: Curves.easeInOut,
                                  );
                                } catch (_) {
                                  try {
                                    _pageController.jumpToPage(_minIndex);
                                  } catch (_) {}
                                } finally {
                                  _isAnimating = false;
                                }

                                final today = mid.add(
                                    Duration(days: _minIndex - _middleIndex));
                                if (!_isSameDate(today,
                                    widget.controller.selectedCalendarDate.value)) {
                                  widget.controller.selectedCalendarDate.value =
                                      today;
                                  widget.controller.recomputeNow();
                                }
                                _lastSettledIndex = _minIndex;

                                Get.snackbar(
                                  'Not allowed',
                                  'You can’t scroll before today',
                                  snackPosition: SnackPosition.BOTTOM,
                                  duration:
                                  const Duration(milliseconds: 1200),
                                  backgroundColor: Colors.black87,
                                  colorText: Colors.white,
                                  icon: const Icon(Icons.block,
                                      color: Colors.white),
                                  snackStyle: SnackStyle.FLOATING,
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  borderRadius: 12,
                                  animationDuration:
                                  const Duration(milliseconds: 300),
                                  forwardAnimationCurve: Curves.easeOutBack,
                                  boxShadows: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.25),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                );

                                return;
                              }

                              final day = mid.add(
                                  Duration(days: pageIndex - _middleIndex));
                              if (!_isSameDate(day,
                                  widget.controller.selectedCalendarDate.value)) {
                                widget.controller.selectedCalendarDate.value =
                                    day;
                                widget.controller.recomputeNow();
                              }
                              _lastSettledIndex = pageIndex;
                            });
                      },
                      itemBuilder: (ctx, i) {
                        final day = mid.add(Duration(days: i - _middleIndex));
                        final isToday = _isSameDate(day, DateTime.now());
                        final isSelected = _isSameDate(
                            day, widget.controller.selectedCalendarDate.value);
                        final isMarked =
                        (markedDate != null && _isSameDate(day, markedDate));

                        final page = _pageController.hasClients
                            ? (_pageController.page ??
                            _pageController.initialPage.toDouble())
                            : _pageController.initialPage.toDouble();
                        final dist = (page - i).abs();
                        final centerish = dist < 0.5;

                        final isPast =
                        day.isBefore(_startOfDay(DateTime.now()));
                        final numColor = isPast
                            ? Colors.grey.shade400
                            : (isSelected || isToday
                            ? _accent
                            : _accent.withOpacity(0.9));
                        final weekdayColor = Colors.grey.shade700;
                        final caption =
                        centerish && isToday ? 'TODAY' : _weekdayShort(day);

                        final isHistoricPeriodDay = widget
                            .controller.periodHistory
                            .any((p) =>
                        !day.isBefore(p.start) &&
                            !day.isAfter(p.end));

                        final double circleSize = centerish ? 68 : 36;

                        Widget dayNumberWidgetSized = SizedBox(
                          width: circleSize,
                          height: circleSize,
                          child: Center(
                            child: centerish
                                ? Container(
                              width: circleSize,
                              height: circleSize,
                              decoration: const BoxDecoration(
                                color: Colors.transparent,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                  child: Semantics(
                                      label:
                                      'Selected day ${day.day}',
                                      child:
                                      const SizedBox.shrink())),
                            )
                                : Container(
                              width: circleSize,
                              height: circleSize,
                              alignment: Alignment.center,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '${day.day}',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: numColor,
                                      fontSize: 16),
                                ),
                              ),
                            ),
                          ),
                        );

                        bool isTempStart = widget.controller
                            .tempRangeStart.value !=
                            null &&
                            _isSameDate(day,
                                widget.controller.tempRangeStart.value!);
                        bool isUserStart = widget
                            .controller.lastPeriodStart.value !=
                            null &&
                            _isSameDate(day,
                                widget.controller.lastPeriodStart.value!);
                        bool isUserEnd = widget
                            .controller.lastPeriodEnd.value !=
                            null &&
                            _isSameDate(day,
                                widget.controller.lastPeriodEnd.value!);

                        Widget decoratedNumber;

                        if ((isUserStart || isUserEnd) && !centerish) {
                          decoratedNumber = Container(
                            width: circleSize,
                            height: circleSize,
                            decoration: const BoxDecoration(
                                color: Color(0xFFFF6B9D),
                                shape: BoxShape.circle),
                            child: Center(
                                child: Text('${day.day}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold))),
                          );
                        } else if (isTempStart && !centerish) {
                          decoratedNumber =
                              _dottedCircle(circleSize + 6.0, dayNumberWidgetSized);
                        } else if (isHistoricPeriodDay && !centerish) {
                          decoratedNumber = Stack(
                            alignment: Alignment.center,
                            children: [
                              dayNumberWidgetSized,
                              Positioned(
                                bottom: 6,
                                child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                        color: Colors.pinkAccent,
                                        shape: BoxShape.circle)),
                              ),
                            ],
                          );
                        } else if (isMarked && !centerish) {
                          decoratedNumber =
                              _dottedCircle(circleSize + 8.0, dayNumberWidgetSized);
                        } else {
                          decoratedNumber = dayNumberWidgetSized;
                        }

                        return RepaintBoundary(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: tileMargin / 2, vertical: 4),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  height: 18,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      caption.toUpperCase(),
                                      style: TextStyle(
                                          fontSize: _weekdayFontSize,
                                          fontWeight: FontWeight.w600,
                                          color: weekdayColor),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Flexible(child: decoratedNumber),
                                const SizedBox(height: 4),
                                if (centerish) const SizedBox(height: 5),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  );
                }),
              ),
            ],
          ),

          // Center overlay circle
          Positioned(
            left: 0,
            right: 0,
            top: 75,
            bottom: 0,
            child: IgnorePointer(
              child: Center(
                child: Obx(() {
                  const double overlaySize = 64;
                  final sel = widget.controller.selectedCalendarDate.value;
                  final p = widget.controller.predictedNextPeriodStart.value;
                  final isMarked = (p != null &&
                      p.year == sel.year &&
                      p.month == sel.month &&
                      p.day == sel.day);

                  Widget circle = Container(
                    width: overlaySize,
                    height: overlaySize,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(
                            color: Colors.black12,
                            blurRadius: 6,
                            offset: Offset(0, 2))
                      ],
                    ),
                    child: Center(
                      child: Text(
                        '${sel.day}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _accent,
                            fontSize: 18),
                      ),
                    ),
                  );

                  if (isMarked) {
                    circle = _dottedCircle(overlaySize + 8.0, circle);
                  }

                  return SizedBox(
                    width: overlaySize + 16,
                    height: overlaySize + 16,
                    child: Align(alignment: Alignment.center, child: circle),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dottedCircle(double size, Widget child) {
    return CustomPaint(
      painter: _DottedCirclePainter(),
      child: SizedBox(width: size, height: size, child: Center(child: child)),
    );
  }

  bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _weekdayShort(DateTime d) =>
      ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][d.weekday % 7];
}

class _DottedCirclePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = const Color(0xFF0FA79A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    const double dashWidth = 6.0;
    const double dashSpace = 4.0;
    final radius = (size.width / 2) - 2.0;
    final circumference = 2 * 3.1415926535 * radius;
    final dashCount =
    (circumference / (dashWidth + dashSpace)).floor().clamp(4, 120);
    final sweep = 2 * 3.1415926535 / dashCount;

    for (int i = 0; i < dashCount; i++) {
      final startAngle = i * sweep;
      final segment = sweep * (dashWidth / (dashWidth + dashSpace));
      canvas.drawArc(
          Rect.fromCircle(
              center: Offset(size.width / 2, size.height / 2), radius: radius),
          startAngle,
          segment,
          false,
          paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Helper functions
String _formatMonthYear(DateTime d) =>
    '${['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][d.month - 1]} ${d.year}';
bool _isSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// A small convenience pick-date function (kept for compatibility)
Future<void> _pickDateAndUpdate(HomeController c) async {
  final picked = await showDatePicker(
    context: Get.context!,
    initialDate: c.predictedNextPeriodStart.value ?? DateTime.now(),
    firstDate: DateTime.now().subtract(const Duration(days: 365)),
    lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
  );
  if (picked != null) {
    final confirm = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Update next period date?'),
        content: Text(
            'Set next period to ${picked.toLocal().toIso8601String().split("T").first}?'),
        actions: [
          TextButton(onPressed: () => Get.back(result: false), child: const Text('Cancel')),
          TextButton(onPressed: () => Get.back(result: true), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await c.updatePredictedNextPeriodStart(picked);
        Get.snackbar('Updated', 'Next period date saved',
            snackPosition: SnackPosition.BOTTOM);
      } catch (e) {
        Get.snackbar('Error', 'Failed to save date: $e',
            snackPosition: SnackPosition.BOTTOM);
      }
    }
  }
}
