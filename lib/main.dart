// main.dart
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import 'app.dart';
import 'data/repositories/authentication/authentication_repository.dart';
import 'firebase_options.dart';
import 'modules/home/widgets/profile/health_check/HealthSurveyPage.dart'; // contains initHealthFlow()

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) Load .env FIRST
  await dotenv.load(fileName: ".env");

  // 2) Now do the rest
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await GetStorage.init();

  // 3) Safe to call (reads GEMINI_API_KEY from dotenv)
  initHealthFlow();

  FirebaseAuth.instance.setLanguageCode('en');

  await FirebaseAppCheck.instance.activate(
    androidProvider: kReleaseMode ? AndroidProvider.playIntegrity : AndroidProvider.debug,
  );

  if (!kReleaseMode) {
    debugPrint("🛡️ App Check debug provider active (debug).");
  }

  Get.put(AuthenticationRepository(), permanent: true);

  runApp(const MyApp());
}
