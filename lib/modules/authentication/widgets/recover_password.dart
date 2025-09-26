import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';

import '../../../common/components/custom_button.dart';
import '../controllers/forget_password_controller.dart';
import '../views/loginPage.dart';


class RecoverPassword extends StatelessWidget {
  const RecoverPassword({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(ForgetPasswordController());
    return Scaffold(
      appBar: AppBar(title:  /// Heading
      Text(
        'Recover your password',
        style: GoogleFonts.poppins(
          fontSize: 20,
          fontWeight: FontWeight.w600, // Added proper styling
        ),
      ),
        backgroundColor: Colors.white,
        leading: IconButton(
          onPressed: () => Get.offAll(() => const LoginPage()),
          icon: const Icon(Icons.arrow_back), // Use back arrow
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            SizedBox(
              height: 5,
            ),
            Text(
              "Don't worry we've got your back, enter your email and we will send you a password reset link",
              textAlign: TextAlign.start,
              style: GoogleFonts.poppins(color: Colors.grey.shade600),
            ),

            SizedBox(height: 25),

            Form(
              key: controller.forgetPasswordFormKey,
              child: Theme(
                data: Theme.of(context).copyWith(
                  textSelectionTheme: const TextSelectionThemeData(
                    selectionHandleColor: Colors.redAccent, // 👈 Change this to your desired color
                  ),
                ),
                child: TextFormField(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: controller.email,
                  decoration: InputDecoration(
                    floatingLabelStyle: TextStyle(color: Colors.grey.shade700),
                    labelText: "Enter your email", labelStyle: GoogleFonts.poppins(
                    color: Colors.grey.shade700, fontWeight: FontWeight.bold
                  ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.black)
                    ),
                    prefixIcon: Icon(Iconsax.direct_right),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)
                    )
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Email is required';
                    final emailReg = RegExp(r"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$");
                    if (!emailReg.hasMatch(v.trim())) return 'Enter a valid email';
                    return null;
                  },
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(40.0),
              child: ElevatedButton(
                onPressed: () {
                  Get.to(ForgetPasswordController.instance.sendPasswordResetMail(context));
                },
                child: const Text("Log in"),
              ),
            )
            // You can add further widgets for email input, recovery steps, etc.
          ],
        ),
      ),
    );
  }
}
