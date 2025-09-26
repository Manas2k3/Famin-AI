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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await GetStorage.init();

  // optional: load .env if present (wrap in try/catch so missing file won't crash)
  try {
    await dotenv.load(fileName: ".env");
  } catch (_) {
    debugPrint('No .env file found or failed to load. Continuing without it.');
  }

  FirebaseAuth.instance.setLanguageCode('en');

  await FirebaseAppCheck.instance.activate(
    androidProvider: kReleaseMode ? AndroidProvider.playIntegrity : AndroidProvider.debug,
  );

  if (!kReleaseMode) {
    debugPrint("🛡️ App Check debug provider active (debug).");
  }

  // Register repository now, but DO NOT start navigation/listener here
  Get.put(AuthenticationRepository(), permanent: true);

  runApp(const MyApp());
}
