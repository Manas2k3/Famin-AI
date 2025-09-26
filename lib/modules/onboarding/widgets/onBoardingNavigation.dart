import 'package:flutter/material.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../controller/onboarding_controller.dart';

class OnBoardingNavigation extends StatelessWidget {
  const OnBoardingNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = OnboardingController.instance;
    return Positioned(
      bottom: kBottomNavigationBarHeight + 5,
      left: 25,
      child: SmoothPageIndicator(
        controller: controller.pageController,
        onDotClicked: controller.dotNavigationClick,
        count: 3,
        effect: ExpandingDotsEffect(
          activeDotColor: Colors.pink.shade300, // lavender/purple
          dotColor: Theme.of(context).colorScheme.secondary.withOpacity(0.4),
          dotHeight: 6,
        ),
      ),
    );
  }
}
