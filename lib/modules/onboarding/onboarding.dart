
import 'package:famina/modules/onboarding/widgets/onBoardingNavigation.dart';
import 'package:famina/modules/onboarding/widgets/onboarding_circular_button.dart';
import 'package:famina/modules/onboarding/widgets/onboarding_page.dart';
import 'package:famina/modules/onboarding/widgets/onboarding_skip.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../utils/constants/image_strings.dart';
import '../../utils/constants/text_strings.dart';
import 'controller/onboarding_controller.dart';

class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(OnboardingController());

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          PageView(
            controller: controller.pageController,
            onPageChanged: controller.upDatePageIndicator,
            children: [
              OnBoardingPage(
                image: ImageStrings.onBoardingImage1,
                title: TextStrings.onBoardingTitle1,
                subTitle: TextStrings.onBoardingSubTitle1,
              ),
              OnBoardingPage(
                image: ImageStrings.onBoardingImage2,
                title: TextStrings.onBoardingTitle2,
                subTitle: TextStrings.onBoardingSubTitle2,
              ),
              OnBoardingPage(
                image: ImageStrings.onBoardingImage3,
                title: TextStrings.onBoardingTitle3,
                subTitle: TextStrings.onBoardingSubTitle3,
              ),
            ],
          ),
          // Skip Button
          OnBoardingSkip(),

          // Dot Navigation SmoothPageIndicator
          OnBoardingNavigation(),

          // Circular Button
          OnBoardingCircularButton()
        ],
      ),
    );
  }
}
