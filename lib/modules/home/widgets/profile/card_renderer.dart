import 'package:flutter/material.dart';
import 'package:get/get.dart';

class CardRenderer extends StatelessWidget {
  final Map<String, dynamic> card;
  CardRenderer(this.card);

  @override
  Widget build(BuildContext context) {
    final type = card['type'] ?? 'generic';
    switch (type) {
      case 'insight':
        return _insightCard(card);
      case 'survey_prompt':
        return _surveyCard(card);
      case 'recommendation':
        return _recommendCard(card);
      default:
        return _genericCard(card);
    }
  }

  Widget _insightCard(Map c) {
    final valueChange = (c['valueChange'] ?? 0).toDouble();
    final valueStr = c['value']?.toString() ?? '';
    final color = valueChange > 0 ? Colors.green : (valueChange < 0 ? Colors.red : Colors.grey);
    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c['title'] ?? '', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            Text(c['subtitle'] ?? '', style: TextStyle(color: Colors.grey.shade600)),
          ])),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(valueStr, style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 6),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  (valueChange > 0 ? '+' : '') + valueChange.toString(),
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _surveyCard(Map c) {
    return ListTile(
      tileColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(c['title'] ?? ''),
      subtitle: Text(c['subtitle'] ?? ''),
      trailing: ElevatedButton(
        onPressed: () => Get.toNamed(c['action']?['route'] ?? '/survey'),
        child: Text(c['action']?['label'] ?? 'Start'),
      ),
    );
  }

  Widget _recommendCard(Map c) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.blue.shade50),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Expanded(child: Text(c['title'] ?? '')), ElevatedButton(onPressed: () => Get.toNamed(c['action']?['route'] ?? '/'), child: Text(c['action']?['label'] ?? 'Do'))],
      ),
    );
  }

  Widget _genericCard(Map c) => Card(child: Padding(padding: EdgeInsets.all(12), child: Text(c['title'] ?? '')));
}
