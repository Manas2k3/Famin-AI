// cycle_selection_page.dart
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:famina/data/repositories/authentication/authentication_repository.dart';
import 'package:famina/modules/authentication/widgets/verify_mail.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class CycleSelectionPage extends StatefulWidget {
  const CycleSelectionPage({super.key});
  @override
  State<CycleSelectionPage> createState() => _CycleSelectionPageState();
}

class _CycleSelectionPageState extends State<CycleSelectionPage> {
  DateTime? rangeStart;
  DateTime? rangeEnd;
  DateTime focusedDay = DateTime.now();

  bool showYearPicker = false;
  final DateTime firstDay = DateTime.utc(1990, 1, 1);
  final DateTime lastDay = DateTime.utc(DateTime.now().year + 2, 12, 31);

  final _fire = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  Color get primary => Colors.pink.shade200;
  Color get surface => Colors.white;

  int? lengthDays;
  DateTime? predictedNextPeriod;
  bool _loadingPrediction = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "Tell us about your cycle",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
      ),

      // ==== Scrollable body to prevent overflow ====
      body: SafeArea(
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            final double calH = _responsiveCalHeight(context); // ~45% of screen, clamped

            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // intro + month/year toggle
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18.0),
                      child: Column(
                        children: [
                          const SizedBox(height: 6),
                          const Text(
                            "Choose the start and end date of your last period",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black87, fontSize: 15),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(32),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            padding: const EdgeInsets.all(4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _segmentedButton("Month", !showYearPicker, () => setState(() => showYearPicker = false)),
                                _segmentedButton("Year", showYearPicker, () => setState(() => showYearPicker = true)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // calendar card (bounded height; no Expanded)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                      child: Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: SizedBox(
                            height: calH,
                            child: showYearPicker ? _buildYearPicker() : _buildMonthCalendar(),
                          ),
                        ),
                      ),
                    ),

                    // range preview + prediction
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: _rangePreviewTile(label: "Start", date: rangeStart, placeholder: "Select")),
                              const SizedBox(width: 12),
                              Expanded(child: _rangePreviewTile(label: "End", date: rangeEnd, placeholder: "Select")),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (lengthDays != null || _loadingPrediction)
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.grey.shade200),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Period length', style: TextStyle(fontSize: 12, color: Colors.black54)),
                                        const SizedBox(height: 6),
                                        Text(
                                          lengthDays != null ? '$lengthDays days' : '—',
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.grey.shade200),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Next period (pred.)', style: TextStyle(fontSize: 12, color: Colors.black54)),
                                        const SizedBox(height: 6),
                                        if (_loadingPrediction)
                                          Row(
                                            children: const [
                                              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                              SizedBox(width: 8),
                                              Text('Predicting...', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                            ],
                                          )
                                        else
                                          Text(
                                            predictedNextPeriod != null ? _formatDate(predictedNextPeriod!) : '—',
                                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),

                    // CTA button
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          ),
                          onPressed: (rangeStart != null && rangeEnd != null)
                              ? () async {
                            final ok = await _saveRangeToFirestore(rangeStart!, rangeEnd!);
                            if (ok) {
                              final user = _auth.currentUser;
                              Get.to(() => VerifyMail(email: user?.email));
                            }
                          }
                              : null,
                          child: const Text(
                            "Next",
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ===== UI Helpers =====

  Widget _segmentedButton(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: active ? primary : Colors.transparent,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Text(
          label,
          style: TextStyle(color: active ? Colors.white : Colors.black87, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildMonthCalendar() {
    return TableCalendar(
      firstDay: firstDay,
      lastDay: lastDay,
      focusedDay: focusedDay,
      headerStyle: HeaderStyle(
        titleCentered: true,
        formatButtonVisible: false,
        leftChevronIcon: const Icon(Icons.chevron_left, color: Colors.black),
        rightChevronIcon: const Icon(Icons.chevron_right, color: Colors.black),
        headerPadding: const EdgeInsets.symmetric(vertical: 8),
      ),
      availableCalendarFormats: const {CalendarFormat.month: 'Month'},
      calendarStyle: CalendarStyle(
        rangeHighlightColor: primary.withOpacity(0.12),
        rangeStartDecoration: BoxDecoration(color: primary, shape: BoxShape.circle),
        rangeEndDecoration: BoxDecoration(color: primary, shape: BoxShape.circle),
        todayDecoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
        selectedDecoration: BoxDecoration(color: primary.withOpacity(0.9), shape: BoxShape.circle),
        outsideDaysVisible: false,
      ),
      calendarBuilders: CalendarBuilders(
        defaultBuilder: (context, day, fd) {
          final inRange = _isInRange(day);
          final isStart = rangeStart != null && isSameDay(day, rangeStart);
          final isEnd = rangeEnd != null && isSameDay(day, rangeEnd);
          if (isStart || isEnd) {
            return _dayTile(day.day.toString(), highlight: true);
          } else if (inRange) {
            return _dayTile(day.day.toString(), inRange: true);
          } else {
            return _dayTile(day.day.toString());
          }
        },
        dowBuilder: (context, day) => Center(
          child: Text(
            _dowLabel(day.weekday),
            style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black54),
          ),
        ),
      ),
      selectedDayPredicate: (day) => isSameDay(day, rangeStart) || isSameDay(day, rangeEnd),
      onDaySelected: (selectedDay, focused) {
        setState(() {
          focusedDay = focused;
          if (rangeStart == null) {
            rangeStart = selectedDay;
            rangeEnd = null;
          } else if (rangeStart != null && rangeEnd == null) {
            if (!selectedDay.isBefore(rangeStart!)) {
              rangeEnd = selectedDay;
            } else {
              rangeStart = selectedDay;
              rangeEnd = null;
            }
          } else {
            rangeStart = selectedDay;
            rangeEnd = null;
          }
          _recalculateDerivedValues();
        });
      },
      onPageChanged: (f) => focusedDay = f,
    );
  }

  Widget _dayTile(String label, {bool highlight = false, bool inRange = false}) {
    if (highlight) {
      return Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      );
    }
    if (inRange) {
      return Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: primary.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(color: primary, fontWeight: FontWeight.w600)),
      );
    }
    return Center(child: Text(label, style: const TextStyle(color: Colors.black87)));
  }

  Widget _buildYearPicker() {
    final currentYear = DateTime.now().year;
    return Column(
      children: [
        const SizedBox(height: 6),
        const Text("Select year", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87)),
        const SizedBox(height: 8),
        Expanded(
          child: YearPicker(
            firstDate: DateTime(1990),
            lastDate: DateTime(currentYear),
            selectedDate: focusedDay,
            onChanged: (DateTime picked) {
              setState(() {
                final month = focusedDay.month;
                final day = focusedDay.day;
                final safe = DateTime(picked.year, month, day);
                focusedDay = safe;
                showYearPicker = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Year ${picked.year} selected — pick dates now.'),
                  duration: const Duration(milliseconds: 900),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _rangePreviewTile({required String label, DateTime? date, required String placeholder}) {
    final txt = date == null ? placeholder : _formatDate(date);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 6),
          Text(txt, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  // target ~45% of screen height, clamped for sanity across devices
  double _responsiveCalHeight(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final val = h * 0.45;
    return val.clamp(320.0, 520.0);
  }

  // ===== Logic =====

  String _formatDate(DateTime d) =>
      "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  String _dowLabel(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return "Mon";
      case DateTime.tuesday:
        return "Tue";
      case DateTime.wednesday:
        return "Wed";
      case DateTime.thursday:
        return "Thu";
      case DateTime.friday:
        return "Fri";
      case DateTime.saturday:
        return "Sat";
      default:
        return "Sun";
    }
  }

  bool _isInRange(DateTime day) {
    if (rangeStart == null) return false;
    if (rangeEnd == null) return isSameDay(day, rangeStart);
    return (day.isAfter(rangeStart!) && day.isBefore(rangeEnd!)) ||
        isSameDay(day, rangeStart) ||
        isSameDay(day, rangeEnd);
  }

  Future<void> _recalculateDerivedValues() async {
    if (rangeStart == null || rangeEnd == null) {
      setState(() {
        lengthDays = null;
        predictedNextPeriod = null;
      });
      return;
    }

    final int len = rangeEnd!.difference(rangeStart!).inDays + 1;
    int cycleLength = 28;

    try {
      final user = _auth.currentUser;
      Map<String, dynamic>? userDocData;
      if (user != null) {
        final doc = await _fire.collection('Users').doc(user.uid).get();
        if (doc.exists) {
          userDocData = doc.data();
          if (userDocData!.containsKey('avg_cycle_length_days')) {
            final val = userDocData['avg_cycle_length_days'];
            if (val is num && val > 0) cycleLength = val.toInt();
          } else if (userDocData.containsKey('last_period_start_ts') &&
              userDocData.containsKey('previous_period_start_ts')) {
            try {
              final prevStart =
              (userDocData['previous_period_start_ts'] as Timestamp?)?.toDate();
              final lastStart =
              (userDocData['last_period_start_ts'] as Timestamp?)?.toDate();
              if (prevStart != null && lastStart != null) {
                final inferred = lastStart.difference(prevStart).inDays;
                if (inferred > 18 && inferred < 45) cycleLength = inferred;
              }
            } catch (_) {}
          }
        }
      }

      setState(() {
        lengthDays = len;
      });

      await _fetchGeminiPrediction(
        start: rangeStart!,
        end: rangeEnd!,
        lastLength: len,
        inferredCycleLength: cycleLength,
        userDoc: userDocData,
      );
    } catch (e) {
      setState(() {
        lengthDays = len;
        predictedNextPeriod = rangeStart!.add(Duration(days: cycleLength));
      });
    }
  }

  Future<void> _fetchGeminiPrediction({
    required DateTime start,
    required DateTime end,
    required int lastLength,
    required int inferredCycleLength,
    Map<String, dynamic>? userDoc,
  }) async {
    // dotenv fallback
    final bool hasDotEnv = dotenv.isInitialized;
    final apiKey = hasDotEnv ? dotenv.env['GEMINI_API_KEY'] : null;
    final apiEndpoint = hasDotEnv ? dotenv.env['GEMINI_API_ENDPOINT'] : null;

    if (apiKey == null || apiKey.isEmpty || apiEndpoint == null || apiEndpoint.isEmpty) {
      setState(() {
        predictedNextPeriod = start.add(Duration(days: inferredCycleLength));
        _loadingPrediction = false;
      });
      return;
    }

    setState(() {
      _loadingPrediction = true;
    });

    try {
      final payload = <String, dynamic>{
        'request_type': 'predict_next_period',
        'last_period_start': start.toIso8601String(),
        'last_period_end': end.toIso8601String(),
        'last_period_length_days': lastLength,
        'inferred_cycle_length_days': inferredCycleLength,
        'user': {
          if (userDoc != null) ...{
            'age': userDoc['age'],
            'height_cm': userDoc['height_cm'],
            'weight_kg': userDoc['weight_kg'],
            'health_conditions': userDoc['health_conditions'],
            'email': userDoc['email'],
            'name': userDoc['name'],
            'last_period_start_ts': (userDoc['last_period_start_ts'] is Timestamp)
                ? (userDoc['last_period_start_ts'] as Timestamp).toDate().toIso8601String()
                : userDoc['last_period_start_ts'],
            'previous_period_start_ts': (userDoc['previous_period_start_ts'] is Timestamp)
                ? (userDoc['previous_period_start_ts'] as Timestamp).toDate().toIso8601String()
                : userDoc['previous_period_start_ts'],
          }
        },
        'response_format': 'iso_date',
      };

      final resp = await http
          .post(
        Uri.parse(apiEndpoint),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final Map<String, dynamic> body =
        jsonDecode(resp.body) as Map<String, dynamic>;
        String? isoDate;
        if (body.containsKey('predicted_next_period')) {
          isoDate = body['predicted_next_period']?.toString();
        }
        if (isoDate == null && body.containsKey('prediction')) {
          isoDate = body['prediction']?.toString();
        }
        if (isoDate != null && isoDate.isNotEmpty) {
          try {
            final parsed = DateTime.parse(isoDate);
            setState(() {
              predictedNextPeriod = parsed;
              _loadingPrediction = false;
            });
            return;
          } catch (_) {}
        }
        if (body.containsKey('days_from_start')) {
          final v = body['days_from_start'];
          if (v is num) {
            final predicted = start.add(Duration(days: v.toInt()));
            setState(() {
              predictedNextPeriod = predicted;
              _loadingPrediction = false;
            });
            return;
          }
        }
        setState(() {
          predictedNextPeriod = start.add(Duration(days: inferredCycleLength));
          _loadingPrediction = false;
        });
        return;
      } else {
        setState(() {
          predictedNextPeriod = start.add(Duration(days: inferredCycleLength));
          _loadingPrediction = false;
        });
        return;
      }
    } catch (e) {
      setState(() {
        predictedNextPeriod = start.add(Duration(days: inferredCycleLength));
        _loadingPrediction = false;
      });
      return;
    }
  }

  Future<bool> _saveRangeToFirestore(DateTime start, DateTime end) async {
    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("You must be signed in to save cycle data.")));
      return false;
    }
    if (end.isBefore(start)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("End date cannot be before start date.")));
      return false;
    }
    final int len = end.difference(start).inDays + 1;
    await _recalculateDerivedValues(); // ensure prediction updated

    try {
      final Map<String, dynamic> payload = {
        'last_period_start_ts': Timestamp.fromDate(start),
        'last_period_end_ts': Timestamp.fromDate(end),
        'last_period_length_days': len,
        'cycle_updated_at': DateTime.now().toIso8601String(),
      };
      if (predictedNextPeriod != null) {
        payload['predicted_next_period_start_ts'] =
            Timestamp.fromDate(predictedNextPeriod!);
        payload['predicted_next_period_start'] =
            _formatDate(predictedNextPeriod!);
        payload['predicted_by'] =
        (dotenv.isInitialized && dotenv.env['GEMINI_API_KEY'] != null)
            ? 'gemini'
            : 'fallback';
      }
      final docRef = _fire.collection('Users').doc(user.uid);
      final prev = await docRef.get();
      if (prev.exists) {
        final prevData = prev.data()!;
        if (prevData.containsKey('last_period_start_ts')) {
          payload['previous_period_start_ts'] = prevData['last_period_start_ts'];
        }
      }
      await docRef.set(payload, SetOptions(merge: true));
      return true;
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Failed to save: $e")));
      return false;
    }
  }
}
