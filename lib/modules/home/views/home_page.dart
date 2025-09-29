// lib/views/home_page.dart
import 'dart:convert';
import 'dart:ui'; // 👈 for BackdropFilter (glassy blur)
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../../services/chat_services.dart';
import '../controllers/home_controller.dart';
import '../widgets/profile/full_screen_chat_page.dart';
import '../widgets/profile/health_check/HealthSurveyPage.dart';
import '../widgets/profile/period_dates/full_screen_calendar_picket.dart';
import '../widgets/profile/profile_page.dart';

class HomePage extends StatelessWidget {
  HomePage({Key? key}) : super(key: key);
  final HomeController c = Get.put(HomeController());
  final GlobalKey _calendarStripKey = GlobalKey();

  // ==================== CHAT CONFIG ====================
  // Auto target language = device locale (e.g. 'hi', 'bn', 'te', etc.)
  String get _targetLang => (Get.locale?.languageCode ?? 'en');

  // ==================== GRADIENT HELPERS ====================
  List<Color> _gradientForController(HomeController c) {
    final sel = c.selectedCalendarDate.value;
    final today = DateTime.now();
    final selectedIsToday =
        sel.year == today.year && sel.month == today.month && sel.day == today.day;
    final useSelected =
        !selectedIsToday &&
            (c.selectedDaysUntilNextPeriod.value != null ||
                c.selectedDaysUntilOvulation.value != null);
    final refDate = useSelected
        ? DateTime(
      c.selectedCalendarDate.value.year,
      c.selectedCalendarDate.value.month,
      c.selectedCalendarDate.value.day,
    )
        : DateTime.now();

    final info = c.getCycleInfo(refDate);
    if (info == null) return [const Color(0xFFF9FBFC), const Color(0xFFF3FCF9)];

    final daysSincePeriodStart = info.daysSinceCurrentPeriodStart;
    final daysUntilNextPeriod = info.daysUntilNextPeriod;
    final daysToOv = info.daysUntilOvulation;
    final lastLen = c.lastPeriodLengthDays.value;

    if (daysSincePeriodStart >= 0 && daysSincePeriodStart < lastLen) {
      return [const Color(0xFFFFE9ED), const Color(0xFFFFC7D1)];
    }
    if (daysToOv > 0 && daysToOv <= 14) {
      return [const Color(0xFFE6F9F3), const Color(0xFFBFEFEA)];
    }
    if (daysToOv >= -3 && daysToOv <= 3) {
      return [const Color(0xFFFFF7E6), const Color(0xFFFFEDCC)];
    }
    if (daysUntilNextPeriod > 0 && daysUntilNextPeriod <= 10) {
      return [const Color(0xFFF8F4F6), const Color(0xFFF0E7EA)];
    }
    return [const Color(0xFFFDEFF1), const Color(0xFFF8F3FB)];
  }

  Color _foregroundForGradient(List<Color> colors) {
    double lum = 0.0;
    for (var col in colors) {
      lum += col.computeLuminance();
    }
    lum = lum / colors.length;
    return lum > 0.55 ? Colors.black87 : Colors.white;
  }

  Future<void> _pickDateAndUpdate(HomeController c) async {
    final picked = await showDatePicker(
      context: Get.context!,
      initialDate: c.predictedNextPeriodStart.value ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.pinkAccent,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: Colors.pinkAccent),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      final confirm = await Get.dialog<bool>(
        AlertDialog(
          title: const Text('Update next period date?'),
          content: Text(
            'Set next period to ${picked.toLocal().toIso8601String().split("T").first}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: const Text('Cancel', style: TextStyle(color: Colors.redAccent)),
            ),
            TextButton(
              onPressed: () => Get.back(result: true),
              child: const Text('Confirm', style: TextStyle(color: Colors.redAccent)),
            ),
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

  String _greetingForNow() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Noon';
    return 'Good Evening';
  }

  String _firstName(String fullName) {
    final t = fullName.trim();
    if (t.isEmpty) return 'friend';
    return t.split(RegExp(r'\s+'))[0];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8FA),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Obx(() {
          final gradColors = _gradientForController(c);
          final fg = _foregroundForGradient(gradColors);

          return AppBar(
            automaticallyImplyLeading: false,
            elevation: 0,
            backgroundColor: Colors.transparent,
            centerTitle: true,
            title: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_greetingForNow()}, ${_firstName(c.userName.value)}',
                  style: TextStyle(color: fg, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            flexibleSpace: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradColors,
                ),
              ),
            ),
            leading: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: GestureDetector(
                onTap: () => Get.to(ProfilePage()),
                child: Obx(
                      () => CircleAvatar(
                    radius: 18,
                    backgroundImage: c.avatarUrl.value.isNotEmpty
                        ? NetworkImage(c.avatarUrl.value)
                        : null,
                    backgroundColor: Colors.pink.shade300,
                    child: c.avatarUrl.value.isEmpty
                        ? const Icon(Icons.person, color: Colors.white)
                        : null,
                  ),
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.calendar_today_outlined),
                color: fg,
                tooltip: 'Open calendar',
                onPressed: () {
                  showModalBottomSheet(
                    context: Get.context!,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => DraggableScrollableSheet(
                      expand: false,
                      initialChildSize: 0.95,
                      minChildSize: 0.6,
                      maxChildSize: 0.98,
                      builder: (ctx, ctrl) => CalendarFullView(controller: c),
                    ),
                  );
                },
              ),
            ],
          );
        }),
      ),

      body: SafeArea(
        child: Obx(() {
          if (c.isLoading.value) {
            return const Center(child: CircularProgressIndicator());
          }

          return RefreshIndicator(
            onRefresh: () async {
              await c.fetchUserData();
              await c.fetchCards(); // new tips each pull
              c.selectedCalendarDate.value = DateTime.now();
              c.initialCalendarDate = DateTime.now();
              c.recomputeNow();
              await Future.delayed(const Duration(milliseconds: 120));
            },
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _topPanel(context, c)),
                const SliverToBoxAdapter(child: SizedBox(height: 10)),
                SliverToBoxAdapter(child: _cardsCarousel(c)),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                SliverToBoxAdapter(child: _latestHealthCheckSection(c)),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([_contentCard()]),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 80)),
              ],
            ),
          );
        }),
      ),

      // ==================== CHAT FAB ====================
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        floatingActionButton: _ChatFab(
          onTap: () {
            // ⛳️ NEW: push a separate scaffold instead of bottom sheet
            Get.to(() => const ChatFullScreenPage(),
                transition: Transition.rightToLeftWithFade);
          },
    ));
  }

  // ===================== NEW SECTION: Latest Health Check =====================

  Widget _latestHealthCheckSection(HomeController c) {
    final user = c.auth.currentUser;
    if (user == null) {
      return _hcEmptyState(
        title: "You're signed out",
        subtitle: "Sign in to see your latest Health Check here.",
        cta: "Take a Health Check",
        onTap: () => Get.off(() => HealthSurveyPage()),
      );
    }

    final query = c.db
        .collection('Health Check')
        .where('uid', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .withConverter<Map<String, dynamic>>(
      fromFirestore: (snap, _) => (snap.data() ?? {}),
      toFirestore: (data, _) => data,
    );

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _hcSkeletonCard();
        }
        if (snap.hasError) {
          return _hcEmptyState(
            title: "Couldn’t load Health Check",
            subtitle: "Tap to retry or take a new check.",
            cta: "Take a Health Check",
            onTap: () => Get.off(() => HealthSurveyPage()),
          );
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return _hcEmptyState(
            title: "No Health Check yet",
            subtitle: "Answer a few quick questions to get smart insights.",
            cta: "Take a Health Check",
            onTap: () => Get.off(() => HealthSurveyPage()),
          );
        }

        final data = snap.data!.docs.first.data();
        return _hcGlassySummary(data);
      },
    );
  }

  // ===== Glassy card renderer =====
  num _numOrZero(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v;
    if (v is String) return num.tryParse(v.trim()) ?? 0.0;
    return 0.0;
  }

  Map<String, dynamic> _mapOrEmpty(dynamic v) =>
      (v is Map<String, dynamic>) ? v : <String, dynamic>{};

  List<dynamic> _listOrEmpty(dynamic v) =>
      (v is List) ? v : const [];

  T? _firstOrNull<T>(List l) => l.isNotEmpty ? (l.first as T?) : null;

  Map<String, dynamic> _asMap(dynamic v) =>
      (v is Map<String, dynamic>) ? v : <String, dynamic>{};

  Map<String, dynamic> _pickBlock(Map<String, dynamic> data, String key) {
    // tries multiple common nesting locations
    final root = _asMap(data[key]);
    if (root.isNotEmpty) return root;

    final details = _asMap(data['details']);
    final d1 = _asMap(details[key]);
    if (d1.isNotEmpty) return d1;

    final api = _asMap(data['apiResponse']);
    final a1 = _asMap(api[key]);
    if (a1.isNotEmpty) return a1;

    final apiDetails = _asMap(api['details']);
    final a2 = _asMap(apiDetails[key]);
    if (a2.isNotEmpty) return a2;

    return <String, dynamic>{};
  }

  String _pickIndicator(Map<String, dynamic> block) {
    // tolerate 'indicator' or 'status' or 'label'
    final v = block['indicator'] ?? block['status'] ?? block['label'];
    return (v == null) ? '' : v.toString();
  }

  String _pickRecommendation(Map<String, dynamic> data) {
    final root = (data['recommendation'] ?? '').toString();
    if (root.trim().isNotEmpty) return root;
    final input = _asMap(data['input']);
    return (input['recommendation'] ?? '').toString();
  }

  bool _dropReason(String s) {
    final t = s.trim();
    // drop model probability/confidence lines
    if (RegExp(r'^Model\s+high-?risk\s+probability\s*:', caseSensitive: false).hasMatch(t)) {
      return true;
    }
    if (RegExp(r'^Model\s+confidence\s*:', caseSensitive: false).hasMatch(t)) {
      return true;
    }
    return false;
  }

  // Parse **bold** segments into spans
  List<InlineSpan> _parseBoldSpans(String text, {TextStyle? base}) {
    final spans = <InlineSpan>[];
    final reg = RegExp(r'\*\*(.+?)\*\*'); // minimal match
    int idx = 0;
    for (final m in reg.allMatches(text)) {
      if (m.start > idx) {
        spans.add(TextSpan(text: text.substring(idx, m.start), style: base));
      }
      spans.add(TextSpan(
        text: m.group(1),
        style: (base ?? const TextStyle()).merge(const TextStyle(fontWeight: FontWeight.w800)),
      ));
      idx = m.end;
    }
    if (idx < text.length) {
      spans.add(TextSpan(text: text.substring(idx), style: base));
    }
    return spans;
  }

  // Build a pretty recommendation: supports "* bullets" + **bold**
  Widget _buildRecommendation(String rec, {required TextStyle style}) {
    final base = TextStyle(fontSize: 13.5, color: Colors.black.withOpacity(0.85));
    final bulletRe = RegExp(r'^\*\s+(.*)$', multiLine: true);
    final bullets = bulletRe.allMatches(rec).map((m) => m.group(1)!.trim()).toList();

    if (bullets.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: bullets.map((b) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(padding: EdgeInsets.only(top: 6), child: Icon(Icons.circle, size: 6)),
                const SizedBox(width: 8),
                Expanded(child: RichText(text: TextSpan(children: _parseBoldSpans(b, base: base)))),
              ],
            ),
          );
        }).toList(),
      );
    }
    return RichText(text: TextSpan(children: _parseBoldSpans(rec, base: base)));
  }

  Widget _hcGlassySummary(Map<String, dynamic> data) {
    final createdAt = data['createdAt'];
    final anemia = _pickBlock(data, 'anemia');
    final pcos = _pickBlock(data, 'pcos');
    final endo = _pickBlock(data, 'endometriosis');
    final thyroid = _pickBlock(data, 'thyroid');

    final anemiaInd = _pickIndicator(anemia);
    final pcosInd = _pickIndicator(pcos);
    final endoInd = _pickIndicator(endo);
    final thyroidInd = _pickIndicator(thyroid);

    List _list(dynamic v) => (v is List) ? v : const [];

    final reasons = <String>{
      ..._list(anemia['reasons']).map((e) => e.toString().trim()),
      ..._list(pcos['reasons']).map((e) => e.toString().trim()),
      ..._list(endo['reasons']).map((e) => e.toString().trim()),
      ..._list(thyroid['reasons']).map((e) => e.toString().trim()),
    }.where((e) => e.isNotEmpty && !_dropReason(e)).toList();

    final recommendation = _pickRecommendation(data);

    Widget chip(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12.withOpacity(0.08)),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
    );

    Widget sectionTile(String title, String value) {
      if (value.isEmpty) return const SizedBox.shrink();
      return Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black12.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const Spacer(),
            chip(value),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.pink.shade50, Colors.purple.shade50, Colors.blue.shade50],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.55),
                  border: Border.all(color: Colors.white.withOpacity(0.25)),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 8))],
                ),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.monitor_heart_rounded, size: 22, color: Colors.pink),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Your Latest Health Check', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: Colors.black.withOpacity(0.04), borderRadius: BorderRadius.circular(999)),
                        child: Text(_formatTimestamp(createdAt),
                            style: TextStyle(fontSize: 11, color: Colors.black.withOpacity(0.65))),
                      ),
                    ]),
                    const SizedBox(height: 12),

                    sectionTile('Anemia', anemiaInd),
                    sectionTile('PCOS', pcosInd),
                    sectionTile('Endometriosis', endoInd),
                    sectionTile('Thyroid', thyroidInd),

                    if (reasons.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('Reasons',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.black.withOpacity(0.8))),
                      const SizedBox(height: 8),
                      ...reasons
                          .where((e) => e.trim().isNotEmpty)
                          .map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(padding: EdgeInsets.only(top: 3), child: Icon(Icons.circle, size: 6)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(r, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                          ],
                        ),
                      )),
                    ],

                    if (recommendation.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text('Recommendation',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.black.withOpacity(0.8))),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.black12.withOpacity(0.08)),
                        ),
                        child: _buildRecommendation(recommendation,
                            style: TextStyle(fontSize: 13.5, color: Colors.black.withOpacity(0.85))),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(dynamic ts) {
    try {
      DateTime d;
      if (ts is Timestamp) d = ts.toDate();
      else if (ts is DateTime) d = ts;
      else return '—';
      final months = const ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      final hh = d.hour.toString().padLeft(2, '0');
      final mm = d.minute.toString().padLeft(2, '0');
      return '${d.day} ${months[d.month-1]} ${d.year}, $hh:$mm';
    } catch (_) {
      return '—';
    }
  }

  Widget _bmiBadge(String bmi) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.monitor_weight, size: 16),
          const SizedBox(width: 6),
          Text('BMI: $bmi', style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _riskChipWidget(_RiskChip c) {
    final Color bg;
    final Color fg;
    if (c.percent >= 60) {
      bg = const Color(0xFFFFE8EA);
      fg = const Color(0xFFB90F3A);
    } else if (c.percent >= 25) {
      bg = const Color(0xFFFFF3E0);
      fg = const Color(0xFF9C6A00);
    } else {
      bg = const Color(0xFFEAF7EE);
      fg = const Color(0xFF1B7F41);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12.withOpacity(0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            c.label,
            style: TextStyle(fontWeight: FontWeight.w800, color: fg),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.black12.withOpacity(0.08)),
            ),
            child: Text(
              '${c.percent.toStringAsFixed(2)}%',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: fg,
                letterSpacing: 0.2,
              ),
            ),
          ),
          if (c.tag.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.05),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                c.tag,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _thyroidBlock(String indicator, double predictedPct, List<(String, double)> bars) {
    final label = indicator.isNotEmpty ? indicator : 'Thyroid';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label • ${predictedPct.toStringAsFixed(2)}%',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (ctx, cons) {
              final total = bars.fold<double>(0, (p, e) => p + e.$2);
              final w = cons.maxWidth;
              return Row(
                children: bars.map((e) {
                  final pct = total == 0 ? 0.0 : (e.$2 / total);
                  return Container(
                    width: w * pct,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _thyroidColor(e.$1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: bars.map((e) {
              return Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _thyroidColor(e.$1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('${e.$1}: ${e.$2.toStringAsFixed(2)}%',
                        style: TextStyle(fontSize: 11.5, color: Colors.black.withOpacity(0.7))),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Color _thyroidColor(String cls) {
    switch (cls) {
      case 'Normal':
      case 'Normal Function':
        return const Color(0xFF47A967);
      case 'Hypo':
      case 'Hypothyroid Risk':
        return const Color(0xFFE0A800);
      case 'Hyper':
      case 'Hyperthyroid Risk':
        return const Color(0xFFD7263D);
      default:
        return Colors.grey.shade400;
    }
  }

  Widget _hcEmptyState({
    required String title,
    required String subtitle,
    required String cta,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.pinkAccent.withOpacity(0.12),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.health_and_safety, color: Colors.pink, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: Colors.black.withOpacity(0.65))),
              ],
            ),
          ),
          TextButton(onPressed: onTap, child: Text(cta, style: TextStyle(color: Colors.pink),)),
        ],
      ),
    );
  }

  Widget _hcSkeletonCard() {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      height: 148,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.pinkAccent.withOpacity(0.12),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: const _Shimmer(),
    );
  }

  // ===================== EXISTING CONTENT BELOW (unchanged) =====================

  Widget _topPanel(BuildContext context, HomeController c) {
    return Obx(() {
      final gradColors = _gradientForController(c);
      final fgColor = _foregroundForGradient(gradColors);

      final sel = c.selectedCalendarDate.value;
      final today = DateTime.now();
      final selectedIsToday =
          sel.year == today.year && sel.month == today.month && sel.day == today.day;
      final useSelected =
          !selectedIsToday &&
              (c.selectedDaysUntilNextPeriod.value != null ||
                  c.selectedDaysUntilOvulation.value != null);

      final refDate = useSelected
          ? DateTime(
        c.selectedCalendarDate.value.year,
        c.selectedCalendarDate.value.month,
        c.selectedCalendarDate.value.day,
      )
          : DateTime.now();

      final info = c.getCycleInfo(refDate);
      final lastPeriodLen = c.lastPeriodLengthDays.value;

      String title;
      String big;
      String subtitle;

      if (info != null) {
        final daysSincePeriodStart = info.daysSinceCurrentPeriodStart;
        final daysUntilNextPeriod = info.daysUntilNextPeriod;
        final daysToOv = info.daysUntilOvulation;

        if (daysSincePeriodStart >= 0 && daysSincePeriodStart < lastPeriodLen) {
          final dayNum = daysSincePeriodStart + 1;
          title = 'Period';
          big = 'Day $dayNum';
          subtitle = 'Take care — listen to your body';
        } else if (daysToOv > 0 && daysToOv <= 14) {
          title = 'Ovulation in';
          big = '${daysToOv} day${daysToOv == 1 ? '' : 's'}';
          subtitle = 'Fertility window approaching';
        } else if (daysToOv >= -3 && daysToOv <= 3) {
          if (daysToOv == 0) {
            title = 'Ovulation';
            big = 'Today';
            subtitle = 'Peak fertility';
          } else {
            title = 'Fertile';
            big = 'High';
            subtitle = 'Peak fertility period';
          }
        } else if (daysUntilNextPeriod > 0 && daysUntilNextPeriod <= 10) {
          title = 'Next period in';
          big = '${daysUntilNextPeriod} day${daysUntilNextPeriod == 1 ? '' : 's'}';
          subtitle = 'Plan ahead';
        } else if (daysUntilNextPeriod >= 0) {
          title = 'Next period in';
          big = '${daysUntilNextPeriod} day${daysUntilNextPeriod == 1 ? '' : 's'}';
          subtitle = 'Keep tracking';
        } else {
          title = 'Prediction';
          big = '—';
          subtitle = 'No prediction available';
        }
      } else {
        title = 'Prediction';
        big = '—';
        subtitle = 'No prediction available';
      }

      final infoCaption =
      (c.selectedCalendarDate.value.day == DateTime.now().day &&
          c.selectedCalendarDate.value.month == DateTime.now().month &&
          c.selectedCalendarDate.value.year == DateTime.now().year)
          ? 'Based on today'
          : 'Based on selected date: ${c.selectedCalendarDate.value.toLocal().toIso8601String().split("T").first}';

      final ButtonStyle logPeriodStyle = ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 28),
        minimumSize: const Size(120, 44),
        shape: const StadiumBorder(),
        backgroundColor: const Color(0xFFFF6B9D),
        elevation: 0,
      );

      return AnimatedContainer(
        duration: const Duration(milliseconds: 480),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradColors,
          ),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(24),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: CalendarStrip(
                    key: _calendarStripKey,
                    controller: c,
                    onSettingsTap: () => _showOvulationToggleSheet(Get.context!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Column(
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 16, color: fgColor.withOpacity(0.95)),
                ),
                const SizedBox(height: 8),
                Text(
                  big,
                  style: TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.bold,
                    color: fgColor,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 14, color: fgColor.withOpacity(0.9)),
                ),
                const SizedBox(height: 14),
                Text(
                  infoCaption,
                  style: TextStyle(fontSize: 12, color: fgColor.withOpacity(0.85)),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    showModalBottomSheet(
                      context: Get.context!,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => DraggableScrollableSheet(
                        expand: false,
                        initialChildSize: 0.95,
                        minChildSize: 0.6,
                        maxChildSize: 0.98,
                        builder: (ctx, ctrl) => CalendarFullView(controller: c),
                      ),
                    );
                  },
                  style: logPeriodStyle,
                  child: const Text(
                    'Log period',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }

  Widget _cardsCarousel(HomeController c) {
    return SizedBox(
      height: 190,
      child: Obx(() {
        final list = List<Map<String, dynamic>>.from(c.cards);

        if (list.isEmpty) {
          return _tipsShimmerPaged();
        }

        return Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: c.tipsPageCtrl,
                padEnds: false,
                physics: const PageScrollPhysics(),
                onPageChanged: (i) => c.currentTipPage.value = i,
                itemCount: list.length,
                itemBuilder: (ctx, idx) {
                  final item = list[idx];
                  final bool isActive = idx == c.currentTipPage.value;
                  return AnimatedPadding(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    padding: EdgeInsets.only(
                      left: idx == 0 ? 12 : 0,
                      right: 12,
                    ),
                    child: AnimatedScale(
                      scale: isActive ? 1.0 : 0.96,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          boxShadow: [
                            if (isActive)
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 18,
                                spreadRadius: 1,
                                offset: const Offset(0, 8),
                              ),
                          ],
                        ),
                        child: _tipCard(item, idx),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Obx(() {
              final total = list.length;
              final cur = c.currentTipPage.value;
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(total, (i) {
                  final active = i == cur;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 6,
                    width: active ? 18 : 6,
                    decoration: BoxDecoration(
                      color: active
                          ? const Color(0xFFE50914)
                          : const Color(0xFFE50914).withOpacity(0.35),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  );
                }),
              );
            }),
          ],
        );
      }),
    );
  }

  Widget _tipsShimmerPaged() {
    final placeholders = List.generate(3, (_) => _ShimmerCard());
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            padEnds: false,
            controller: PageController(viewportFraction: 0.86),
            itemCount: placeholders.length,
            itemBuilder: (ctx, idx) => Padding(
              padding: EdgeInsets.only(
                left: idx == 0 ? 12 : 0,
                right: 12,
              ),
              child: placeholders[idx],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              height: 6,
              width: 6,
              decoration: BoxDecoration(
                color: const Color(0xFFE50914).withOpacity(0.35),
                borderRadius: BorderRadius.circular(999),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _tipCard(Map item, int idx) {
    final String title = (item['title'] ?? '').toString();
    final String subtitle = (item['subtitle'] ?? '').toString();
    final String category = (item['category'] ?? 'Hygiene').toString();
    final String icon = (item['icon'] ?? '💡').toString();

    final Map<String, List<Color>> catGrad = {
      'Hygiene': [const Color(0xFFFFE9F0), const Color(0xFFFFD6E3)],
      'Products': [const Color(0xFFE7FBF8), const Color(0xFFCFF6EE)],
      'Hydration': [const Color(0xFFE6F4FF), const Color(0xFFCCE7FF)],
      'Diet': [const Color(0xFFFFF6E7), const Color(0xFFFFE7BF)],
      'Movement': [const Color((0xEFF7FF)), const Color(0xFFD8EAFF)], // minor
      'Sleep & Relax': [const Color(0xFFF3EBFF), const Color(0xFFE2D7FF)],
      'Cramps & Comfort': [const Color(0xFFFFF1E9), const Color(0xFFFFDEC9)],
      'Disposal & Environment': [const Color(0xFFE8FFF1), const Color(0xFFCFF7E0)],
      'Travel & Backup': [const Color(0xFFFFF0F3), const Color(0xFFFFD7E1)],
      'Tracking & Symptoms': [const Color(0xFFEFFAF6), const Color(0xFFD6F2E7)],
    };

    final colors = catGrad[category] ?? [const Color(0xFFFDEFF1), const Color(0xFFF8F3FB)];
    final fg = _foregroundForGradient(colors);

    return Container(
      width: 310,
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12.withOpacity(0.06)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(icon, style: const TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  category,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.black.withOpacity(0.7),
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: fg),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: fg.withOpacity(0.9)),
          ),
        ],
      ),
    );
  }

  Widget _contentCard() {
    final today = DateTime.now();
    final monthNames = const [
      'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sept','Oct','Nov','Dec',
    ];
    final headerText =
        'Quick Symptom Check • ${today.day} ${monthNames[today.month - 1]}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          Get.off(() => HealthSurveyPage());
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.pinkAccent.withOpacity(0.15),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text(
                  headerText,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: Colors.grey.shade800,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                height: 160,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(18),
                  ),
                  gradient: LinearGradient(
                    colors: [
                      Colors.pink.shade400,
                      Colors.pink.shade300,
                      Colors.pink.shade200,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      right: -20,
                      bottom: -10,
                      child: Icon(
                        Icons.favorite,
                        size: 120,
                        color: Colors.white.withOpacity(0.08),
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(
                          Icons.health_and_safety_rounded,
                          size: 36,
                          color: Colors.white,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Take a Health Check',
                          style: TextStyle(
                            fontSize: 20,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOvulationToggleSheet(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      builder: (_) {
        return Obx(() {
          final val = c.useLastDayForOvulation.value;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Ovulation calculation',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: val,
                    title: const Text('Use last-day-of-period as anchor'),
                    subtitle: const Text(
                      'Alternate ovulation rule (power users). Default is mid-cycle midpoint.',
                    ),
                    onChanged: (v) async {
                      c.useLastDayForOvulation.value = v;
                      await _saveOvulationPreference(v);
                      c.recomputeNow();
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tip: mid-cycle is clinically common. Use last-day rule only if you prefer it.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Future<void> _saveOvulationPreference(bool v) async {
    try {
      final user = c.auth.currentUser;
      if (user != null) {
        await c.db.collection('Users').doc(user.uid).set({
          'use_last_day_for_ovulation': v,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Failed saving ovulation pref: $e');
    }
  }
}

/// ===== Shimmer Widgets (package-free) =====

class _ShimmerCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      height: 170,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
        border: Border.all(color: Colors.black12.withOpacity(0.06)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ShimmerBox(width: 36, height: 36, borderRadius: BorderRadius.circular(12)),
              const SizedBox(width: 8),
              _ShimmerBox(width: 90, height: 22, borderRadius: BorderRadius.circular(999)),
            ],
          ),
          const Spacer(),
          _ShimmerBox(width: 200, height: 16, borderRadius: BorderRadius.circular(6)),
          const SizedBox(height: 8),
          _ShimmerBox(width: 260, height: 12, borderRadius: BorderRadius.circular(6)),
          const SizedBox(height: 6),
          _ShimmerBox(width: 220, height: 12, borderRadius: BorderRadius.circular(6)),
        ],
      ),
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const _ShimmerBox({
    Key? key,
    required this.width,
    required this.height,
    required this.borderRadius,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: width,
        height: height,
        child: const _Shimmer(),
      ),
    );
  }
}

class _Shimmer extends StatefulWidget {
  const _Shimmer({Key? key}) : super(key: key);

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _ac;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat();
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ac,
      builder: (context, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            return Stack(
              fit: StackFit.expand,
              children: [
                Container(color: Colors.grey.shade200),
                Transform.translate(
                  offset: Offset((w + 200) * (_ac.value) - 200, 0),
                  child: Container(
                    width: 200,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.grey.shade200.withOpacity(0.0),
                          Colors.grey.shade100.withOpacity(0.9),
                          Colors.grey.shade200.withOpacity(0.0),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ===== Helper models =====
class _RiskChip {
  final String label;
  final double percent;
  final String tag;
  _RiskChip({required this.label, required this.percent, required this.tag});
}

// ==================== CHAT UI + SERVICE ====================

class _ChatFab extends StatelessWidget {
  final VoidCallback onTap;
  const _ChatFab({Key? key, required this.onTap}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: onTap,
      backgroundColor: const Color(0xFFFF8FB1),
      foregroundColor: Colors.white,
      icon: const Icon(Icons.chat_bubble_outline),
      label: const Text('Ask', style: TextStyle(fontWeight: FontWeight.w700)),
      shape: const StadiumBorder(),
      elevation: 2,
    );
  }
}
