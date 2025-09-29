import 'package:get/get_navigation/src/root/get_material_app.dart';
import 'package:flutter/material.dart';
import 'package:get/get_navigation/src/routes/get_route.dart';
import 'data/theme/themedata.dart';
import 'modules/authentication/views/height_page.dart';
import 'modules/authentication/views/loginPage.dart';
import 'modules/authentication/views/weight_page.dart';
import 'modules/home/views/home_page.dart';
import 'modules/splash/splash_screen.dart';
import 'navigation_menu.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'FlowSense',
      debugShowCheckedModeBanner: false,
      theme: feminineHealthTheme,

      initialRoute: '/',  // ✅ Use this instead of home

      getPages: [
        GetPage(name: '/', page: () => const SplashScreen()),
        GetPage(name: '/login', page: () => const LoginPage()),
        GetPage(name: '/home', page: () => HomePage()),
        GetPage(name: '/height', page: () => const HeightPage()),
        GetPage(name: '/weight', page: () => const WeightPage()),
        GetPage(name: '/navigation', page: () => NavigationMenu()),
      ],
    );
  }
}