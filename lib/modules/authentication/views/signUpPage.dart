import 'package:famina/modules/authentication/views/loginPage.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../utils/constants/image_strings.dart';
import '../controllers/signupController.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _allValid = false.obs;
  late final SignUpController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(SignUpController());

    // Add listeners to update _allValid when inputs change
    controller.firstName.addListener(_validateInputs);
    controller.lastName.addListener(_validateInputs);
    controller.email.addListener(_validateInputs);
    controller.password.addListener(_validateInputs);

    // initial validation
    WidgetsBinding.instance.addPostFrameCallback((_) => _validateInputs());
  }

  @override
  void dispose() {
    // remove listeners so no leaks (controller might be kept by GetX; don't dispose controller here)
    controller.firstName.removeListener(_validateInputs);
    controller.lastName.removeListener(_validateInputs);
    controller.email.removeListener(_validateInputs);
    controller.password.removeListener(_validateInputs);
    super.dispose();
  }

  void _validateInputs() {
    final fn = controller.firstName.text.trim();
    final ln = controller.lastName.text.trim();
    final em = controller.email.text.trim();
    final pw = controller.password.text;

    final emailReg = RegExp(r"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$");

    final allFilled = fn.isNotEmpty && ln.isNotEmpty && em.isNotEmpty && pw.isNotEmpty;
    final emailValid = emailReg.hasMatch(em);
    final passwordValid = pw.length >= 8;

    _allValid.value = allFilled && emailValid && passwordValid;
  }

  InputDecoration _fieldDecoration(BuildContext context, String label, {Widget? suffix}) {
    return InputDecoration(
      floatingLabelBehavior: FloatingLabelBehavior.never,
      labelText: label,
      suffixIcon: suffix,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        title: Text("Sign Up"),
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
                  key: controller.signUpFormKey,
                  autovalidateMode: AutovalidateMode.disabled,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 180,
                        child: SvgPicture.asset(ImageStrings.signUpPage),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        cursorColor: Colors.black54,
                        controller: controller.firstName,
                        textInputAction: TextInputAction.next,
                        decoration: _fieldDecoration(context, "First Name"),
                        validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'First name is required' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        cursorColor: Colors.black54,
                        controller: controller.lastName,
                        textInputAction: TextInputAction.next,
                        decoration: _fieldDecoration(context, "Last Name"),
                        validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Last name is required' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        cursorColor: Colors.black54,
                        controller: controller.email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: _fieldDecoration(context, "Email"),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Email is required';
                          final emailReg = RegExp(r"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$");
                          if (!emailReg.hasMatch(v.trim())) return 'Enter a valid email';
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      Obx(() => TextFormField(
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        cursorColor: Colors.black54,
                        controller: controller.password,
                        obscureText: controller.hidePassword.value,
                        textInputAction: TextInputAction.done,
                        decoration: _fieldDecoration(
                          context,
                          "Password",
                          suffix: IconButton(
                            onPressed: () => controller.hidePassword.value = !controller.hidePassword.value,
                            icon: Icon(
                              controller.hidePassword.value ? Icons.visibility_off : Icons.visibility,
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
                          if (controller.signUpFormKey.currentState?.validate() ?? false) {
                            controller.signUp(context);
                          }
                        },
                      )),
                      const SizedBox(height: 16),

                      // Removed the checkbox area entirely

                      const SizedBox(height: 8),
                      Obx(() => ElevatedButton(
                        onPressed: _allValid.value
                            ? () {
                          // final validation when user presses button
                          if (controller.signUpFormKey.currentState?.validate() ?? false) {
                            controller.signUp(context);
                          } else {
                            // If form validators fail, re-check the inputs (shows errors)
                            _validateInputs();
                          }
                        }
                            : null,
                        child: const Text("Create account"),
                      )),
                      const SizedBox(height: 24),
                      Center(
                        child: TextButton(
                          onPressed: () => Get.off(LoginPage()),
                          child: const Text(
                            "Already have an account? Sign in",
                            style: TextStyle(decoration: TextDecoration.underline, color: Colors.black),
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
