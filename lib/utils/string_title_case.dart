import 'package:flutter/foundation.dart';

extension TitleCaseX on String {
  String toTitleCase() {
    // collapse spaces, trim, then Title Case each word
    final clean = replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return clean;
    return clean
        .split(' ')
        .map((w) => w.isEmpty
        ? w
        : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
  }
}
