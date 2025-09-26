// splash_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../data/repositories/authentication/authentication_repository.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {

  late final AnimationController _logoCtrl;
  late final AnimationController _taglineCtrl;
  late final AnimationController _bgCtrl;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _taglineOpacity;
  late final Animation<Offset> _taglineOffset;

  Timer? _startTimer;

  // Palette
  static const Color kPrimaryRed = Color(0xFFE50914);
  static const Color kCoral = Color(0xFFFF6B81);
  static const Color kWhite = Colors.white;

  @override
  void initState() {
    super.initState();

    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);

    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();

    _logoScale = CurvedAnimation(
      parent: _logoCtrl,
      curve: Curves.elasticOut,
    );

    _logoOpacity = CurvedAnimation(
      parent: _logoCtrl,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );

    _taglineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _taglineCtrl.forward();
    });

    _taglineOpacity = CurvedAnimation(
      parent: _taglineCtrl,
      curve: Curves.easeOut,
    );

    _taglineOffset = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _taglineCtrl,
      curve: Curves.easeOutCubic,
    ));

    // After the splash animation delay, initialize repository and redirect
    _startTimer = Timer(const Duration(milliseconds: 2400), () {
      if (!mounted) return;
      // init repository and perform redirect now that GetMaterialApp is running
      AuthenticationRepository.instance.initAndRedirect();
    });
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    _bgCtrl.dispose();
    _logoCtrl.dispose();
    _taglineCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        body: AnimatedBuilder(
          animation: _bgCtrl,
          builder: (context, _) {
            final t = _bgCtrl.value;
            final align1 = Alignment.lerp(
              const Alignment(-0.8, -0.9),
              const Alignment(0.8, 0.9),
              t,
            )!;
            final align2 = Alignment.lerp(
              const Alignment(0.8, 0.9),
              const Alignment(-0.8, -0.9),
              t,
            )!;

            final colorA = Color.lerp(kPrimaryRed, kCoral, t)!;
            final colorB = Color.lerp(Colors.red.shade300, kPrimaryRed, t * 0.6)!;

            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: align1,
                  end: align2,
                  colors: [colorA, colorB, kWhite],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // App Name
                          ScaleTransition(
                            scale: _logoScale.drive(Tween(begin: 0.92, end: 1.0)),
                            child: FadeTransition(
                              opacity: _logoOpacity,
                              child: Text(
                                "Famin AI",
                                textAlign: TextAlign.center,
                                style: textTheme.displaySmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Opacity(
                            opacity: 0.25,
                            child: Container(
                              height: 1.2,
                              width: 120,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Tagline
                          FadeTransition(
                            opacity: _taglineOpacity,
                            child: SlideTransition(
                              position: _taglineOffset,
                              child: Text(
                                "Comfort. Confidence. Care.",
                                textAlign: TextAlign.center,
                                style: textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                  color: const Color(0xFF1A1A1A),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
