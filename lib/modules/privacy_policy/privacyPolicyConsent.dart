import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import '../../data/repositories/authentication/authentication_repository.dart';
import '../onboarding/onboarding.dart';
import 'PrivacyPolicyPage.dart';

class PrivacyConsentPage extends StatefulWidget {
  const PrivacyConsentPage({super.key});

  @override
  State<PrivacyConsentPage> createState() => _PrivacyConsentPageState();
}

class _PrivacyConsentPageState extends State<PrivacyConsentPage> {
  bool agreePolicy = false;
  bool agreeHealthData = false;
  bool agreeEmails = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const Text(
                "Privacy first",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 24),

              _buildCheckTile(
                value: agreePolicy,
                text: RichText(
                  text: TextSpan(
                    style: const TextStyle(color: Colors.black87),
                    children: [
                      const TextSpan(text: "I agree to "),
                      WidgetSpan(
                        child: GestureDetector(
                          onTap: () => Get.to(() => PrivacyPolicyPage()),
                          child: Text(
                            "Privacy Policy",
                            style: TextStyle(
                              color: Colors.pink.shade400,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                      const TextSpan(text: " and "),
                      WidgetSpan(
                        child: GestureDetector(
                          onTap: () {},
                          child: Text(
                            "Terms of Use",
                            style: TextStyle(
                              color: Colors.pink.shade400,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                      const TextSpan(text: "."),
                    ],
                  ),
                ),
                onChanged: (v) => setState(() => agreePolicy = v ?? false),
              ),
              const SizedBox(height: 12),

              _buildCheckTile(
                value: agreeHealthData,
                text: RichText(
                  text: TextSpan(
                    style: const TextStyle(color: Colors.black87),
                    children: [
                      const TextSpan(
                        text:
                        "I agree to processing of my personal health data for providing app functions. See more in ",
                      ),
                      WidgetSpan(
                        child: GestureDetector(
                          onTap: () => Get.to(() => PrivacyPolicyPage()),
                          child: Text(
                            "Privacy Policy",
                            style: TextStyle(
                              color: Colors.pink.shade400,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                      const TextSpan(text: "."),
                    ],
                  ),
                ),
                onChanged: (v) => setState(() => agreeHealthData = v ?? false),
              ),
              const SizedBox(height: 12),

              _buildCheckTile(
                value: agreeEmails,
                text: const Text(
                  "I agree that the app may use my personal data (except health data) to send me product or service offerings via email.",
                ),
                onChanged: (v) => setState(() => agreeEmails = v ?? false),
              ),
              SizedBox(height: MediaQuery.of(context).size.height*0.42,),

              // Buttons section
              SizedBox(
                width: double.infinity,
                child: Column(
                  children: [
                    TextButton(
                      onPressed: () {
                        setState(() {
                          agreePolicy = true;
                          agreeHealthData = true;
                          agreeEmails = true;
                        });
                      },
                      child: const Text(
                        "Select All",
                        style: TextStyle(color: Colors.black),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: (agreePolicy && agreeHealthData)
                          ? () {
                        AuthenticationRepository.instance
                            .completeConsent();
                        Get.to(() => const OnboardingPage());
                      }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.pink.shade400,
                        disabledBackgroundColor: Colors.pink.shade200,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: const Text(
                        "Next",
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckTile({
    required bool value,
    required Widget text,
    required ValueChanged<bool?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: Checkbox(
              checkColor: Colors.white,
              value: value,
              onChanged: onChanged,
              activeColor: Colors.pink.shade400,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: text),
        ],
      ),
    );
  }
}
