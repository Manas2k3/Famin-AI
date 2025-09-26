import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.pink.shade300,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () {
            Get.back();
          },
          icon: Icon(Icons.arrow_back, color: Colors.white),
        ),
        automaticallyImplyLeading: false,
        title: const Text(
          "Privacy Policy",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        centerTitle: true,
        backgroundColor: Colors.pink.shade300,
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  "Privacy Policy",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.pink,
                  ),
                ),
                SizedBox(height: 16),

                Text(
                  "Last updated: September 2025\n",
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),

                Text(
                  "We respect your privacy. This Privacy Policy explains how our menstrual health application collects, uses, and protects your data. By using our app, you agree to the practices described below.\n",
                ),

                Text(
                  "1. Information We Collect",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.pink,
                  ),
                ),
                Text(
                  "• Personal Information: name, email, and account details.\n"
                  "• Health Data: menstrual cycle logs, symptoms, and images you upload for analysis.\n"
                  "• Technical Data: device information, app version, and crash reports.\n\n",
                ),

                Text(
                  "2. How We Use Your Information",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.pink,
                  ),
                ),
                Text(
                  "• To provide personalized cycle tracking and health insights.\n"
                  "• To analyze uploaded images using our machine learning model.\n"
                  "• To improve app performance and features.\n"
                  "• To send account-related notifications such as verification emails.\n\n",
                ),

                Text(
                  "3. Data Storage and Security",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.pink,
                  ),
                ),
                Text(
                  "• Your data may be stored securely in Firebase Authentication and Firestore.\n"
                  "• Uploaded images may be processed locally or via secure cloud servers.\n"
                  "• We implement encryption and strict access controls to safeguard your data.\n\n",
                ),

                Text(
                  "4. Third-Party Services",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.pink,
                  ),
                ),
                Text(
                  "We rely on trusted third-party services such as Firebase (Auth, Firestore, Analytics, App Check). These services may process limited technical data as part of providing functionality.\n\n",
                ),

                Text(
                  "5. Data Sharing",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.pink,
                  ),
                ),
                Text(
                  "We do not sell, trade, or rent your personal data. Data may only be shared if legally required.\n\n",
                ),

                Text(
                  "6. User Rights",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.pink,
                  ),
                ),
                Text(
                  "You have the right to access, update, or delete your data. You may also request deletion of your account and all associated data by contacting us.\n\n",
                ),

                Text(
                  "7. Children’s Privacy",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.pink,
                  ),
                ),
                Text(
                  "Our app is intended for users above 13 years. We do not knowingly collect data from children under this age.\n\n",
                ),

                Text(
                  "8. Changes to This Policy",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.pink,
                  ),
                ),
                Text(
                  "We may update this Privacy Policy from time to time. Any changes will be reflected in the app and communicated where appropriate.\n\n",
                ),

                Text(
                  "9. Contact Us",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.pink,
                  ),
                ),
                Text(
                  "If you have questions about this Privacy Policy, please contact us at: support@famina.ai\n",
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
