import 'package:flutter/material.dart';
import 'package:get/get.dart';
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
    final size = MediaQuery.sizeOf(context);
    final isTablet = size.width >= 600;
    final double horizontal = isTablet ? 32.0 : 20.0;

    // Height of the fixed bottom area (approximate, keep in sync with bottomSheet).
    const double kButtonSheetHeight = 110;

    return Scaffold(
      backgroundColor: Colors.white,

      // CONTENT — scrolls, with extra bottom padding so it never hides behind the sheet.
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(horizontal, 20, horizontal, kButtonSheetHeight + 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Text(
                "Privacy first",
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 24),

              _buildCheckTile(
                value: agreePolicy,
                text: RichText(
                  text: TextSpan(
                    style: const TextStyle(color: Colors.black87, height: 1.35),
                    children: [
                      const TextSpan(text: "I agree to "),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: InkWell(
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
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: InkWell(
                          onTap: () {
                            // TODO: Navigate to Terms page
                          },
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
                    style: const TextStyle(color: Colors.black87, height: 1.35),
                    children: [
                      const TextSpan(
                        text:
                        "I agree to processing of my personal health data for providing app functions. See more in ",
                      ),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: InkWell(
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
                  style: TextStyle(height: 1.35),
                ),
                onChanged: (v) => setState(() => agreeEmails = v ?? false),
              ),
            ],
          ),
        ),
      ),

      // FIXED BOTTOM — always same position across devices.
      bottomSheet: SafeArea(
        top: false,
        child: Material(
          elevation: 12,
          color: Colors.white,
          child: Padding(
            padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () {
                        setState(() {
                          final all = !(agreePolicy && agreeHealthData && agreeEmails);
                          agreePolicy = all;
                          agreeHealthData = all;
                          agreeEmails = all;
                        });
                      },
                      child: const Text("Select All", style: TextStyle(color: Colors.black)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (agreePolicy && agreeHealthData)
                          ? () {
                        AuthenticationRepository.instance.completeConsent();
                        Get.to(() => const OnboardingPage());
                      }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.pink.shade400,
                        disabledBackgroundColor: Colors.pink.shade200,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text("Next", style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
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
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox.adaptive(
              checkColor: Colors.white,
              value: value,
              onChanged: onChanged,
              activeColor: Colors.pink.shade400,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 8),
            Expanded(child: text),
          ],
        ),
      ),
    );
  }
}
