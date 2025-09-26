import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AnimationLoader extends StatelessWidget {
  final String text;
  final String animation; // you can pass ImageStrings.loadingImage here
  final ValueListenable<String>? listenableText;

  const AnimationLoader({
    Key? key,
    required this.text,
    required this.animation,
    this.listenableText,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final textWidget = listenableText != null
        ? ValueListenableBuilder<String>(
      valueListenable: listenableText!,
      builder: (context, value, _) => Text(
        value,
        style: GoogleFonts.poppins(
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        textAlign: TextAlign.center,
      ),
    )
        : Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      textAlign: TextAlign.center,
    );

    return Center(
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),

            /// ✅ Static loading image (SVG)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SvgPicture.asset(
                animation, // pass ImageStrings.loadingImage
                width: 200,
                height: 200,
              ),
            ),

            SizedBox(height: MediaQuery.of(context).size.height * 0.2),

            textWidget,

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
