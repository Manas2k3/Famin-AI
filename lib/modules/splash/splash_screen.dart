// lib/features/splash/splash_screen.dart
import 'dart:async';
import 'dart:math' as math;
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
  late final AnimationController _bgCtrl;       // background rotation + bokeh drift
  late final AnimationController _logoCtrl;     // logo entrance + glow pulse
  late final AnimationController _taglineCtrl;  // tagline slide/fade

  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _glowPulse;
  late final Animation<double> _shimmerPhase;
  late final Animation<Offset> _taglineOffset;
  late final Animation<double> _taglineOpacity;

  Timer? _startTimer;

  // Palette
  static const Color kPrimaryPink = Colors.pinkAccent;
  static const Color kCoral = Color(0xFFFF6B81);
  static const Color kInk = Color(0xFF121212);
  static const Color kWhite = Colors.white;

  @override
  void initState() {
    super.initState();

    // Slow, continuous motion for background & bokeh
    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    // Snappy but premium entrance for the logo
    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();

    _logoScale = CurvedAnimation(
      parent: _logoCtrl,
      curve: const Interval(0.0, 1.0, curve: Curves.elasticOut),
    ).drive(Tween(begin: 0.92, end: 1.0));

    _logoOpacity = CurvedAnimation(
      parent: _logoCtrl,
      curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
    );

    // very subtle glow pulse tied to the last half of the logo anim
    _glowPulse = CurvedAnimation(
      parent: _logoCtrl,
      curve: const Interval(0.45, 1.0, curve: Curves.easeInOut),
    );

    // shimmer phase for the divider
    _shimmerPhase = Tween<double>(begin: -1.0, end: 2.0)
        .animate(CurvedAnimation(parent: _bgCtrl, curve: Curves.linear));

    // Tagline comes after a tiny pause
    _taglineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    Future.delayed(const Duration(milliseconds: 450), () {
      if (mounted) _taglineCtrl.forward();
    });

    _taglineOpacity = CurvedAnimation(
      parent: _taglineCtrl,
      curve: Curves.easeOut,
    );

    _taglineOffset = Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _taglineCtrl,
      curve: Curves.easeOutCubic,
    ));

    // Keep your redirect timing
    bool _kickedOff = false;

    _startTimer = Timer(const Duration(milliseconds: 2400), () {
      if (!mounted || _kickedOff) return;
      _kickedOff = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        AuthenticationRepository.instance.initAndRedirect();
      });
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
          animation: Listenable.merge([_bgCtrl, _logoCtrl, _taglineCtrl]),
          builder: (context, _) {
            final t = _bgCtrl.value;

            return Container(
              decoration: BoxDecoration(
                // Rotating sweep + blended radial to feel alive
                gradient: SweepGradient(
                  center: FractionalOffset(0.4 + 0.2 * math.sin(2 * math.pi * t), 0.6),
                  startAngle: 0,
                  endAngle: 2 * math.pi,
                  colors: [
                    kInk,
                    Color.lerp(kPrimaryPink, kCoral, 0.35)!,
                    kInk,
                    Color.lerp(kPrimaryPink, Colors.red.shade300, 0.25)!,
                    kInk,
                  ],
                  stops: const [0.00, 0.22, 0.50, 0.78, 1.0],
                  transform: GradientRotation(2 * math.pi * t),
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Soft radial overlay to make center pop
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0.0, -0.1),
                        radius: 1.1,
                        colors: [
                          Colors.white.withOpacity(0.10),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 1.0],
                      ),
                    ),
                  ),

                  // Floating bokeh orbs (pure paint, tied to _bgCtrl)
                  CustomPaint(
                    painter: _BokehPainter(progress: t),
                  ),

                  SafeArea(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Logo: spring-in + glow pulse
                              ScaleTransition(
                                scale: _logoScale,
                                child: FadeTransition(
                                  opacity: _logoOpacity,
                                  child: _GlowingText(
                                    "Famin AI",
                                    baseStyle: textTheme.displaySmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.6,
                                      color: kWhite,
                                    ),
                                    // Glow expands & fades with the pulse
                                    glowStrength: Tween<double>(begin: 0, end: 1.0)
                                        .evaluate(_glowPulse),
                                    glowColor: Color.lerp(
                                      kPrimaryPink,
                                      kCoral,
                                      0.5 + 0.5 * math.sin(2 * math.pi * _bgCtrl.value),
                                    )!,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 14),

                              // Shimmer divider (no packages)
                              _ShimmerDivider(phase: _shimmerPhase.value),

                              const SizedBox(height: 18),

                              // Tagline: gentle rise + fade
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
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// ----- Shimmer divider -------------------------------------------------------
class _ShimmerDivider extends StatelessWidget {
  const _ShimmerDivider({required this.phase});
  final double phase;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 2,
        width: 140,
        child: CustomPaint(
          painter: _ShimmerPainter(phase: phase),
        ),
      ),
    );
  }
}

class _ShimmerPainter extends CustomPainter {
  _ShimmerPainter({required this.phase});
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.black.withOpacity(0.18),
          Colors.black.withOpacity(0.24),
        ],
      ).createShader(Offset.zero & size);

    final shimmer = Paint()
      ..blendMode = BlendMode.plus
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.white.withOpacity(0.0),
          Colors.white.withOpacity(0.65),
          Colors.white.withOpacity(0.0),
        ],
        stops: const [0.35, 0.5, 0.65],
        // Move the gradient by translating its rect with phase
      ).createShader(Rect.fromLTWH(size.width * phase, 0, size.width, size.height));

    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(999));
    canvas.drawRRect(r, base);
    canvas.drawRRect(r, shimmer);
  }

  @override
  bool shouldRepaint(covariant _ShimmerPainter oldDelegate) =>
      oldDelegate.phase != phase;
}

/// ----- Glowing Text (soft shadow pulse) -------------------------------------
class _GlowingText extends StatelessWidget {
  const _GlowingText(
      this.text, {
        required this.baseStyle,
        required this.glowStrength,
        required this.glowColor,
      });

  final String text;
  final TextStyle? baseStyle;
  final double glowStrength; // 0..1
  final Color glowColor;

  @override
  Widget build(BuildContext context) {
    final s = (glowStrength * 14) + 4; // blur radius
    final o = (0.35 + 0.35 * glowStrength).clamp(0.0, 1.0); // opacity
    return Text(
      text,
      textAlign: TextAlign.center,
      style: baseStyle?.copyWith(
        shadows: [
          Shadow(
            color: glowColor.withOpacity(o as double),
            blurRadius: s,
            offset: const Offset(0, 0),
          ),
        ],
      ),
    );
  }
}

/// ----- Bokeh painter (drifting soft circles) --------------------------------
class _BokehPainter extends CustomPainter {
  _BokehPainter({required this.progress});
  final double progress;

  final List<_Blob> _blobs = const [
    _Blob(0.15, 0.25, 120, 0.8),
    _Blob(0.82, 0.20, 140, 0.65),
    _Blob(0.25, 0.78, 180, 0.55),
    _Blob(0.78, 0.72, 130, 0.50),
    _Blob(0.50, 0.48, 220, 0.40),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < _blobs.length; i++) {
      final b = _blobs[i];
      final p = progress + i * 0.17;

      // subtle circular drift path
      final dx = b.dx * size.width +
          math.sin(2 * math.pi * (p + b.dx)) * 18.0;
      final dy = b.dy * size.height +
          math.cos(2 * math.pi * (p + b.dy)) * 18.0;

      final r = b.radius * (0.9 + 0.1 * math.sin(2 * math.pi * p));

      final paint = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24)
        ..color = Color.lerp(
          const Color(0x66FFFFFF),
          const Color(0x22FFFFFF),
          0.5 + 0.5 * math.sin(2 * math.pi * p),
        )!;

      canvas.drawCircle(Offset(dx, dy), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BokehPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _Blob {
  final double dx;
  final double dy;
  final double radius;
  final double opacity;
  const _Blob(this.dx, this.dy, this.radius, this.opacity);
}
