import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:iconsax/iconsax.dart';

class Loaders {
  // Static method for success SnackBar
  static void successSnackBar({
    required String title,
    required String message,
  }) {
    Get.snackbar(animationDuration: Duration(milliseconds: 1000),
      duration: Duration(milliseconds: 1000),
      title,
      message,
      isDismissible: true,
      shouldIconPulse: true,
      colorText: Colors.white,
      backgroundColor: Colors.green.shade400,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(10),
      icon: const Icon(Iconsax.check, color: Colors.white),
    );
  }

  // Static method for warning SnackBar
  static void warningSnackBar({
    required String title,
    required String message,
  }) {
    Get.snackbar(
      animationDuration: Duration(milliseconds: 1000),
      duration: Duration(milliseconds: 1000),
      title,
      message,
      isDismissible: true,
      shouldIconPulse: true,
      colorText: Colors.white,
      backgroundColor: Colors.orange.shade400,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(20),
      icon: const Icon(Iconsax.warning_2, color: Colors.white),
    );
  }

  // Static method for error SnackBar
  static void errorSnackBar({
    required String title,
    required String message,
  }) {
    Get.snackbar(
      animationDuration: Duration(milliseconds: 1000),
      duration: Duration(milliseconds: 1000),
      title,
      message,
      isDismissible: true,
      shouldIconPulse: true,
      colorText: Colors.white,
      backgroundColor: Colors.redAccent.shade400,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(10),
      icon: const Icon(
        Icons.error_outline,
        color: Colors.white,
      ),
    );
  }
}
