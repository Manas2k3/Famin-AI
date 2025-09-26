import 'package:flutter/material.dart';

final ThemeData feminineHealthTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  fontFamily: 'Poppins',

  primaryColor: const Color(0xFFFADADD),
  scaffoldBackgroundColor: Colors.white,

  colorScheme: const ColorScheme.light(
    primary: Color(0xFFFADADD),
    onPrimary: Color(0xFF6D6875),
    secondary: Color(0xFFE6E6FA),
    onSecondary: Color(0xFF6D6875),
    error: Color(0xFFE57373),
    onError: Colors.white,
    background: Colors.white,
    onBackground: Color(0xFF333333),
    surface: Colors.white,
    onSurface: Color(0xFF333333),
  ),

  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFFFADADD),
    foregroundColor: Color(0xFF6D6875),
    elevation: 0,
    centerTitle: true,
    titleTextStyle: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.bold,
      color: Color(0xFF6D6875),
    ),
  ),

  textTheme: const TextTheme(
    displayLarge: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.bold,
      color: Color(0xFF333333),
    ),
    displayMedium: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      color: Color(0xFF333333),
    ),
    bodyLarge: TextStyle(
      fontSize: 16,
      color: Color(0xFF6D6875),
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      color: Color(0xFF6D6875),
    ),
    labelLarge: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    ),
  ),

  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.pink.shade300,
      foregroundColor: Colors.white,
      minimumSize: const Size(double.infinity, 50),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      textStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),

  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Color(0xFFFADADD),
    contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
    hintStyle: const TextStyle(color: Color(0xFF6D6875)),
  ),

  cardTheme: CardThemeData(
    color: Color(0xFFFEF6F7).withOpacity(0.3),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
    ),
    elevation: 1,
    margin: const EdgeInsets.all(8),
  ),
);
