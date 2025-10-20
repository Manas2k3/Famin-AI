// main.dart
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'data/repositories/authentication/authentication_repository.dart';
import 'firebase_options.dart';
import 'modules/home/widgets/profile/health_check/HealthSurveyPage.dart';
import 'modules/home/widgets/sleep_track/controller/sleep_controller.dart'; // contains initHealthFlow()

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  Get.put(SleepController());
  await GetStorage.init();

  initHealthFlow();
  FirebaseAuth.instance.setLanguageCode('en');

  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.debug,
    appleProvider: AppleProvider.debug,
  );

  if (!kReleaseMode) {
    debugPrint("🛡️ App Check debug provider active (debug).");
  }

  // ✅ ADD THIS: Initialize auth repo before running app
  final authRepo = Get.put(AuthenticationRepository(), permanent: true);
  await authRepo.init(); // Only init storage, don't navigate yet

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(const MyApp());
}