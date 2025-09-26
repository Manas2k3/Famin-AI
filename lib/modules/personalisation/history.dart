import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class ScanHistoryPage extends StatelessWidget {
  const ScanHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> scanHistory = [
      {
        "date": "2024-01-15",
        "time_period": "Cycle Day 14",
        "desc": "Normal Discharge",
        "image":
        "https://nuawoman.com/blog/wp-content/uploads/2024/05/Menstrual-Hygiene-with-Nua-scaled.jpg"
      },
      {
        "date": "2023-10-22",
        "time_period": "Cycle Day 21",
        "desc": "Signs of mild infection",
        "image":
        "https://static.vecteezy.com/system/resources/previews/041/449/261/non_2x/cartoon-style-illustration-of-a-menstruation-sanitary-napkins-doodle-period-pads-isolated-on-white-vector.jpg"
      },
      {
        "date": "2023-07-05",
        "time_period": "Cycle Day 12",
        "desc": "Ovulation approaching",
        "image":
        "https://nuawoman.com/blog/wp-content/uploads/2024/05/Menstrual-Hygiene-with-Nua-scaled.jpg"
      },
      {
        "date": "2023-04-12",
        "time_period": "Cycle Day 28",
        "desc": "Pre-menstural symptoms",
        "image":
        "https://static.vecteezy.com/system/resources/previews/041/449/261/non_2x/cartoon-style-illustration-of-a-menstruation-sanitary-napkins-doodle-period-pads-isolated-on-white-vector.jpg"
      },
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "Scan History",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Filter buttons
            Row(
              children: [
                _filterChip("All", true),
                const SizedBox(width: 8),
                _filterChip("Last 3 Months", false),
                const SizedBox(width: 8),
                _filterChip("Last 6 Months", false),
              ],
            ),
            const SizedBox(height: 16),

            // Scan History List
            Expanded(
              child: ListView.separated(
                itemCount: scanHistory.length,
                separatorBuilder: (context, index) =>
                const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final scan = scanHistory[index];
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              scan["date"]!,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.redAccent,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              scan["time_period"]!,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              scan["desc"]!,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.redAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Image with shimmer loading
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          scan["image"]!,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Shimmer.fromColors(
                              baseColor: Colors.grey.shade300,
                              highlightColor: Colors.grey.shade100,
                              child: Container(
                                width: 80,
                                height: 80,
                                color: Colors.white,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFF5F3F3) : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? Colors.transparent : Colors.grey.shade300,
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.black87,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
