import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../data/repositories/authentication/authentication_repository.dart';
import '../../../utils/constants/animation_strings.dart';
import '../../../utils/loaders/loaders.dart';
import '../widgets/sucesss_email.dart';

class VerifyEmailController extends GetxController {
  static VerifyEmailController get instance => Get.find();

  Timer? _pollTimer;
  final _resendCooldown = false.obs;

  @override
  void onInit() {
    super.onInit();
    _maybeSendEmailVerification();
    _startAutoRedirectTimer();
  }

  @override
  void onClose() {
    _pollTimer?.cancel();
    super.onClose();
  }

  /// Send verification only if needed and with basic error handling + cooldown
  Future<void> _maybeSendEmailVerification() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Loaders.errorSnackBar(
        title: 'Error',
        message: 'No user found. Please login again.',
      );
      return;
    }
    if (user.emailVerified) return;

    await sendEmailVerification();
  }

  Future<void> sendEmailVerification() async {
    try {
      if (_resendCooldown.value) {
        Loaders.errorSnackBar(
          title: 'Please wait',
          message: 'You can resend the verification in a few seconds.',
        );
        return;
      }

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw 'No logged in user to send verification to.';
      }
      if (currentUser.emailVerified) {
        Loaders.successSnackBar(
          title: 'Already verified',
          message: 'Your email is already verified.',
        );
        return;
      }

      await AuthenticationRepository.instance.sendEmailVerification();

      // UX: success + cooldown for resend
      Loaders.successSnackBar(
        title: 'Email Sent!',
        message: 'Please check your inbox and verify your email.',
      );

      _resendCooldown.value = true;
      // simple cooldown: 30 seconds (adjust as needed)
      Future.delayed(const Duration(seconds: 30), () {
        _resendCooldown.value = false;
      });
    } catch (e, st) {
      debugPrint('sendEmailVerification error: $e');
      debugPrint('$st');
      Loaders.errorSnackBar(
        title: 'Could not send email',
        message: e.toString(),
      );
    }
  }

  /// Polls every 5 seconds to avoid excessive reloads
  void _startAutoRedirectTimer() {
    const duration = Duration(seconds: 5);
    _pollTimer = Timer.periodic(duration, (timer) async {
      try {
        await FirebaseAuth.instance.currentUser?.reload();
        final user = FirebaseAuth.instance.currentUser;

        if (user != null && user.emailVerified) {
          timer.cancel();
          _pollTimer = null;

          Get.offAll(
                () => SucesssEmail(
              image: AnimationStrings.sucessfullyRegisteredAnimation,
              title: 'Account created successfully',
              subTitle: 'Welcome to the App',
              onPressed: () => AuthenticationRepository.instance.screenRedirect(),
            ),
          );
        }
      } catch (e) {
        debugPrint('Error while polling email verification: $e');
        // optional: show a non-invasive error or ignore transient errors
      }
    });
  }

  /// Manual check (e.g., user taps "I verified" button)
  Future<void> checkEmailVerificationStatus() async {
    try {
      await FirebaseAuth.instance.currentUser?.reload();
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null && currentUser.emailVerified) {
        _pollTimer?.cancel();
        _pollTimer = null;
        Get.off(
              () => SucesssEmail(
            image: AnimationStrings.sucessfullyRegisteredAnimation,
            title: 'Account created successfully',
            subTitle: 'Welcome to the App',
            onPressed: () => AuthenticationRepository.instance.screenRedirect(),
          ),
        );
      } else {
        Loaders.errorSnackBar(
          title: 'Not verified yet',
          message: 'We still don’t see the verification. Try again in a moment.',
        );
      }
    } catch (e) {
      debugPrint('checkEmailVerificationStatus error: $e');
      Loaders.errorSnackBar(title: 'Error', message: 'Something went wrong.');
    }
  }
}
