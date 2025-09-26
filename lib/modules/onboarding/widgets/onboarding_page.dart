import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart'; // 👈 import this

class OnBoardingPage extends StatelessWidget {
  const OnBoardingPage({
    super.key,
    required this.image,
    required this.title,
    required this.subTitle,
  });

  final String image, title, subTitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          // 👇 Replace Image with SvgPicture
          SvgPicture.asset(
            image,
            width: MediaQuery.of(Get.context!).size.width * 0.8,
            height: MediaQuery.of(Get.context!).size.height * 0.6,
            fit: BoxFit.contain,
          ),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Text(
            subTitle,
            style: GoogleFonts.poppins(fontSize: 16),
            textAlign: TextAlign.center,
          )
        ],
      ),
    );
  }
}
