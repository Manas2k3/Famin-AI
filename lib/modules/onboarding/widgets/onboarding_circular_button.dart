import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../controller/onboarding_controller.dart';

class OnBoardingCircularButton extends StatelessWidget {
  const OnBoardingCircularButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 25,
      bottom: 45,
      child: ElevatedButton(
        onPressed: () => OnboardingController.instance.nextPage(),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.pink.shade300,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          minimumSize: const Size(60, 60),
          shape: const CircleBorder(),
        ),
        child: Icon(
          Iconsax.arrow_right_3,
          color: Colors.white, // icon stands out
        ),
      ),
    );
  }
}