import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../authentication/views/signUpPage.dart';
import '../../../data/repositories/authentication/authentication_repository.dart';

class OnboardingController extends GetxController {
  static OnboardingController get instance => Get.find();

  // Variables
  final pageController = PageController();
  Rx<int> currentPageIndex = 0.obs;

  // Update the Variables
  void upDatePageIndicator(index) => currentPageIndex.value = index;

  void dotNavigationClick(index) {
    currentPageIndex.value = index;
    pageController.jumpToPage(index);
  }

  // Go to the next page or SignUp
  void nextPage() async {
    if (currentPageIndex.value == 2) {
      // ✅ Mark onboarding complete
      AuthenticationRepository.instance.completeOnboarding();

      // ✅ Navigate to SignUpPage
      Get.off(() => const SignUpPage());
    } else {
      int page = currentPageIndex.value + 1;
      pageController.jumpToPage(page);
    }
  }

  // Skip the onboarding and go directly to SignUp
  void skipPage() async {
    // ✅ Mark onboarding complete
    AuthenticationRepository.instance.completeOnboarding();

    // ✅ Navigate to SignUpPage
    Get.off(() => const SignUpPage());
  }
}
