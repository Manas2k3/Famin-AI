import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../controller/onboarding_controller.dart';

class OnBoardingSkip extends StatelessWidget {
  const OnBoardingSkip({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: kToolbarHeight,
      right: 25,
      child: TextButton(
        onPressed: () => OnboardingController.instance.skipPage(),
        child: Text(
          'Skip',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurface, // muted grey
          ),
        ),
      ),
    );
  }
}

