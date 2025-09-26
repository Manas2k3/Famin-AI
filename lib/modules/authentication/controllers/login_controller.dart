import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:famina/utils/constants/image_strings.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../data/repositories/authentication/authentication_repository.dart';
import '../../../navigation_menu.dart';
import '../../../utils/constants/animation_strings.dart';
import '../../../utils/loaders/full_screen.dart';
import '../../../utils/loaders/loaders.dart';

class LoginController extends GetxController {
  /// Controllers for form fields
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final loginFormKey = GlobalKey<FormState>();

  /// Firebase
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Reactive password visibility toggle
  final RxBool hidePassword = true.obs;   // ✅ add this

  /// Login with email + password
  Future<void> loginWithEmail(BuildContext context) async {
    try {
      FullScreenLoader.openLoadingDialog(
        "Signing you in...",
        ImageStrings.loadingImage,
      );

      final email = emailController.text.trim();
      final password = passwordController.text.trim();

      if (!(loginFormKey.currentState?.validate() ?? false)) {
        FullScreenLoader.stopLoading(); // ❌ instead of _hideLoader()
        return;
      }

      final authRepo = AuthenticationRepository.instance;
      final userCredential =
      await authRepo.loginWithEmailandPassword(email, password);

      final User? user = userCredential.user;

      if (user != null) {
        final doc = await _firestore.collection('Users').doc(user.uid).get();

        if (doc.exists) {
          final userData = doc.data()!;
          Loaders.successSnackBar(
            title: "Login Successful",
            message: "Welcome back, ${userData['name'] ?? ''}!",
          );
          FullScreenLoader.stopLoading(); // ✅ stop here
          Get.offAll(() => NavigationMenu());
        } else {
          FullScreenLoader.stopLoading();
          Loaders.errorSnackBar(
            title: "User Not Found",
            message: "No profile found. Please sign up first.",
          );
        }
      }
    } on FirebaseAuthException catch (e) {
      FullScreenLoader.stopLoading();
      _handleFirebaseAuthException(e);
    } on FirebaseException catch (e) {
      FullScreenLoader.stopLoading();
      Loaders.errorSnackBar(
        title: 'Firebase Error',
        message: e.message ?? 'Unknown Firebase error.',
      );
    } on PlatformException catch (e) {
      FullScreenLoader.stopLoading();
      Loaders.errorSnackBar(
        title: 'Platform Error',
        message: e.message ?? 'Something went wrong on the platform side.',
      );
    } on FormatException {
      FullScreenLoader.stopLoading();
      Loaders.errorSnackBar(
        title: 'Invalid Format',
        message: 'Check your input fields.',
      );
    } catch (e) {
      FullScreenLoader.stopLoading();
      Loaders.errorSnackBar(
        title: 'Unexpected Error',
        message: e.toString(),
      );
    }
  }


  /// Handle FirebaseAuth exceptions gracefully
  /// Handle FirebaseAuth exceptions gracefully
  void _handleFirebaseAuthException(FirebaseAuthException e) {
    String message;
    switch (e.code) {
      case 'user-not-found':
        message = 'No user found with this email.';
        break;
      case 'wrong-password':
        message = 'Incorrect password. Try again.';
        break;
      case 'invalid-email':
        message = 'Invalid email format.';
        break;
      case 'user-disabled':
        message = 'This account has been disabled.';
        break;
      case 'too-many-requests':
        message = 'Too many failed attempts. Please try again later.';
        break;
      case 'network-request-failed':
        message = 'Network error. Check your internet connection.';
        break;
      case 'operation-not-allowed':
        message = 'This login method is not enabled.';
        break;
      case 'invalid-credential':
        message = 'Your login session has expired or is invalid. Please try again.';
        break;
      default:
        message = e.message ?? 'Login failed. Please try again.';
        break;
    }

    Loaders.errorSnackBar(title: "Login Failed", message: message);
  }

}
