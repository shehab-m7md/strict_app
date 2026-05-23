import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lottie/lottie.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'auth_service.dart';
import 'login_page.dart';
import 'email_verification_page.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController nameC = TextEditingController();
  final TextEditingController emailC = TextEditingController();
  final TextEditingController passC = TextEditingController();
  final TextEditingController customC = TextEditingController();
  final TextEditingController confirmPassC = TextEditingController();
  bool loading = false;
  bool _obscurePassword = true;

  Future<void> signUpNow() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => loading = true);

    String email = emailC.text.trim();
    String password = passC.text.trim();
    String name = nameC.text.trim();
    String customId = customC.text.trim();

    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection("custom_ids")
          .doc(customId)
          .get();

      if (doc.exists) {
        setState(() => loading = false);
        ScaffoldMessenger.of(
          // ignore: use_build_context_synchronously
          context,
        ).showSnackBar(SnackBar(content: Text('custom_id_taken'.tr())));
        return;
      }

      String? result = await signUp(
        email: email,
        password: password,
        displayName: name,
        customId: customId,
      );

      if (result != "done") {
        setState(() => loading = false);
        ScaffoldMessenger.of(
          // ignore: use_build_context_synchronously
          context,
        ).showSnackBar(SnackBar(content: Text(result!)));
        return;
      }

      String uid = FirebaseAuth.instance.currentUser!.uid;

      await FirebaseFirestore.instance
          .collection("custom_ids")
          .doc(customId)
          .set({"uid": uid, "createdAt": FieldValue.serverTimestamp()});

      await FirebaseFirestore.instance.collection("users").doc(uid).set({
        "email": email,
        "displayName": name,
        "customId": customId,
        "avatarIndex": 2,
        "createdAt": FieldValue.serverTimestamp(),
      });

      Navigator.pushAndRemoveUntil(
        // ignore: use_build_context_synchronously
        context,
        MaterialPageRoute(builder: (_) => const EmailVerificationPage()),
        (route) => false,
      );
    } catch (e) {
      setState(() => loading = false);

      if (FirebaseAuth.instance.currentUser != null) {
        await FirebaseAuth.instance.currentUser!.delete();
      }

      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${'error_prefix'.tr()}${e.toString()}')),
      );
    }
  }

  InputDecoration _fieldDecoration(BuildContext context, String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Theme.of(context).colorScheme.primary),
      filled: true,
      fillColor: Theme.of(context).colorScheme.secondary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      counterText: '',
      border: const OutlineInputBorder(
        borderSide: BorderSide.none,
        borderRadius: BorderRadius.all(Radius.circular(50)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  SizedBox(height: constraints.maxHeight * 0.08),
                  Lottie.asset(
                    'assets/animations/animation.json',
                    height: 80,
                    fit: BoxFit.contain,
                  ),
                  SizedBox(height: constraints.maxHeight * 0.08),

                  Text(
                    'sign_up'.tr(),
                    style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  SizedBox(height: constraints.maxHeight * 0.05),

                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: nameC,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          maxLength: 16,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[a-zA-Z0-9_\s\u0600-\u06FF]'),
                            ),
                          ],
                          decoration: _fieldDecoration(
                            context,
                            'full_name'.tr(),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'enter_your_name'.tr();
                            }
                            if (v.trim().length < 3) return 'at_least_3'.tr();
                            return null;
                          },
                        ),

                        const SizedBox(height: 16),

                        TextFormField(
                          controller: emailC,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          decoration: _fieldDecoration(context, 'email'.tr()),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'enter_your_email'.tr();
                            }
                            if (!RegExp(
                              r'^[\w\.-]+@[\w\.-]+\.\w{2,}$',
                            ).hasMatch(v.trim())) {
                              return 'invalid_email'.tr();
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 16),
                        // غير الـ TextFormField بتاع الباسورد
                        TextFormField(
                          controller: passC,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            hintText: 'password'.tr(),
                            hintStyle: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.secondary,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                            border: const OutlineInputBorder(
                              borderSide: BorderSide.none,
                              borderRadius: BorderRadius.all(
                                Radius.circular(50),
                              ),
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'password_required'.tr();
                            }
                            final valid =
                                v.length >= 8 &&
                                !v.contains(' ') &&
                                v.contains(RegExp(r'[A-Za-z]')) &&
                                v.contains(RegExp(r'[0-9]')) &&
                                v.contains(RegExp(r'[!@#$]'));
                            if (!valid) return 'password_requirements'.tr();
                            return null;
                          },
                        ),

                        const SizedBox(height: 16),

                        TextFormField(
                          controller: confirmPassC,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          obscureText: true,
                          decoration: _fieldDecoration(
                            context,
                            'confirm_password'.tr(),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'please_confirm_password'.tr();
                            }
                            if (v != passC.text) {
                              return 'passwords_no_match'.tr();
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 16),

                        TextFormField(
                          controller: customC,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          maxLength: 16,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[a-zA-Z0-9_]'),
                            ),
                          ],
                          decoration: _fieldDecoration(
                            context,
                            'unique_id'.tr(),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'custom_id_required'.tr();
                            }
                            if (v.length < 3) return 'at_least_3'.tr();
                            return null;
                          },
                        ),

                        const SizedBox(height: 24),

                        loading
                            ? const CircularProgressIndicator()
                            : ElevatedButton(
                                onPressed: signUpNow,
                                style: ElevatedButton.styleFrom(
                                  elevation: 0,
                                  backgroundColor: Theme.of(
                                    context,
                                  ).primaryColor,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(double.infinity, 48),
                                  shape: const StadiumBorder(),
                                ),
                                child: Text('sign_up'.tr()),
                              ),

                        const SizedBox(height: 20),

                        TextButton(
                          onPressed: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (_) => LoginPage()),
                            );
                          },
                          child: Text.rich(
                            TextSpan(
                              text: 'already_have_account'.tr(),
                              children: [
                                TextSpan(
                                  text: 'sign_in'.tr(),
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                            style: Theme.of(context).textTheme.bodyMedium!
                                .copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
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
