import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../data/repositories/authentication/authentication_repository.dart';
import '../../../utils/constants/animation_strings.dart';
import '../../../utils/constants/image_strings.dart';
import '../controllers/verify_email_controller.dart';

class VerifyMail extends StatelessWidget {
  const VerifyMail({super.key, required this.email});

  final String? email;

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(VerifyEmailController());
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          onPressed: () => AuthenticationRepository.instance.logOut(),
          icon: const Icon(CupertinoIcons.clear),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              /// Image
              SvgPicture.asset(height: MediaQuery.of(context).size.height*0.3,ImageStrings.verifyEmail),
              const SizedBox(height: 15),

              /// Title and Subtitle
              Text(
                'Verify Your Email Address!',
                style: GoogleFonts.poppins(
                    fontSize: 24, fontWeight: FontWeight.w600),
              ),

              const SizedBox(height: 10),
              Text(
                'Your account has been created successfully. Please verify your email to proceed ahead.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(),
              ),

              const SizedBox(height: 25),

              /// Email Display
              Column(
                children: [
                  Text('Mail has been sent to', style: GoogleFonts.poppins()),
                  Text(
                    '$email',
                    style: GoogleFonts.poppins(
                        color: Colors.blue, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'If you don’t see the email, please check your spam or junk folder.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: Colors.red.shade700),
                  ),
                ],
              ),

              const SizedBox(height: 30),

              /// Resend Button
              TextButton(
                onPressed: () => controller.sendEmailVerification(),
                child: Text(
                  'Resend Email',
                  style: GoogleFonts.poppins(color: Colors.grey.shade600),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
