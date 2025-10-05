// lib/data/repositories/authentication/authentication_repository.dart
// Modified to fix the navigation race condition

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../../../modules/authentication/views/additional_period_related_questions.dart';
import '../../../modules/authentication/views/birth_year_page.dart';
import '../../../modules/authentication/views/health_conditions_page.dart';
import '../../../modules/authentication/views/height_page.dart';
import '../../../modules/authentication/views/loginPage.dart';
import '../../../modules/authentication/views/signUpPage.dart';
import '../../../modules/authentication/views/weight_page.dart';
import '../../../modules/onboarding/onboarding.dart';
import '../../../modules/privacy_policy/privacyPolicyConsent.dart';
import '../../../modules/authentication/widgets/verify_mail.dart';
import '../../../navigation_menu.dart';

class AuthenticationRepository extends GetxController {
  static AuthenticationRepository get instance => Get.find();

  // Keys
  static const _consentAcceptedKey = 'hasAcceptedConsent';
  static const _firstLaunchKey = 'hasSeenOnboarding';
  static const _hasSignedUpKey = 'hasCompletedSignup';
  static const _heightDoneKey = 'hasCompletedHeight';
  static const _weightDoneKey = 'hasCompletedWeight';
  static const _healthDoneKey = 'hasCompletedHealthConditions';
  static const _birthDoneKey = 'hasCompletedBirth';
  // New keys for the 4 period-question pages
  static const _bloodDoneKey = 'hasCompletedBlood';
  static const _cycleRegularDoneKey = 'hasCompletedCycleRegular';
  static const _periodDurationDoneKey = 'hasCompletedPeriodDuration';
  static const _avgCycleDoneKey = 'hasCompletedAvgCycle';

  final GetStorage deviceStorage = GetStorage();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _fire = FirebaseFirestore.instance;

  StreamSubscription<User?>? _authSub;
  bool _initialized = false;
  bool _isNavigating = false;

  /// Initialize storage defaults. Do NOT navigate here.
  Future<void> init() async {
    if (_initialized) return;

    // initialize GetStorage (no-op if already done)
    await GetStorage.init();

    // ensure defaults exist
    deviceStorage.writeIfNull(_consentAcceptedKey, false);
    deviceStorage.writeIfNull(_firstLaunchKey, false);
    deviceStorage.writeIfNull(_hasSignedUpKey, false);
    deviceStorage.writeIfNull(_heightDoneKey, false);
    deviceStorage.writeIfNull(_weightDoneKey, false);
    deviceStorage.writeIfNull(_healthDoneKey, false);
    deviceStorage.writeIfNull(_birthDoneKey, false);

    // new period-question defaults
    deviceStorage.writeIfNull(_bloodDoneKey, false);
    deviceStorage.writeIfNull(_cycleRegularDoneKey, false);
    deviceStorage.writeIfNull(_periodDurationDoneKey, false);
    deviceStorage.writeIfNull(_avgCycleDoneKey, false);

    _initialized = true;
  }

  /// Call this AFTER the app is running (e.g. from SplashScreen)
  /// It sets up the auth listener and performs an initial redirect.
  Future<void> initAndRedirect() async {
    if (!_initialized) await init();

    // prevent multiple listeners
    await _authSub?.cancel();

    // IMPORTANT: Wait for auth state to be ready
    await _auth.authStateChanges().first;

    _authSub = _auth.authStateChanges().listen((user) {
      // Handle sign-in/out events while app is running.
      _handleAuthStateChange(user);
    });

    // Perform a one-time redirect based on stored flags + auth state:
    await screenRedirect();
  }

  @override
  void onClose() {
    _authSub?.cancel();
    super.onClose();
  }

  /// Reset all signup-related flags so a fresh signup flow can occur.
  Future<void> resetSignupFlow({bool keepConsent = true, bool keepOnboarding = false}) async {
    // Keys to reset
    final keysToReset = [
      _hasSignedUpKey,
      _heightDoneKey,
      _weightDoneKey,
      _healthDoneKey,
      _birthDoneKey,
      _bloodDoneKey,
      _cycleRegularDoneKey,
      _periodDurationDoneKey,
      _avgCycleDoneKey,
    ];

    for (final k in keysToReset) {
      await deviceStorage.write(k, false);
    }

    // optionally clear onboarding/consent
    if (!keepConsent) await deviceStorage.write(_consentAcceptedKey, false);
    if (!keepOnboarding) await deviceStorage.write(_firstLaunchKey, false);
  }

  /// Improved logout that also resets signup steps so the next "Sign Up"
  /// starts from scratch. Call this from your logout button handler.
  Future<void> logOutAndReset({bool keepConsent = true, bool keepOnboarding = false}) async {
    // sign out from firebase
    await _auth.signOut();

    // clear stored signup progress (so next signup prompts all pages)
    await resetSignupFlow(keepConsent: keepConsent, keepOnboarding: keepOnboarding);

    // optionally re-run redirect to send user to SignUpPage
    await screenRedirect();
  }

  /// Decide start route (can be called multiple times)
  // authentication_repository.dart (only the changed parts)

  Future<void> screenRedirect() async {
    if (_isNavigating) return;
    _isNavigating = true;

    try {
      if (!_initialized) await init();

      final user = _auth.currentUser;
      // read flags up front
      final hasConsent = deviceStorage.read(_consentAcceptedKey) ?? false;
      final hasOnboarded = deviceStorage.read(_firstLaunchKey) ?? false;
      final signedUp = deviceStorage.read(_hasSignedUpKey) ?? false;
      final heightDone = deviceStorage.read(_heightDoneKey) ?? false;
      final weightDone = deviceStorage.read(_weightDoneKey) ?? false;
      final birthDone = deviceStorage.read(_birthDoneKey) ?? false;
      final healthDone = deviceStorage.read(_healthDoneKey) ?? false;

      // helper to push the first incomplete step
      Future<void> _routeToFirstIncompleteStep() async {
        if (!hasConsent)         { Get.offAll(() => const PrivacyConsentPage()); return; }
        if (!hasOnboarded)       { Get.offAll(() => const OnboardingPage());     return; }
        if (!signedUp)           { Get.offAll(() => const SignUpPage());         return; }
        if (!heightDone)         { Get.offAll(() => const HeightPage());         return; }
        if (!weightDone)         { Get.offAll(() => const WeightPage());         return; }
        if (!birthDone)          { Get.offAll(() => const BirthYearPage());      return; }
        if (!healthDone)         { Get.offAll(() => const HealthConditionsPage()); return; }

        // All steps done but might not be verified yet.
        // At this point, if the user exists and is NOT verified -> go VerifyMail.
        final u = _auth.currentUser;
        if (u != null && !(u.emailVerified)) {
          Get.offAll(() => VerifyMail(email: u.email));
          return;
        }

        // Fallback
        Get.offAll(() => const SignUpPage());
      }

      if (user != null) {
        try { await user.reload(); } catch (_) {}
        final refreshed = _auth.currentUser;

        if (refreshed != null && refreshed.emailVerified) {
          // Fully authenticated → home
          Get.offAll(() => NavigationMenu());
          return;
        }

        // NOT verified → continue the step flow instead of VerifyMail
        await _routeToFirstIncompleteStep();
        return;
      }

      // No user signed in → run flow from the top
      await _routeToFirstIncompleteStep();

    } finally {
      _isNavigating = false;
    }
  }

  Future<void> _handleAuthStateChange(User? user) async {
    if (!_initialized) return;
    if (_isNavigating) return;
    _isNavigating = true;

    try {
      if (user != null) {
        try { await user.reload(); } catch (_) {}
        final refreshed = _auth.currentUser;

        if (refreshed != null && refreshed.emailVerified) {
          Get.offAll(() => NavigationMenu());
          return;
        }

        // Not verified? Don’t force VerifyMail here—defer to screenRedirect()
        await screenRedirect();
        return;
      }

      // Signed out → normal flow
      await screenRedirect();

    } finally {
      _isNavigating = false;
    }
  }


  // Step completion helpers (call from UI)
  void completeConsent() => deviceStorage.write(_consentAcceptedKey, true);
  void completeOnboarding() => deviceStorage.write(_firstLaunchKey, true);
  void completeSignup() => deviceStorage.write(_hasSignedUpKey, true);
  void completeHeight() => deviceStorage.write(_heightDoneKey, true);
  void completeWeight() => deviceStorage.write(_weightDoneKey, true);
  void completeBirth() => deviceStorage.write(_birthDoneKey, true);
  void completeHealthConditions() => deviceStorage.write(_healthDoneKey, true);

  // New completion helpers for the period-question pages
  void completeBlood() => deviceStorage.write(_bloodDoneKey, true);
  void completeCycleRegular() => deviceStorage.write(_cycleRegularDoneKey, true);
  void completePeriodDuration() => deviceStorage.write(_periodDurationDoneKey, true);
  void completeAvgCycle() => deviceStorage.write(_avgCycleDoneKey, true);

  /// Register user and create minimal Firestore doc
  Future<UserCredential> registerWithEmailAndPassword(String email, String password,
      {String? displayName, String? phone, bool sendEmailVerification = true}) async {
    final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
    final uid = cred.user?.uid;
    if (uid == null) throw 'Failed to create user';

    await _fire.collection('Users').doc(uid).set({
      'id': uid,
      'email': email,
      'name': displayName ?? '',
      'phone': phone ?? '',
      'createdAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));

    completeSignup();

    if (sendEmailVerification) {
      try {
        await cred.user?.sendEmailVerification();
      } catch (_) {}
    }

    return cred;
  }

  Future<UserCredential> loginWithEmailandPassword(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> sendEmailVerification() async => _auth.currentUser?.sendEmailVerification();
  Future<void> sendPasswordResetEmail(String email) async => _auth.sendPasswordResetEmail(email: email);
  Future<void> logOut() async => _auth.signOut();
}