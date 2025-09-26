import 'package:famina/modules/authentication/views/loginPage.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';

import '../../../data/repositories/authentication/authentication_repository.dart';
import '../../../utils/constants/animation_strings.dart';
import '../../../utils/loaders/full_screen.dart';
import '../../../utils/loaders/loaders.dart';

class ForgetPasswordController extends GetxController {
  static ForgetPasswordController get instance => Get.find();

  /// Variables
  final email = TextEditingController();
  final GlobalKey<FormState> forgetPasswordFormKey = GlobalKey<FormState>();

  /// Send Reset Password Email
  Future<void> sendPasswordResetMail(BuildContext context) async {
    try {
      FullScreenLoader.openLoadingDialog(
        "We are processing your information",
        AnimationStrings.loadingAnimation,
      );

      /// Internet connection check
      final isConnected = await _isInternetConnected();
      if (!isConnected) {
        FullScreenLoader.stopLoading();
        _showNoInternetDialog(context);
        return;
      }

      /// Form Validation
      if (!(forgetPasswordFormKey.currentState?.validate() ?? false)) {
        FullScreenLoader.stopLoading();
        return;
      }

      /// Send reset email
      await AuthenticationRepository.instance
          .sendPasswordResetEmail(email.text.trim());

      FullScreenLoader.stopLoading();

      Loaders.successSnackBar(
        title: 'Email Sent!',
        message: 'Password reset link has been sent to your email!',
      );

      /// Redirect after success
      Get.offAll(() => const LoginPage());
      // or Get.to(() => ResetPassword(email: email.text.trim())); if you have that page
    } catch (e) {
      FullScreenLoader.stopLoading();
      Loaders.errorSnackBar(
        title: 'Oh Snap!',
        message: e.toString(),
      );
    }
  }

  /// Resend Reset Password Email
  Future<void> resendPasswordResetMail(String email, BuildContext context) async {
    try {
      FullScreenLoader.openLoadingDialog(
        "We are processing your information",
        AnimationStrings.loadingAnimation,
      );

      final isConnected = await _isInternetConnected();
      if (!isConnected) {
        FullScreenLoader.stopLoading();
        _showNoInternetDialog(context);
        return;
      }

      await AuthenticationRepository.instance.sendPasswordResetEmail(email);

      FullScreenLoader.stopLoading();

      Loaders.successSnackBar(
        title: 'Email Sent!',
        message: 'Another reset link has been sent to your email!',
      );
    } catch (e) {
      FullScreenLoader.stopLoading();
      Loaders.errorSnackBar(
        title: 'Oh Snap!',
        message: e.toString(),
      );
    }
  }

  /// Private helpers
  Future<bool> _isInternetConnected() async {
    return await InternetConnectionChecker.createInstance().hasConnection;
  }

  void _showNoInternetDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("No Internet"),
        content: const Text("Please check your internet connection."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }
}
