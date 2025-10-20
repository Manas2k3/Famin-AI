import 'package:flutter/material.dart';

class ResponsiveHelper {
  static bool isSmallScreen(BuildContext context) {
    return MediaQuery.of(context).size.width < 360;
  }

  static bool isMediumScreen(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= 360 && width < 600;
  }

  static bool isTablet(BuildContext context) {
    return MediaQuery.of(context).size.width >= 600;
  }

  static double getMaxWidth(BuildContext context) {
    return isTablet(context) ? 600 : double.infinity;
  }

  static EdgeInsets getScreenPadding(BuildContext context) {
    if (isSmallScreen(context)) return const EdgeInsets.all(16);
    if (isTablet(context)) return const EdgeInsets.all(32);
    return const EdgeInsets.all(20);
  }

  static double getSpacing(BuildContext context, {double small = 16, double medium = 24, double large = 32}) {
    if (isSmallScreen(context)) return small;
    if (isTablet(context)) return large;
    return medium;
  }

  static double getFontScale(BuildContext context) {
    final textScaleFactor = MediaQuery.of(context).textScaleFactor;
    return textScaleFactor.clamp(0.8, 1.3);
  }
}