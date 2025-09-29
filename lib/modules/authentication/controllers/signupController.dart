import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import '../../../data/models/userModel.dart';
import '../../../data/repositories/authentication/authentication_repository.dart';
import '../../../data/repositories/user/user_repository.dart';
import '../../../utils/constants/animation_strings.dart';
import '../../../utils/constants/image_strings.dart';
import '../../../utils/loaders/full_screen.dart';
import '../../../utils/loaders/loaders.dart';
import '../views/height_page.dart';
import '../widgets/verify_mail.dart';

class SignUpController extends GetxController {
  static SignUpController get instance => Get.find();

  /// Observables & Controllers
  final _fire = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final hidePassword = true.obs;
  final email = TextEditingController();
  final firstName = TextEditingController();
  final lastName = TextEditingController();
  final password = TextEditingController();
  final privacyPolicy = false.obs;
  final GlobalKey<FormState> signUpFormKey = GlobalKey<FormState>();

  /// Main Sign-Up Function
  Future<void> signUp(BuildContext context) async {
    try {
      _showLoader();

      // Check internet
      if (!await _isInternetConnected()) {
        _hideLoader();
        _showNoInternetDialog(context);
        return;
      }

      // Validate form
      if (!_validateForm()) {
        _hideLoader();
        return;
      }

      // Build display name
      final displayName = '${firstName.text.trim()} ${lastName.text.trim()}'.trim();

      // 1) Register with Firebase Auth (repo will create base Users/{uid} doc)
      final userCredential = await AuthenticationRepository.instance
          .registerWithEmailAndPassword(
        email.text.trim(),
        password.text.trim(),
        displayName: displayName.isEmpty ? null : displayName,
        phone: null,
        sendEmailVerification: false, // we'll send verification after weight step
      );

      if (userCredential.user == null) {
        throw Exception("User creation failed.");
      }

      final uid = userCredential.user!.uid;

      // 2) Save additional user fields using your UserRepository (keeps your schema)
      await _saveUserData(uid);

      // 3) Success feedback and navigate to Height page (next step in flow)
      _hideLoader();
      Loaders.successSnackBar(
        title: 'Congratulations!',
        message: "Account created. Let's capture your height next.",
      );


      final user = _auth.currentUser;
      Get.to(HeightPage());
    } catch (e, stackTrace) {
      _handleSignUpError(e, stackTrace);
    }
  }

  /// Show Loader
  void _showLoader() {
    FullScreenLoader.openLoadingDialog(
      "We are processing your information",
      ImageStrings.loadingImage,
    );
  }

  void _hideLoader() => FullScreenLoader.stopLoading();

  /// Internet Check
  Future<bool> _isInternetConnected() async {
    return await InternetConnectionChecker.createInstance().hasConnection;
  }


  /// Form Validation
  bool _validateForm() => signUpFormKey.currentState?.validate() ?? false;

  /// Save User to Firestore (through your UserRepository)
  Future<void> _saveUserData(String userId) async {
    final newUser = UserModel(
      id: userId,
      name: '${firstName.text.trim()} ${lastName.text.trim()}',
      email: email.text.trim(),
      createdAt: DateTime.now(),
      // if your UserModel requires other fields, set defaults here
      // e.g. gutTestPaymentStatus: false, selectedRole: 'user'
    );

    final userRepository = Get.put(UserRepository());
    try {
      await userRepository.savedUserRecord(newUser);
      debugPrint('User record saved for $userId');
    } catch (e) {
      debugPrint('Failed to save user record for $userId: $e');
      // Not fatal — Firestore write may be retried later or fixed,
      // but you may want to surface this to the user in production.
    }
  }

  /// Error Handling
  void _handleSignUpError(Object e, StackTrace stackTrace) {
    _hideLoader();
    debugPrint("Error during sign-up: $e");
    debugPrint("Stack trace: $stackTrace");

    Future.delayed(const Duration(milliseconds: 100), () {
      // If this is a FirebaseAuthException, present a more friendly message
      String message = e.toString();
      if (e is Exception && e.toString().contains('email-already-in-use')) {
        message = 'That email is already registered. Try logging in or use a different email.';
      }
      Loaders.errorSnackBar(
        title: "Oh Snap!",
        message: message,
      );
    });
  }

  /// No Internet Dialog
  void _showNoInternetDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
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
