import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';

import '../../../common/components/custom_button.dart';
import '../../../utils/constants/image_strings.dart';
import '../controllers/forget_password_controller.dart';
import '../views/loginPage.dart';

class ResetPassword extends StatelessWidget {
  final String email;
  const ResetPassword({super.key, required this.email});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Get.offAll(() => const LoginPage()),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(25),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center, // Center the column
            children: [
              /// Image at the to
              Center(
                child: Image.asset(
                  ImageStrings.mailSent,
                  height: 150, // Set an appropriate height for image
                ),
              ),
              const SizedBox(height: 25),

              /// Heading
              Text(
                'Password Reset Email Sent!',
                style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),

              /// Subtitle
              Text(
                "We've sent you a secure link to safely change your password and keep your account protected.",
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(color: Colors.grey.shade600),
              ),

              SizedBox(height: 15,),

              Column(
                children: [
                  Text('Recovery Mail has been sent to', style: GoogleFonts.poppins(fontSize: 18),),
                  Text('$email', style: GoogleFonts.poppins(color: Colors.blue, fontSize: 16),)
                ],
              ),

              const SizedBox(height: 25),

              /// Done Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40.0),
                child: CustomButton(
                  initialColor: Colors.redAccent, pressedColor: Colors.redAccent.shade100,
                  buttonText: "Done",
                  onTap: () => Get.offAll(() => const LoginPage()),
                ),
              ),
              const SizedBox(height: 15),

              /// Resend Email Option
              TextButton(
                onPressed: () => ForgetPasswordController.instance.resendPasswordResetMail,
                child: Text(
                  "Resend Email",
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
