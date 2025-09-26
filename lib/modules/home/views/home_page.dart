// lib/views/home_page.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/home_controller.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
        sel.year == today.year &&
        sel.month == today.month &&
        sel.day == today.day;
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

    // 1) INSIDE PERIOD: soft warm pink gradient
    if (daysSincePeriodStart >= 0 && daysSincePeriodStart < lastLen) {
      return [const Color(0xFFFFE9ED), const Color(0xFFFFC7D1)];
    }

    // 2) approaching ovulation: calming teal
    if (daysToOv > 0 && daysToOv <= 14) {
      return [const Color(0xFFE6F9F3), const Color(0xFFBFEFEA)];
    }

    // 3) fertile window (ovulation +/-3): peach/orange highlight
    if (daysToOv >= -3 && daysToOv <= 3) {
      return [const Color(0xFFFFF7E6), const Color(0xFFFFEDCC)];
    }

    // 4) pre-period warning (<=10 days): soft warm neutral
    if (daysUntilNextPeriod > 0 && daysUntilNextPeriod <= 10) {
      return [const Color(0xFFF8F4F6), const Color(0xFFF0E7EA)];
    }

    // default: pastel pink-lavender neutral
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
            colorScheme: ColorScheme.light(
              primary: Colors.pinkAccent, // header & selected date color
              onPrimary: Colors.white, // text on primary (like month/year)
              onSurface: Colors.black, // default text
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
              child: Text('Cancel', style: TextStyle(color: Colors.redAccent)),
            ),
            TextButton(
              onPressed: () => Get.back(result: true),
              child: Text('Confirm', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      );
      if (confirm == true) {
        try {
          await c.updatePredictedNextPeriodStart(picked);
          Get.snackbar(
            'Updated',
            'Next period date saved',
            snackPosition: SnackPosition.BOTTOM,
          );
        } catch (e) {
          Get.snackbar(
            'Error',
            'Failed to save date: $e',
            snackPosition: SnackPosition.BOTTOM,
          );
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
                        ? Icon(Icons.person, color: Colors.white)
                        : null,
                  ),
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.calendar_today_outlined),
                color: fg,
                tooltip: 'Open calendar',
                onPressed: () {
                  // open full calendar modal (month / year toggle + range logging)
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
          if (c.isLoading.value)
            return const Center(child: CircularProgressIndicator());

          return RefreshIndicator(
            onRefresh: () async {
              await c.fetchUserData();
              await c.fetchCards();
              c.selectedCalendarDate.value = DateTime.now();
              c.initialCalendarDate = DateTime.now();
              c.recomputeNow();
              await Future.delayed(const Duration(milliseconds: 120));
            },
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _topPanel(context, c)),
                SliverToBoxAdapter(child: const SizedBox(height: 10)),
                SliverToBoxAdapter(child: _cardsCarousel(c)),
                SliverToBoxAdapter(child: const SizedBox(height: 12)),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([_contentCard()]),
                  ),
                ),
                SliverToBoxAdapter(child: const SizedBox(height: 80)),
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
          sel.year == today.year &&
          sel.month == today.month &&
          sel.day == today.day;
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
          big =
              '${daysUntilNextPeriod} day${daysUntilNextPeriod == 1 ? '' : 's'}';
          subtitle = 'Plan ahead';
        } else if (daysUntilNextPeriod >= 0) {
          title = 'Next period in';
          big =
              '${daysUntilNextPeriod} day${daysUntilNextPeriod == 1 ? '' : 's'}';
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

      // smaller CTA style (rounded pill)
      final ButtonStyle logPeriodStyle = ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 28),
        minimumSize: const Size(120, 44),
        shape: const StadiumBorder(),
        backgroundColor: const Color(0xFFFF6B9D),
        elevation: 0,
      );

      // Gesture-enabled top panel: swipe left/right to move selected date +/- 1 day
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
                    onSettingsTap: () =>
                        _showOvulationToggleSheet(Get.context!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // big area
            Column(
              children: [
                // small title
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    color: fgColor.withOpacity(0.95),
                  ),
                ),
                const SizedBox(height: 8),
                // hero big text — larger and more prominent
                Text(
                  big,
                  style: TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.bold,
                    color: fgColor,
                  ),
                ),
                const SizedBox(height: 10),
                // subtitle / short hint
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    color: fgColor.withOpacity(0.9),
                  ),
                ),
                const SizedBox(height: 14),
                // small info caption
                Text(
                  infoCaption,
                  style: TextStyle(
                    fontSize: 12,
                    color: fgColor.withOpacity(0.85),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    // open full calendar modal (month / year toggle + range logging)
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
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
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
    return Container(
      padding: const EdgeInsets.only(left: 12),
      height: 140,
      child: Obx(() {
        final list = List.from(c.cards);
        return ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (ctx, idx) {
            final item = list[idx];
            return _miniCard(item, idx);
          },
        );
      }),
    );
  }

  // give each card a unique soft accent so they look lively (pink, teal, lavender)
  Widget _miniCard(Map item, int idx) {
    final accents = [
      const Color(0xFFFFE9F0), // soft pink
      const Color(0xFFE7FBF8), // soft teal
      const Color(0xFFF3EBFF), // soft lavender
    ];
    final borderAccents = [
      const Color(0xFFFFA6C0),
      const Color(0xFF9DE0CC),
      const Color(0xFFCDADFF),
    ];

    final bg = accents[idx % accents.length];
    final border = borderAccents[idx % borderAccents.length];

    return Container(
      width: 150,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item['title'] ?? '',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const Spacer(),
          Text(
            item['subtitle']?.toString() ?? '',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _contentCard() {
    final today = DateTime.now();
    final monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sept',
      'Oct',
      'Nov',
      'Dec',
    ];
    final headerText =
        'My daily insights • ${today.day} ${monthNames[today.month - 1]}';

    return Container(
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
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(14),
            ),
            child: Container(
              height: 180,
              color: Colors.deepOrange.shade400,
              alignment: Alignment.center,
              child: const Text(
                'Lifestyle Enhancements',
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
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
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
