import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lottie/lottie.dart';
import 'home_page.dart';
import 'forgot_password.dart';
import 'sign_up.dart';
import 'email_verification_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController phoneC = TextEditingController();
  final TextEditingController passC = TextEditingController();
  bool loading = false;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _obscurePassword = true;


  Future<void> login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => loading = true);
    try {
      UserCredential userCred = await _auth.signInWithEmailAndPassword(
        email: phoneC.text.trim(),
        password: passC.text.trim(),
      );
      User user = userCred.user!;
      await user.reload();
      user = FirebaseAuth.instance.currentUser!;
      if (user.emailVerified) {
        Navigator.pushAndRemoveUntil(
          // ignore: use_build_context_synchronously
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
          (route) => false,
        );
      } else {
        Navigator.pushAndRemoveUntil(
          // ignore: use_build_context_synchronously
          context,
          MaterialPageRoute(builder: (_) => const EmailVerificationPage()),
          (route) => false,
        );
      }
    } catch (e) {
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  SizedBox(height: constraints.maxHeight * 0.1),
                  Lottie.asset('assets/animations/animation.json', height: 200, fit: BoxFit.contain),
                  SizedBox(height: constraints.maxHeight * 0.1),
                  Text(
                    'sign_in'.tr(),
                    style: Theme.of(context).textTheme.headlineSmall!.copyWith(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: constraints.maxHeight * 0.05),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: phoneC,
                          style: TextStyle(color: Theme.of(context).colorScheme.primary),
                          decoration: InputDecoration(
                            hintText: 'email'.tr(),
                            hintStyle: TextStyle(color: Theme.of(context).colorScheme.primary),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.secondary,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            border: const OutlineInputBorder(
                              borderSide: BorderSide.none,
                              borderRadius: BorderRadius.all(Radius.circular(50)),
                            ),
                          ),
                          validator: (v) => v!.isEmpty ? 'field_required'.tr() : null,
                        ),
                        const SizedBox(height: 16.0)
                        ,

// غير الـ TextFormField بتاع الباسورد
TextFormField(
  controller: passC,
  style: TextStyle(color: Theme.of(context).colorScheme.primary),
  obscureText: _obscurePassword,
  decoration: InputDecoration(
    hintText: 'password'.tr(),
    hintStyle: TextStyle(color: Theme.of(context).colorScheme.primary),
    filled: true,
    fillColor: Theme.of(context).colorScheme.secondary,
    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    border: const OutlineInputBorder(
      borderSide: BorderSide.none,
      borderRadius: BorderRadius.all(Radius.circular(50)),
    ),
    suffixIcon: IconButton(
      icon: Icon(
        _obscurePassword ? Icons.visibility_off : Icons.visibility,
        color: Theme.of(context).colorScheme.primary,
      ),
      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
    ),
  ),
                          validator: (v) => v!.isEmpty ? 'password_required'.tr() : null,
                        ),
                        const SizedBox(height: 20),
                        loading
                            ? const CircularProgressIndicator()
                            : ElevatedButton(
                                onPressed: login,
                                style: ElevatedButton.styleFrom(
                                  elevation: 0,
                                  backgroundColor: Theme.of(context).primaryColor,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(double.infinity, 48),
                                  shape: const StadiumBorder(),
                                ),
                                child: Text('sign_in_btn'.tr()),
                              ),
                        const SizedBox(height: 16.0),
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => ForgotPasswordScreen()),
                            );
                          },
                          child: Text(
                            'forgot_password_link'.tr(),
                            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (_) => SignUpPage()),
                            );
                          },
                          child: Text.rich(
                            TextSpan(
                              text: 'dont_have_account'.tr(),
                              children: [
                                TextSpan(
                                  text: 'sign_up'.tr(),
                                  style: TextStyle(color: Theme.of(context).colorScheme.primary),
                                ),
                              ],
                            ),
                            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}