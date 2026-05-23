import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:strict/monitor_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'home_page.dart';
import 'main.dart';

class EmailVerificationPage extends StatefulWidget {
  const EmailVerificationPage({super.key});

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  bool _loading = false;
  bool _resendLoading = false;
  String? _message;

  Future<void> _checkVerification() async {
    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      await FirebaseAuth.instance.currentUser!.reload();
      final user = FirebaseAuth.instance.currentUser!;

      if (user.emailVerified) {
        Navigator.pushAndRemoveUntil(
          // ignore: use_build_context_synchronously
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
          (_) => false,
        );
      } else {
        setState(() {
          _message = 'email_not_verified'.tr();
        });
      }
    } catch (e) {
      setState(() {
        _message = "${'error_prefix'.tr()}${e.toString()}";
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _resendEmail() async {
    setState(() {
      _resendLoading = true;
      _message = null;
    });

    try {
      await FirebaseAuth.instance.currentUser!.sendEmailVerification();
      setState(() {
        _message = 'verification_email_sent'.tr();
      });
    } catch (e) {
      setState(() {
        _message = "${'error_prefix'.tr()}${e.toString()}";
      });
    } finally {
      setState(() => _resendLoading = false);
    }
  }

  Future<void> _logout() async {
    await MonitorService.stopCaptureByLogout();
    await FirebaseAuth.instance.signOut();
    Navigator.pushAndRemoveUntil(
      // ignore: use_build_context_synchronously
      context,
      MaterialPageRoute(builder: (_) => WelcomePage()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.mark_email_unread_outlined,
                size: 80,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),

              Text(
                'verify_email'.tr(),
                style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              Text(
                'verification_sent_to'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),

              Text(
                email,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  // ignore: deprecated_member_use
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  // ignore: deprecated_member_use
                  border: Border.all(color: Colors.orange.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'check_spam'.tr(),
                        style: const TextStyle(color: Colors.orange, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _message!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _message!.contains('error_prefix'.tr())
                          ? Colors.red
                          : Colors.green,
                    ),
                  ),
                ),

              _loading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _checkVerification,
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                        shape: const StadiumBorder(),
                      ),
                      child: Text('verified_btn'.tr()),
                    ),

              const SizedBox(height: 12),

              _resendLoading
                  ? const CircularProgressIndicator()
                  : OutlinedButton(
                      onPressed: _resendEmail,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                        shape: const StadiumBorder(),
                      ),
                      child: Text('resend_email'.tr()),
                    ),

              const SizedBox(height: 12),

              TextButton(
                onPressed: _logout,
                child: Text(
                  'logout'.tr(),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
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