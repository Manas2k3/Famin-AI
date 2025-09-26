import 'package:famina/modules/authentication/views/signUpPage.dart';
import 'package:famina/modules/authentication/widgets/recover_password.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../utils/constants/image_strings.dart';
import '../controllers/login_controller.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  InputDecoration _fieldDecoration(BuildContext context, String label, {Widget? suffix}) {
    return InputDecoration(
      floatingLabelBehavior: FloatingLabelBehavior.never,
      labelText: label,
      suffixIcon: suffix,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(LoginController());

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        title: const Text("Log in"),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Form(
                  key: controller.loginFormKey,
                  autovalidateMode: AutovalidateMode.disabled,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Illustration
                      SizedBox(
                        height: 180,
                        child: SvgPicture.asset(ImageStrings.loginPage),
                      ),
                      const SizedBox(height: 24),

                      TextFormField(
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        cursorColor: Colors.black54,
                        controller: controller.emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: _fieldDecoration(context, "Email"),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Email is required';
                          final emailReg = RegExp(r"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$");
                          if (!emailReg.hasMatch(v.trim())) return 'Please enter a valid email';
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      Obx(() => TextFormField(
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        cursorColor: Colors.black54,
                        controller: controller.passwordController,
                        obscureText: controller.hidePassword.value,
                        textInputAction: TextInputAction.done,
                        decoration: _fieldDecoration(
                          context,
                          "Password",
                          suffix: IconButton(
                            onPressed: () => controller.hidePassword.value =
                            !controller.hidePassword.value,
                            icon: Icon(
                              controller.hidePassword.value
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Password is required';
                          if (v.length < 8) return 'Must be at least 8 characters';
                          return null;
                        },
                        onFieldSubmitted: (_) {
                          if (controller.loginFormKey.currentState?.validate() ?? false) {
                            controller.loginWithEmail(context);
                          }
                        },
                      )),
                      const SizedBox(height: 20),

                      // Log In Button
                      ElevatedButton(
                        onPressed: () {
                          if (controller.loginFormKey.currentState?.validate() ?? false) {
                            controller.loginWithEmail(context);
                          }
                        },
                        child: const Text("Log in"),
                      ),

                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Get.to(RecoverPassword()),
                          child: const Text("Forgot Password?", style: TextStyle(color: Colors.black),),
                        ),
                      ),

                      const SizedBox(height: 24),
                      Center(
                        child: TextButton(
                          onPressed: () => Get.off(SignUpPage()),
                          child: const Text(
                            "Don’t have an account? Create one",
                            style: TextStyle(color: Colors.black,decoration: TextDecoration.underline),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
