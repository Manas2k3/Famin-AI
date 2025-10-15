// lib/views/home_page_redesigned.dart
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../../services/chat_services.dart';
import '../controllers/home_controller.dart';
import '../widgets/calorie_track/calorie_track.dart';
import '../widgets/profile/full_screen_chat_page.dart';
import '../widgets/profile/health_check/HealthSurveyPage.dart';
import '../widgets/profile/period_dates/full_screen_calendar_picket.dart';
import '../widgets/profile/profile_page.dart';

class HomePage extends StatelessWidget {
  HomePage({Key? key}) : super(key: key);

  final HomeController c = Get.put(HomeController());

  String get _targetLang => (Get.locale?.languageCode ?? 'en');

  String _greetingForNow() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
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
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Obx(() {
          if (c.isLoading.value) {
            return const Center(child: CircularProgressIndicator());
          }

          // ✅ ADD 'return' HERE
          return RefreshIndicator(
            onRefresh: () async {
              await c.fetchUserData();
              await c.fetchCards();
              c.selectedCalendarDate.value = DateTime.now();
              c.initialCalendarDate = DateTime.now();
              c.recomputeNow();
            },

            child: CustomScrollView(
              slivers: [
                // Minimal SliverAppBar (we handle our own header)
                const SliverAppBar(
                  expandedHeight: 0,
                  floating: false,
                  pinned: false,
                  elevation: 0,
                  backgroundColor: Colors.transparent,
                  toolbarHeight: 0,
                ),

                // Header
                SliverToBoxAdapter(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.pink.shade50, Colors.purple.shade50],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(24),
                        bottomRight: Radius.circular(24),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Get.to(ProfilePage()),
                          child: Obx(() => Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  Colors.pink.shade300,
                                  Colors.purple.shade300
                                ],
                              ),
                              border:
                              Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.pink.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: c.avatarUrl.value.isNotEmpty
                                ? ClipOval(
                              child: Image.network(
                                c.avatarUrl.value,
                                fit: BoxFit.cover,
                              ),
                            )
                                : const Icon(Icons.person,
                                color: Colors.white, size: 24),
                          )),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _greetingForNow(),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _firstName(c.userName.value),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.calendar_month_rounded),
                          color: Colors.black87,
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
                                builder: (ctx, ctrl) =>
                                    CalendarFullView(controller: c),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                // Horizontal calendar
                SliverToBoxAdapter(child: _modernCalendarStrip(context)),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),

                // Cycle info
                SliverToBoxAdapter(child: _cycleInfoCard()),
                const SliverToBoxAdapter(child: SizedBox(height: 20)),

                // Tips
                SliverToBoxAdapter(child: _tipsSection()),
                const SliverToBoxAdapter(child: SizedBox(height: 20)),

                // Latest Health Check (GLASSY, from old code)
                SliverToBoxAdapter(child: _latestHealthCheckSection(c)),
                const SliverToBoxAdapter(child: SizedBox(height: 20)),

                // Quick health check CTA
                SliverToBoxAdapter(child: _quickHealthCheckCTA()),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          );
        }),
      ),
      floatingActionButton: _modernChatFAB(),
    );
  }

  // ==================== MODERN CALENDAR STRIP ====================
  Widget _modernCalendarStrip(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Obx(() {
                final sel = c.selectedCalendarDate.value;
                return Text(
                  _formatMonthYear(sel),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                );
              }),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.pink.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Obx(() {
                  final cycle = c.estimateCycleLength();
                  return Text(
                    'Cycle: ${cycle}d',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.pink.shade700,
                    ),
                  );
                }),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 100,
            child: Obx(() {
              final today = DateTime.now();
              final selected = c.selectedCalendarDate.value;

              // CRITICAL FIX: Calculate initial scroll position based on selected date
              // This runs on every rebuild when selectedCalendarDate changes
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (c.calendarScrollCtrl.hasClients) {
                  // Calculate which index represents the selected date
                  final daysSinceToday = selected.difference(
                      DateTime(today.year, today.month, today.day)
                  ).inDays;

                  // Index 7 represents today (since we do: today.add(Duration(days: index - 7)))
                  // So if selected is 3 days ahead, we want index 10
                  final targetIndex = 7 + daysSinceToday;

                  // Each item is 56px wide + 8px margin = 64px total
                  const itemWidth = 64.0;

                  // Scroll to center the selected date (subtract half viewport)
                  final targetOffset = (targetIndex * itemWidth) -
                      (c.calendarScrollCtrl.position.viewportDimension / 2) +
                      (itemWidth / 2);

                  // Animate only if we're not already close to the target
                  final currentOffset = c.calendarScrollCtrl.offset;
                  if ((currentOffset - targetOffset).abs() > 10) {
                    c.calendarScrollCtrl.animateTo(
                      targetOffset.clamp(0.0, c.calendarScrollCtrl.position.maxScrollExtent),
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  }
                }
              });

              return ListView.builder(
                controller: c.calendarScrollCtrl,
                scrollDirection: Axis.horizontal,
                itemCount: 60, // ~2 months
                itemBuilder: (ctx, index) {
                  final date = today.add(Duration(days: index - 7));
                  final isSelected = _isSameDate(date, selected);
                  final isToday = _isSameDate(date, today);
                  final isPast = date.isBefore(
                      DateTime(today.year, today.month, today.day));

                  // Period history window
                  final isHistoricPeriod = c.periodHistory.any((p) =>
                  !date.isBefore(p.start) && !date.isAfter(p.end));

                  // Phase indicators
                  final phase = c.phaseForDate(date);
                  final isPeriodPhase = phase == DayPhase.period;
                  final isOvulation = phase == DayPhase.ovulation;
                  final isFertile = phase == DayPhase.fertile;

                  Color bgColor = Colors.transparent;
                  Color textColor = Colors.black87;
                  Color dotColor = Colors.transparent;

                  if (isSelected) {
                    bgColor = Colors.pink.shade400;
                    textColor = Colors.white;
                  } else if (isToday) {
                    bgColor = Colors.pink.shade50;
                    textColor = Colors.pink.shade700;
                  } else if (isPast) {
                    textColor = Colors.grey.shade400;
                  }

                  if (isHistoricPeriod || isPeriodPhase) {
                    dotColor = Colors.pink.shade400;
                  } else if (isOvulation) {
                    dotColor = Colors.amber.shade400;
                  } else if (isFertile) {
                    dotColor = Colors.green.shade300;
                  }

                  return GestureDetector(
                    onTap: () {
                      c.selectedCalendarDate.value = date;
                      c.recomputeNow();
                    },
                    child: Container(
                      width: 56,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _weekdayShort(date),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: bgColor,
                              shape: BoxShape.circle,
                              border: isToday && !isSelected
                                  ? Border.all(
                                  color: Colors.pink.shade300, width: 2)
                                  : null,
                            ),
                            child: Center(
                              child: Text(
                                '${date.day}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: dotColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }


  // ==================== CYCLE INFO CARD ====================
  Widget _cycleInfoCard() {
    return Obx(() {
      final info = c.getCycleInfo(c.selectedCalendarDate.value);
      if (info == null) {
        return const SizedBox.shrink();
      }

      String title;
      String subtitle;
      IconData icon;
      List<Color> gradColors;

      if (info.phase == 'period') {
        final dayNum = info.daysSinceCurrentPeriodStart + 1;
        title = 'Period Day $dayNum';
        subtitle = 'Take care — listen to your body';
        icon = Icons.water_drop_rounded;
        gradColors = [const Color(0xFFFFE9ED), const Color(0xFFFFC7D1)];
      } else if (info.daysUntilOvulation > 0 && info.daysUntilOvulation <= 14) {
        title = 'Ovulation in ${info.daysUntilOvulation}d';
        subtitle = 'Fertility window approaching';
        icon = Icons.spa_rounded;
        gradColors = [const Color(0xFFE6F9F3), const Color(0xFFBFEFEA)];
      } else if (info.phase == 'ovulation') {
        title = 'Ovulation Day';
        subtitle = 'Peak fertility';
        icon = Icons.favorite_rounded;
        gradColors = [const Color(0xFFFFF7E6), const Color(0xFFFFEDCC)];
      } else if (info.daysUntilNextPeriod <= 10) {
        title = 'Next period in ${info.daysUntilNextPeriod}d';
        subtitle = 'Plan ahead';
        icon = Icons.calendar_today_rounded;
        gradColors = [const Color(0xFFF8F4F6), const Color(0xFFF0E7EA)];
      } else {
        title = 'Safe Phase';
        subtitle = 'Keep tracking';
        icon = Icons.check_circle_rounded;
        gradColors = [const Color(0xFFFDEFF1), const Color(0xFFF8F3FB)];
      }

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: gradColors.first.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: Colors.pink.shade400),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  // ==================== TIPS SECTION ====================
  Widget _tipsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Daily Tips',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              TextButton(
                onPressed: () async {
                  await c.fetchCards();
                },
                child: Row(
                  children: [
                    const Icon(Icons.refresh, size: 18, color: Colors.pink),
                    const SizedBox(width: 4),
                    const Text('Refresh', style: TextStyle(color: Colors.pink)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 160,
          child: Obx(() {
            final list = List<Map<String, dynamic>>.from(c.cards);
            if (list.isEmpty) {
              return _tipsShimmer();
            }

            return PageView.builder(
              controller: c.tipsPageCtrl,
              padEnds: false,
              onPageChanged: (i) => c.currentTipPage.value = i,
              itemCount: list.length,
              itemBuilder: (ctx, idx) {
                final item = list[idx];
                return _modernTipCard(item, idx);
              },
            );
          }),
        ),
        const SizedBox(height: 12),
        Obx(() {
          final total = c.cards.length;
          final cur = c.currentTipPage.value;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(total, (i) {
              final active = i == cur;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                height: 6,
                width: active ? 24 : 6,
                decoration: BoxDecoration(
                  color:
                  active ? Colors.pink.shade400 : Colors.pink.shade100,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          );
        }),
      ],
    );
  }

  Widget _modernTipCard(Map item, int idx) {
    final String title = (item['title'] ?? '').toString();
    final String subtitle = (item['subtitle'] ?? '').toString();
    final String category = (item['category'] ?? 'Tip').toString();
    final String icon = (item['icon'] ?? '💡').toString();

    return GestureDetector(
      onTap: () => _handleCardTap(category, title),
      child: Container(
        margin: EdgeInsets.only(left: idx == 0 ? 16 : 8, right: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.pink.shade50,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      category,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.pink.shade700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _tipsShimmer() {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: 3,
      itemBuilder: (ctx, idx) {
        return Container(
          width: 300,
          margin: EdgeInsets.only(left: idx == 0 ? 16 : 8, right: 16),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(20),
          ),
        );
      },
    );
  }

  // ==================== HEALTH CHECK SECTION (from old code, enhanced) ====================
  Widget _latestHealthCheckSection(HomeController c) {
    final user = c.auth.currentUser;
    if (user == null) {
      return _hcEmptyState(
        title: "You're signed out",
        subtitle: "Sign in to see your latest Health Check here.",
        cta: "Take a Health Check",
        onTap: () => Get.offAll(() => HealthSurveyPage()),
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
            onTap: () => Get.offAll(() => HealthSurveyPage()),
          );
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return _hcEmptyState(
            title: "No Health Check yet",
            subtitle:
            "Answer a few quick questions to get smart insights.",
            cta: "Take a Health Check",
            onTap: () => Get.offAll(() => HealthSurveyPage()),
          );
        }

        final data = snap.data!.docs.first.data();
        return _hcGlassySummary(data);
      },
    );
  }

  // ======= Old-code helpers & widgets (ported) =======

  num _numOrZero(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v;
    if (v is String) return num.tryParse(v.trim()) ?? 0.0;
    return 0.0;
  }

  Map<String, dynamic> _asMap(dynamic v) =>
      (v is Map<String, dynamic>) ? v : <String, dynamic>{};

  Map<String, dynamic> _pickBlock(Map<String, dynamic> data, String key) {
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

  Map<String, dynamic> _pickThyroidLocal(Map<String, dynamic> data) {
    final api = _asMap(data['apiResponse']);
    final local = _asMap(api['thyroid_local']);
    if (local.isNotEmpty) return local;

    final rootLocal = _asMap(data['thyroid_local']);
    if (rootLocal.isNotEmpty) return rootLocal;

    final details = _asMap(api['details']);
    final detailsLocal = _asMap(details['thyroid_local']);
    if (detailsLocal.isNotEmpty) return detailsLocal;

    return <String, dynamic>{};
  }

  Map<String, dynamic> _pickLocalIndicators(Map<String, dynamic> data) {
    final api = _asMap(data['apiResponse']);
    final li = _asMap(api['local_indicators']);
    if (li.isNotEmpty) return li;

    final root = _asMap(data['local_indicators']);
    if (root.isNotEmpty) return root;

    return <String, dynamic>{};
  }

  String _coalesceThyroidIndicator({
    required String single,
    required String hypo,
    required String hyper,
    required String legacy,
  }) {
    if (single.trim().isNotEmpty) return single.trim();

    bool _isElevated(String s) {
      final t = s.toLowerCase();
      return t.contains('moderate') || t.contains('high');
    }
    if (_isElevated(hypo) && _isElevated(hyper)) {
      return 'Ambiguous – Please do TSH/T3/T4 tests';
    }
    if (_isElevated(hyper)) return hyper;
    if (_isElevated(hypo)) return hypo;

    return legacy;
  }

  String _pickIndicator(Map<String, dynamic> block) {
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
    if (RegExp(r'^Model\s+high-?risk\s+probability\s*:',
        caseSensitive: false)
        .hasMatch(t)) {
      return true;
    }
    if (RegExp(r'^Model\s+confidence\s*:', caseSensitive: false)
        .hasMatch(t)) {
      return true;
    }
    return false;
  }

  List<InlineSpan> _parseBoldSpans(String text, {TextStyle? base}) {
    final spans = <InlineSpan>[];
    final reg = RegExp(r'\*\*(.+?)\*\*');
    int idx = 0;
    for (final m in reg.allMatches(text)) {
      if (m.start > idx) {
        spans.add(TextSpan(text: text.substring(idx, m.start), style: base));
      }
      spans.add(TextSpan(
        text: m.group(1),
        style: (base ?? const TextStyle())
            .merge(const TextStyle(fontWeight: FontWeight.w800)),
      ));
      idx = m.end;
    }
    if (idx < text.length) {
      spans.add(TextSpan(text: text.substring(idx), style: base));
    }
    return spans;
  }

  Widget _buildRecommendation(String rec, {required TextStyle style}) {
    final base = TextStyle(
        fontSize: 13.5, color: Colors.black.withOpacity(0.85));
    final bulletRe = RegExp(r'^\*\s+(.*)$', multiLine: true);
    final bullets =
    bulletRe.allMatches(rec).map((m) => m.group(1)!.trim()).toList();

    if (bullets.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: bullets.map((b) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Icon(Icons.circle, size: 6)),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    text:
                    TextSpan(children: _parseBoldSpans(b, base: base)),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      );
    }
    return RichText(
        text: TextSpan(children: _parseBoldSpans(rec, base: base)));
  }

  Widget _hcGlassySummary(Map<String, dynamic> data) {
    final createdAt = data['createdAt'];

    // Highest-priority single labels
    final localIndicators = _pickLocalIndicators(data);

    // Fallback blocks
    final anemia = _pickBlock(data, 'anemia');
    final pcos = _pickBlock(data, 'pcos');
    final endo = _pickBlock(data, 'endometriosis');
    final thyroid = _pickBlock(data, 'thyroid');

    final anemiaInd =
        localIndicators['anemia']?.toString() ?? _pickIndicator(anemia);
    final pcosInd =
        localIndicators['pcos']?.toString() ?? _pickIndicator(pcos);
    final endoInd =
        localIndicators['endometriosis']?.toString() ??
            _pickIndicator(endo);

    // Thyroid coalescing
    final thyroidLocal = _pickThyroidLocal(data);
    final thyroidHypo = _asMap(thyroidLocal['thyroid_hypo']);
    final thyroidHyper = _asMap(thyroidLocal['thyroid_hyper']);
    final thyroidHypoInd = _pickIndicator(thyroidHypo);
    final thyroidHyperInd = _pickIndicator(thyroidHyper);
    final thyroidIndLegacy = _pickIndicator(thyroid);
    final thyroidSingle = localIndicators['thyroid']?.toString() ?? '';

    final thyroidUnified = _coalesceThyroidIndicator(
      single: thyroidSingle,
      hypo: thyroidHypoInd,
      hyper: thyroidHyperInd,
      legacy: thyroidIndLegacy,
    );

    List _list(dynamic v) => (v is List) ? v : const [];

    final reasons = <String>{
      ..._list(anemia['reasons']).map((e) => e.toString().trim()),
      ..._list(pcos['reasons']).map((e) => e.toString().trim()),
      ..._list(endo['reasons']).map((e) => e.toString().trim()),
      ..._list(thyroidHypo['reasons']).map((e) => e.toString().trim()),
      ..._list(thyroidHyper['reasons']).map((e) => e.toString().trim()),
      ..._list(thyroid['reasons']).map((e) => e.toString().trim()),
    }.where((e) => e.isNotEmpty && !_dropReason(e)).toList();

    final recommendation = _pickRecommendation(data);

    Widget chip(String text) {
      final style = _badgeStyleFor(text);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: style.bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.black12.withOpacity(0.08)),
        ),
        child: Text(
          text,
          style: TextStyle(fontWeight: FontWeight.w800, color: style.fg),
          softWrap: true,
        ),
      );
    }

    Widget sectionTile(String title, String value) {
      if (value.isEmpty) return const SizedBox.shrink();

      final isAmbiguous = value.toLowerCase().contains('ambiguous');

      return Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black12.withOpacity(0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 6),
            Align(alignment: Alignment.centerLeft, child: chip(value)),
            if (isAmbiguous) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Icon(Icons.warning_amber_rounded,
                      size: 18, color: Color(0xFF9C6A00)),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'This result is ambiguous. Please take standard thyroid tests '
                          '(TSH, Free T3, Free T4) and consult an Endocrinologist.',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.black87,
                          height: 1.3),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.pink.shade50,
                    Colors.purple.shade50,
                    Colors.blue.shade50
                  ],
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
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 8))
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.monitor_heart_rounded,
                          size: 22, color: Colors.pink),
                      const SizedBox(width: 8),
                      const Expanded(
                          child: Text('Your Latest Health Check',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14))),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(999)),
                        child: Text(_formatTimestamp(createdAt),
                            style: TextStyle(
                                fontSize: 11,
                                color:
                                Colors.black.withOpacity(0.65))),
                      ),
                    ]),
                    const SizedBox(height: 12),

                    // Same order as results page:
                    sectionTile('Anemia', anemiaInd),
                    sectionTile('PCOS', pcosInd),
                    sectionTile('Thyroid', thyroidUnified),
                    sectionTile('Endometriosis', endoInd),


                    if (recommendation.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text('Recommendation',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.black.withOpacity(0.8))),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: Colors.black12.withOpacity(0.08)),
                        ),
                        child: _buildRecommendation(
                          recommendation,
                          style: TextStyle(
                              fontSize: 13.5,
                              color:
                              Colors.black.withOpacity(0.85)),
                        ),
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
      if (ts is Timestamp) {
        d = ts.toDate();
      } else if (ts is DateTime) {
        d = ts;
      } else {
        return '—';
      }
      final months = const [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];
      final hh = d.hour.toString().padLeft(2, '0');
      final mm = d.minute.toString().padLeft(2, '0');
      return '${d.day} ${months[d.month - 1]} ${d.year}, $hh:$mm';
    } catch (_) {
      return '—';
    }
  }

  Widget _bmiBadge(String bmi) {
    return Container(
      padding:
      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.monitor_weight, size: 16),
          const SizedBox(width: 6),
          Text('BMI: $bmi',
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _thyroidBlock(
      String indicator, double predictedPct, List<(String, double)> bars) {
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
          LayoutBuilder(builder: (ctx, cons) {
            final total =
            bars.fold<double>(0, (p, e) => p + e.$2);
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
          }),
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
                        style: TextStyle(
                            fontSize: 11.5,
                            color:
                            Colors.black.withOpacity(0.7))),
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
        return const Color(0xFF47A967); // green
      case 'Hypo':
      case 'Hypothyroid Risk':
        return const Color(0xFFE0A800); // orange
      case 'Hyper':
      case 'Hyperthyroid Risk':
        return const Color(0xFFD7263D); // red
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
      margin: const EdgeInsets.symmetric(horizontal: 16),
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
          const Icon(Icons.health_and_safety,
              color: Colors.pink, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style:
                    const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: TextStyle(
                        color: Colors.black.withOpacity(0.65))),
              ],
            ),
          ),
          TextButton(
            onPressed: onTap,
            child: const Text('Take a Health Check',
                style: TextStyle(color: Colors.pink)),
          ),
        ],
      ),
    );
  }

  Widget _hcSkeletonCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
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

  // ==================== QUICK HEALTH CHECK CTA ====================
  Widget _quickHealthCheckCTA() {
    return GestureDetector(
      onTap: () => Get.offAll(() => HealthSurveyPage()),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.pink.shade300, Colors.purple.shade300],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.pink.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.favorite_rounded,
                  color: Colors.white, size: 32),
            ),
            const SizedBox(width: 20),
            const Expanded(
              child: Text(
                'Take a Quick Health Check',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const Icon(Icons.arrow_forward_rounded, color: Colors.white),
          ],
        ),
      ),
    );
  }

  // ==================== MODERN CHAT FAB ====================
  Widget _modernChatFAB() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: [Colors.pink.shade400, Colors.pink.shade300],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.pink.withOpacity(0.4),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        onPressed: () {
          Get.to(() => const ChatFullScreenPage(),
              transition: Transition.rightToLeftWithFade);
        },
        backgroundColor: Colors.transparent,
        elevation: 0,
        icon:
        const Icon(Icons.chat_bubble_rounded, color: Colors.white),
        label: const Text(
          'Ask Me',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  // ==================== NAV HELPERS ====================
  void _handleCardTap(String category, String title) {
    final titleLower = title.toLowerCase();
    final categoryLower = category.toLowerCase();

    if (categoryLower.contains('hydration') ||
        titleLower.contains('water')) {
      Get.snackbar(
        'Water Tracking',
        'Opening water consumption tracker...',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFFE6F4FF),
        colorText: Colors.black87,
      );
      // Get.to(() => WaterTrackingPage());
    } else if (categoryLower.contains('diet') ||
        titleLower.contains('calorie') ||
        titleLower.contains('iron')) {
      Get.snackbar(
        'Nutrition Tracking',
        'Opening calorie & nutrition tracker...',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFFFFF6E7),
        colorText: Colors.black87,
      );
      Get.to(() => CalorieTrackerScreen());
    } else if (categoryLower.contains('sleep') ||
        titleLower.contains('sleep') ||
        titleLower.contains('wind-down')) {
      Get.snackbar(
        'Sleep Monitoring',
        'Opening sleep tracker...',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFFF3EBFF),
        colorText: Colors.black87,
      );
      // Get.to(() => SleepMonitoringPage());
    } else if (categoryLower.contains('movement') ||
        titleLower.contains('walk') ||
        titleLower.contains('stretch')) {
      Get.snackbar(
        'Movement Tracking',
        'Opening exercise tracker...',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFFEFF7FF),
        colorText: Colors.black87,
      );
      // Get.to(() => MovementTrackingPage());
    } else if (categoryLower.contains('tracking & symptoms')) {
      Get.snackbar(
        'Symptom Tracking',
        'Opening symptom tracker...',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFFEFFAF6),
        colorText: Colors.black87,
      );
      // Get.to(() => SymptomTrackingPage());
    } else {
      Get.snackbar(
        category,
        'Tip: $title',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 3),
        backgroundColor: Colors.white,
        colorText: Colors.black87,
        icon: Text(
          (category == 'Hygiene')
              ? '🫧'
              : (category == 'Products')
              ? '🩸'
              : (category == 'Cramps & Comfort')
              ? '🌿'
              : (category == 'Disposal & Environment')
              ? '🗑️'
              : (category == 'Travel & Backup')
              ? '🎒'
              : '💡',
          style: const TextStyle(fontSize: 20),
        ),
      );
    }
  }

  // ==================== UTILS ====================
  String _formatMonthYear(DateTime d) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return '${months[d.month - 1]} ${d.year}';
  }

  String _weekdayShort(DateTime d) {
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return days[d.weekday % 7];
  }

  bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// ===== Minimal shimmer (no package) =====
class _Shimmer extends StatefulWidget {
  const _Shimmer({Key? key}) : super(key: key);

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
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

// ===== Helper models & styles for chips =====
class _RiskChip {
  final String label;
  final double percent;
  final String tag;
  _RiskChip({required this.label, required this.percent, required this.tag});
}

class _BadgeStyle {
  final Color bg;
  final Color fg;
  const _BadgeStyle(this.bg, this.fg);
}

_BadgeStyle _badgeStyleFor(String raw) {
  final s = (raw).toString().trim().toLowerCase();

  if (s.contains('ambiguous')) {
    return const _BadgeStyle(Color(0xFFFFF3E0), Color(0xFF9C6A00)); // orange
  }
  if (s.contains('high')) {
    return const _BadgeStyle(Color(0xFFFFE8EA), Color(0xFFB90F3A)); // red
  }
  if (s.contains('moderate') ||
      s.contains('medium') ||
      s.contains('borderline')) {
    return const _BadgeStyle(Color(0xFFFFF3E0), Color(0xFF9C6A00)); // orange
  }
  if (s.contains('low') ||
      s.contains('none') ||
      s.contains('not detected') ||
      s.contains('normal')) {
    return const _BadgeStyle(Color(0xFFEAF7EE), Color(0xFF1B7F41)); // green
  }
  if (s.contains('hypo')) {
    return const _BadgeStyle(Color(0xFFFFF3E0), Color(0xFF9C6A00)); // orange
  }
  if (s.contains('hyper')) {
    return const _BadgeStyle(Color(0xFFFFE8EA), Color(0xFFB90F3A)); // red
  }

  return _BadgeStyle(Colors.black.withOpacity(0.06), Colors.black87);
}
