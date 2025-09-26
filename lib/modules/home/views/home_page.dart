// lib/views/home_page.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../controllers/home_controller.dart';
import '../widgets/profile/health_check/HealthSurveyPage.dart';
import '../widgets/profile/period_dates/full_screen_calendar_picket.dart';
import '../widgets/profile/profile_page.dart';

class HomePage extends StatelessWidget {
  HomePage({Key? key}) : super(key: key);
  final HomeController c = Get.put(HomeController());
  final GlobalKey _calendarStripKey = GlobalKey();

  // Slightly stronger / clearer gradients tuned for visibility
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
                SliverToBoxAdapter(child: _cardsCarousel(c)), // Tips with shimmer while loading
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
    );
  }

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

  // ===== Tips Carousel with Shimmer =====
  Widget _cardsCarousel(HomeController c) {
    return Container(
      padding: const EdgeInsets.only(left: 12),
      height: 170,
      child: Obx(() {
        final list = List<Map<String, dynamic>>.from(c.cards);

        // If tips not ready yet (or after refresh), show shimmer skeletons.
        if (list.isEmpty) {
          return _tipsShimmer();
        }

        return ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (ctx, idx) {
            final item = list[idx];
            return _tipCard(item, idx);
          },
        );
      }),
    );
  }

  // ⚡️ Shimmer skeletons (no external packages)
  Widget _tipsShimmer() {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: 3,
      separatorBuilder: (_, __) => const SizedBox(width: 12),
      itemBuilder: (ctx, _) => _ShimmerCard(),
    );
  }

  Widget _tipCard(Map item, int idx) {
    final String title = (item['title'] ?? '').toString();
    final String subtitle = (item['subtitle'] ?? '').toString();
    final String category = (item['category'] ?? 'Hygiene').toString();
    final String icon = (item['icon'] ?? '💡').toString();

    // Soft category-driven gradients
    final Map<String, List<Color>> catGrad = {
      'Hygiene': [const Color(0xFFFFE9F0), const Color(0xFFFFD6E3)],
      'Products': [const Color(0xFFE7FBF8), const Color(0xFFCFF6EE)],
      'Hydration': [const Color(0xFFE6F4FF), const Color(0xFFCCE7FF)],
      'Diet': [const Color(0xFFFFF6E7), const Color(0xFFFFE7BF)],
      'Movement': [const Color(0xFFEFF7FF), const Color(0xFFD8EAFF)],
      'Sleep & Relax': [const Color(0xFFF3EBFF), const Color(0xFFE2D7FF)],
      'Cramps & Comfort': [const Color(0xFFFFF1E9), const Color(0xFFFFDEC9)],
      'Disposal & Environment': [const Color(0xFFE8FFF1), const Color(0xFFCFF7E0)],
      'Travel & Backup': [const Color(0xFFFFF0F3), const Color(0xFFFFD7E1)],
      'Tracking & Symptoms': [const Color(0xFFEFFAF6), const Color(0xFFD6F2E7)],
    };

    final colors = catGrad[category] ?? [const Color(0xFFFDEFF1), const Color(0xFFF8F3FB)];
    final fg = _foregroundForGradient(colors);

    return Container(
      width: 300,
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
          // Top row: icon + category chip
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
    final headerText = 'Quick Symptom Check • ${today.day} ${monthNames[today.month - 1]}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Get.to(() => HealthSurveyPage());
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white,
            boxShadow: const [
              BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  headerText,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                child: Container(
                  height: 180,
                  color: Colors.deepOrange.shade400,
                  alignment: Alignment.center,
                  child: const Text(
                    'Take a Health Check',
                    style: TextStyle(
                      fontSize: 20,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
          // icon + chip row skeletons
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
    // Base + moving highlight
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
