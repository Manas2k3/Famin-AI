import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

class PeriodTrackerSummary extends StatelessWidget {
  final DateTime startDate;
  final DateTime endDate;
  final bool isLoading; // Add a loading flag

  const PeriodTrackerSummary({
    super.key,
    required this.startDate,
    required this.endDate,
    this.isLoading = false, // Default false
  });

  @override
  Widget build(BuildContext context) {
    int cycleLength = 28;
    int periodLength = endDate.difference(startDate).inDays + 1;
    int daysSinceStart = DateTime.now().difference(startDate).inDays;
    int daysIntoCycle = daysSinceStart % cycleLength;
    int daysUntilNext = cycleLength - daysIntoCycle;
    DateTime nextPeriodDate = DateTime.now().add(Duration(days: daysUntilNext));

    double progress = daysIntoCycle / cycleLength;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "Period Tracker",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.black),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Banner image shimmer
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: isLoading
                  ? shimmerBox(height: 180, width: double.infinity)
                  : Image.network(
                "https://flo.health/uploads/media/sulu-1200x630/09/5259-Menstrual%20calendar%20used%20to%20track%20how%20long%20a%20period%20usually%20lasts.jpg?v=1-0&inline=1",
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 16),

            // Text shimmer or actual data
            Align(
              alignment: Alignment.centerLeft,
              child: isLoading
                  ? shimmerBox(height: 16, width: 200)
                  : const Text(
                "Your next period is expected on:",
                style: TextStyle(color: Colors.black87, fontSize: 16),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: isLoading
                  ? shimmerBox(height: 18, width: 120)
                  : Text(
                DateFormat.MMMd().format(nextPeriodDate),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: isLoading
                  ? shimmerBox(height: 14, width: 150)
                  : Text(
                "Cycle status:\nDay $daysIntoCycle of $cycleLength",
                style:
                const TextStyle(color: Colors.black87, fontSize: 14),
              ),
            ),

            const SizedBox(height: 8),
            isLoading
                ? shimmerBox(height: 40, width: double.infinity)
                : Container(
              padding:
              const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                "Based on your last input, we've estimated your cycle progress",
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),

            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: isLoading
                  ? shimmerBox(height: 15, width: 180)
                  : const Text(
                "Current Cycle Progress",
                style:
                TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
              ),
            ),
            const SizedBox(height: 8),
            isLoading
                ? shimmerBox(height: 4, width: double.infinity)
                : LinearProgressIndicator(
              borderRadius: BorderRadius.circular(24),
              value: progress,
              backgroundColor: Colors.grey.shade300,
              color: Colors.black,
              minHeight: 6,
            ),

            const SizedBox(height: 20),
            isLoading
                ? Row(
              children: [
                Expanded(child: shimmerBox(height: 48)),
                const SizedBox(width: 12),
                Expanded(child: shimmerBox(height: 48)),
              ],
            )
                : Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                    ),
                    onPressed: () {},
                    child: const Text("Edit Dates", style: TextStyle(color: Colors.black)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                    ),
                    onPressed: () {},
                    child: const Text("Set Reminder", style: TextStyle(color: Colors.white),),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Helper shimmer widget
  Widget shimmerBox({double? height, double? width}) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
