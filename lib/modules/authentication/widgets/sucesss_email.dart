import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import '../views/loginPage.dart';

class SucesssEmail extends StatelessWidget {
  const SucesssEmail({super.key, required this.image, required this.title, required this.subTitle, required this.onPressed});

  final String image, title, subTitle;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          onPressed: () => Get.offAll(() => const LoginPage()),
          icon: const Icon(CupertinoIcons.clear),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center, // Centers vertically
            crossAxisAlignment: CrossAxisAlignment.center, // Centers horizontally
            children: [
              /// Image
              Lottie.asset('assets/animations/successfully_registered.json'),

              /// Title and Subtitle
              Text(
                'Your email has been verified successfully!',
                style: GoogleFonts.poppins(
                    fontSize: 24, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: MediaQuery.of(context).size.height*0.1),

              /// Button
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.pink.shade300, // pastel pink
            ),
            onPressed: () {
             Get.to(() => LoginPage());
            },
            child: const Text("Proceed Ahead!"),
          ),
            ],
          ),
        ),
      ),
    );
  }
}
