// lib/widgets/calendar_full_view.dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../controllers/home_controller.dart'; // import your controller file

class CalendarFullView extends StatefulWidget {
  final HomeController controller;

  const CalendarFullView({Key? key, required this.controller})
      : super(key: key);

  @override
  State<CalendarFullView> createState() => _CalendarFullViewState();
}

class _CalendarFullViewState extends State<CalendarFullView> {
  bool showingYear = false;
  bool editing = false; // edit mode toggle

  DateTime visibleMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  );
  DateTime selectedDate = DateTime.now();

  // persisted (existing) last saved summary range (kept to prefill UI)
  DateTime? rangeStart;
  DateTime? rangeEnd;

  // New: multiple pending ranges during edit mode
  List<Map<String, DateTime>> pendingRanges = [];
  DateTime? tempStart; // first tap while editing (awaiting end)

  // centralized font size for day numbers (change this to increase/decrease all date numbers)
  final double _dayFontSize = 18.0;

  // animation direction for page-turn effect: 1 = forward (next), -1 = backward (prev)
  int _animationDirection = 1;

  bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime _normalize(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    selectedDate = widget.controller.selectedCalendarDate.value;
    visibleMonth = DateTime(selectedDate.year, selectedDate.month, 1);

    // preload last saved range (summary fields)
    rangeStart = widget.controller.lastPeriodStart.value;
    rangeEnd = widget.controller.lastPeriodEnd.value;
  }

  void _prevMonth() {
    setState(() {
      _animationDirection = -1;
      visibleMonth = DateTime(visibleMonth.year, visibleMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _animationDirection = 1;
      visibleMonth = DateTime(visibleMonth.year, visibleMonth.month + 1, 1);
    });
  }

  void _prevYear() {
    setState(() {
      visibleMonth = DateTime(visibleMonth.year - 1, visibleMonth.month, 1);
    });
  }

  void _nextYear() {
    setState(() {
      visibleMonth = DateTime(visibleMonth.year + 1, visibleMonth.month, 1);
    });
  }

  void _showUnifiedSnackbar(String title, String message, {bool isError = false}) {
    Get.closeAllSnackbars();
    Get.rawSnackbar(
      titleText: Text(
        title,
        style: TextStyle(
          color: isError ? Colors.redAccent : Colors.pinkAccent,
          fontWeight: FontWeight.bold,
        ),
      ),
      messageText: Text(
        message,
        style: const TextStyle(color: Colors.black87, fontSize: 14),
      ),
      backgroundColor: Colors.white,
      borderRadius: 12,
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      snackPosition: SnackPosition.BOTTOM,
      borderColor: Colors.pinkAccent.withOpacity(0.4),
      borderWidth: 1.2,
      icon: Icon(
        isError ? Icons.error_outline : Icons.favorite,
        color: isError ? Colors.redAccent : Colors.pinkAccent,
      ),
      duration: const Duration(milliseconds: 1500),
      animationDuration: const Duration(milliseconds: 400),
    );
  }

  /// Check if a day is contained in either:
  /// - any pendingRanges
  /// - the summary range (rangeStart..rangeEnd)
  /// - the historical saved ranges in controller.periodHistory
  bool _isInRange(DateTime day) {
    final d = _normalize(day);

    // check pending ranges first
    for (final r in pendingRanges) {
      final a = _normalize(r['start']!);
      final b = _normalize(r['end']!);
      if (!d.isBefore(a) && !d.isAfter(b)) return true;
    }

    // check summary range
    if (rangeStart != null) {
      final a = _normalize(rangeStart!);
      final b = rangeEnd == null ? a : _normalize(rangeEnd!);
      if (!d.isBefore(a) && !d.isAfter(b)) return true;
    }

    // check controller history
    for (final p in widget.controller.periodHistory) {
      if (!d.isBefore(_normalize(p.start)) && !d.isAfter(_normalize(p.end)))
        return true;
    }

    return false;
  }

  bool _isPendingStart(DateTime day) {
    final d = _normalize(day);
    for (final r in pendingRanges) {
      if (_isSameDate(_normalize(r['start']!), d)) return true;
    }
    return false;
  }

  bool _isPendingEnd(DateTime day) {
    final d = _normalize(day);
    for (final r in pendingRanges) {
      if (_isSameDate(_normalize(r['end']!), d)) return true;
    }
    return false;
  }

  bool _isHistoric(DateTime day) {
    final d = _normalize(day);
    return widget.controller.periodHistory.any(
          (p) => !d.isBefore(_normalize(p.start)) && !d.isAfter(_normalize(p.end)),
    );
  }

  /// Gesture-friendly month grid: we wrap the month grid in a GestureDetector
  /// so swiping left/right switches months. The year view remains tappable.
  Widget _buildMonthGridWrapped(DateTime month) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        // primaryVelocity > 0 => user swiped right => go to previous month
        // primaryVelocity < 0 => user swiped left => go to next month
        final v = details.primaryVelocity ?? 0.0;
        if (v > 200) {
          setState(() => _animationDirection = -1);
          _prevMonth();
        } else if (v < -200) {
          setState(() => _animationDirection = 1);
          _nextMonth();
        }
      },
      onHorizontalDragUpdate: (details) {
        // optional: if you want to respond to slower swipes you could accumulate delta dx.
        // left empty for now — only use end velocity to switch months
      },
      child: _buildMonthGrid(month),
    );
  }

  Widget _buildMonthGrid(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final startWeekday = first.weekday % 7; // Sun==0
    final totalCells = ((startWeekday + daysInMonth) / 7).ceil() * 7;

    return Column(
      children: [
        // Weekday headers
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
              .map(
                (d) => Expanded(
              child: Center(
                child: Text(
                  d,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black54,
                  ),
                ),
              ),
            ),
          )
              .toList(),
        ),
        const SizedBox(height: 8),
        GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: totalCells,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 1.0,
          ),
          itemBuilder: (context, index) {
            final dayIndex = index - startWeekday + 1;
            if (dayIndex < 1 || dayIndex > daysInMonth) {
              return const SizedBox.shrink();
            }

            final day = DateTime(month.year, month.month, dayIndex);
            final dayNorm = _normalize(day);

            final predicted =
                widget.controller.predictedNextPeriodStart.value != null &&
                    _isSameDate(
                      _normalize(widget.controller.predictedNextPeriodStart.value!),
                      dayNorm,
                    );

            final isSavedStart =
                widget.controller.lastPeriodStart.value != null &&
                    _isSameDate(
                      _normalize(widget.controller.lastPeriodStart.value!),
                      dayNorm,
                    );
            final isSavedEnd =
                widget.controller.lastPeriodEnd.value != null &&
                    _isSameDate(
                      _normalize(widget.controller.lastPeriodEnd.value!),
                      dayNorm,
                    );

            final pendingStart = _isPendingStart(dayNorm);
            final pendingEnd = _isPendingEnd(dayNorm);
            final inRange = _isInRange(dayNorm);
            final isHistoric = _isHistoric(dayNorm);

            final isSelected = _isSameDate(selectedDate, dayNorm);

            final dayTextColor = (day.isBefore(DateTime.now()))
                ? Colors.grey.shade600
                : Colors.black87;

            Widget content = Text(
              '$dayIndex',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: dayTextColor,
                fontSize: _dayFontSize,
              ),
            );

            // Visual priority:
            // 1) Final saved start/end -> solid pink circle
            // 2) Pending start/end -> border circle
            // 3) inRange (any saved/pending) -> soft fill
            // 4) predicted -> dotted border
            // 5) historic -> dot
            // 6) selected -> green text
            if (isSavedStart || isSavedEnd) {
              content = Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF6B9D),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$dayIndex',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: _dayFontSize,
                  ),
                ),
              );
            } else if (pendingStart || pendingEnd) {
              content = Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: pendingStart ? Colors.teal : Colors.pinkAccent,
                    width: 2,
                  ),
                  color: Colors.white,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$dayIndex',
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w700,
                    fontSize: _dayFontSize,
                  ),
                ),
              );
            } else if (inRange) {
              content = Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$dayIndex',
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w700,
                    fontSize: _dayFontSize,
                  ),
                ),
              );
            } else if (predicted) {
              content = Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF0FA79A), width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$dayIndex',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: _dayFontSize,
                  ),
                ),
              );
            } else if (isHistoric) {
              content = Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    '$dayIndex',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: dayTextColor,
                      fontSize: _dayFontSize,
                    ),
                  ),
                  const Positioned(
                    bottom: 6,
                    child: SizedBox(
                      width: 6,
                      height: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.pinkAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            } else if (isSelected) {
              content = Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                child: Text(
                  '$dayIndex',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0FA79A),
                    fontSize: _dayFontSize,
                  ),
                ),
              );
            }

            // Enlarge tappable area with padding to make taps easier (user requested)
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                // Always update selectedDate
                setState(() {
                  selectedDate = dayNorm;
                  widget.controller.selectedCalendarDate.value = dayNorm;
                  widget.controller.recomputeNow();
                });

                if (!editing) return;

                // In editing mode: Block future dates
                final today = _normalize(DateTime.now());
                if (dayNorm.isAfter(today)) {
                  _showUnifiedSnackbar(
                    'Invalid',
                    'Cannot log future periods',
                    isError: true, // optional: makes it red accent instead of pink
                  );
                  return;
                }

                // If tempStart is null -> first tap (set temp start)
                if (tempStart == null) {
                  setState(() {
                    tempStart = dayNorm;
                  });
                  _showUnifiedSnackbar('Start selected', 'Start: ${dayNorm.toIso8601String().split("T").first}');
                  return;
                }

                // If tempStart set and this tap will become end
                if (tempStart != null) {
                  DateTime a = _normalize(tempStart!);
                  DateTime b = dayNorm;
                  if (b.isBefore(a)) {
                    final tmp = a;
                    a = b;
                    b = tmp;
                  }
                  setState(() {
                    pendingRanges.add({'start': a, 'end': b});
                    tempStart = null; // ready for next range
                  });

                  _showUnifiedSnackbar(
                    'Range added',
                    '${a.toIso8601String().split("T").first} → ${b.toIso8601String().split("T").first}',
                  );
                  return;
                }
              },
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(6.0),
                  // makes tap target larger than the visible circle
                  child: content,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  String _monthName(int m) => const [
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
    'December',
  ][m - 1];

  @override
  Widget build(BuildContext context) {
    final header = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        Column(
          children: [
            Text(
              showingYear
                  ? '${visibleMonth.year}'
                  : '${_monthName(visibleMonth.month)} ${visibleMonth.year}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () {
                if (showingYear)
                  _prevYear();
                else
                  _prevMonth();
              },
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () {
                if (showingYear)
                  _nextYear();
                else
                  _nextMonth();
              },
            ),
          ],
        ),
      ],
    );

    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              header,
              const SizedBox(height: 12),
              // Toggle Month / Year
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ChoiceChip(
                    label: const Text('Month'),
                    selected: !showingYear,
                    onSelected: (v) =>
                        setState(() => showingYear = !v ? true : false),
                  ),
                  const SizedBox(width: 12),
                  ChoiceChip(
                    label: const Text('Year'),
                    selected: showingYear,
                    onSelected: (v) => setState(() => showingYear = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: showingYear
                    ? _buildYearView(visibleMonth.year)
                    : SingleChildScrollView(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 550),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) {
                      // page-turn like rotation on Y axis
                      final rotateAnim = Tween<double>(
                        begin: (_animationDirection == 1) ? pi / 2 : -pi / 2,
                        end: 0.0,
                      ).animate(animation);

                      return AnimatedBuilder(
                        animation: rotateAnim,
                        child: child,
                        builder: (context, child) {
                          final value = rotateAnim.value;
                          final transform = Matrix4.identity()
                            ..setEntry(3, 2, 0.001)
                            ..rotateY(value);

                          return Transform(
                            transform: transform,
                            alignment: (_animationDirection == 1)
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: child,
                          );
                        },
                      );
                    },
                    child: KeyedSubtree(
                      // key must change when month changes to trigger animation
                      key: ValueKey('${visibleMonth.year}-${visibleMonth.month}'),
                      child: _buildMonthGridWrapped(visibleMonth),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // If editing show pending list preview (compact)
              if (editing && pendingRanges.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                  child: Column(
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Pending ranges:',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 56,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: pendingRanges.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (ctx, i) {
                            final r = pendingRanges[i];
                            final a = r['start']!;
                            final b = r['end']!;
                            return Chip(
                              label: Text(
                                '${a.toIso8601String().split("T").first} → ${b.toIso8601String().split("T").first}',
                              ),
                              deleteIcon: const Icon(Icons.close),
                              onDeleted: () {
                                setState(() {
                                  pendingRanges.removeAt(i);
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),

              // Footer buttons
              if (!editing)
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.pinkAccent,
                          minimumSize: const Size(double.infinity, 48),
                        ),
                        onPressed: () {
                          setState(() {
                            editing = true;
                            pendingRanges.clear();
                            tempStart = null;
                            // we keep existing saved summary range visible but not auto-selected
                          });
                        },
                        child: const Text('Edit Period Dates'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      height: 48,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text('Close',style: TextStyle(color: Colors.black), ),
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.pink,
                          minimumSize: const Size(double.infinity, 48),
                        ),
                        onPressed: pendingRanges.isEmpty
                            ? null
                            : () async {
                          // Save all pending ranges serially
                          try {
                            for (final r
                            in List<Map<String, DateTime>>.from(
                              pendingRanges,
                            )) {
                              final a = _normalize(r['start']!);
                              final b = _normalize(r['end']!);
                              await widget.controller.setPeriodRange(
                                a,
                                b,
                                fromUser: true,
                                saveToHistory: true,
                              );
                            }

                            // success
                            setState(() {
                              editing = false;
                              pendingRanges.clear();
                              tempStart = null;
                              // refresh local summary range from controller
                              rangeStart =
                                  widget.controller.lastPeriodStart.value;
                              rangeEnd =
                                  widget.controller.lastPeriodEnd.value;
                            });
                            _showUnifiedSnackbar(
                              'Saved',
                              'All selected periods have been saved',
                            );
                          } catch (e) {
                            _showUnifiedSnackbar(
                              'Error',
                              'Failed to save: $e',
                              isError: true,
                            );
                          }
                        },
                        child: const Text('Save'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      height: 48,
                      child: TextButton(
                        onPressed: () {
                          // cancel editing (discard pending ranges)
                          setState(() {
                            editing = false;
                            pendingRanges.clear();
                            tempStart = null;
                          });
                        },
                        child: Text('Cancel',style: TextStyle(color: Colors.black),),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildYearView(int year) {
    final months = List.generate(12, (i) => DateTime(year, i + 1, 1));
    return GridView.count(
      crossAxisCount: 3,
      childAspectRatio: 1.4,
      padding: const EdgeInsets.all(8),
      children: months.map((m) {
        return GestureDetector(
          onTap: () {
            setState(() {
              showingYear = false;
              visibleMonth = DateTime(m.year, m.month, 1);
            });
          },
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                children: [
                  Text(
                    '${_monthShort(m.month)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Center(
                      child: Text(
                        '${m.month}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  String _monthShort(int m) {
    const names = [
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
      'December',
    ];
    return names[m - 1];
  }
}
