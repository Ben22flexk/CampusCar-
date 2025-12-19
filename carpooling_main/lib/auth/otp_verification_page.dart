import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:carpooling_main/services/auth_service.dart';
import 'package:carpooling_main/auth/login_page.dart';

class OTPVerificationPage extends HookConsumerWidget {
  final String email;

  const OTPVerificationPage({super.key, required this.email});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final otpControllers = List.generate(
      8,
      (index) => useTextEditingController(),
    );
    final focusNodes = List.generate(8, (index) => useFocusNode());
    final isLoading = useState<bool>(false);
    final resendTimer = useState<int>(60);
    final canResend = useState<bool>(false);

    // Countdown timer for resend
    useEffect(() {
      Timer? timer;
      if (resendTimer.value > 0) {
        timer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (resendTimer.value > 0) {
            resendTimer.value--;
          } else {
            canResend.value = true;
            t.cancel();
          }
        });
      }
      return () => timer?.cancel();
    }, []);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 32),
              // Icon
              Icon(
                Icons.mail_outline,
                size: 80,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              // Title
              Text(
                'Verify Your Email',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              // Description
              Text(
                'We\'ve sent an 8-digit verification code to',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                email,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              // OTP Input Fields - Two rows of 4 digits each
              Column(
                children: [
                  // First 4 digits
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(4, (index) {
                        return SizedBox(
                          width: 50,
                          height: 60,
                          child: TextField(
                            controller: otpControllers[index],
                            focusNode: focusNodes[index],
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            maxLength: 1,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: InputDecoration(
                              counterText: '',
                              contentPadding: EdgeInsets.zero,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.primary,
                                  width: 2,
                                ),
                              ),
                            ),
                            onChanged: (value) {
                              if (value.isNotEmpty && index < 7) {
                                focusNodes[index + 1].requestFocus();
                              } else if (value.isEmpty && index > 0) {
                                focusNodes[index - 1].requestFocus();
                              }
                            },
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Last 4 digits
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(4, (index) {
                        final actualIndex = index + 4;
                        return SizedBox(
                          width: 50,
                          height: 60,
                          child: TextField(
                            controller: otpControllers[actualIndex],
                            focusNode: focusNodes[actualIndex],
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            maxLength: 1,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: InputDecoration(
                              counterText: '',
                              contentPadding: EdgeInsets.zero,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.primary,
                                  width: 2,
                                ),
                              ),
                            ),
                            onChanged: (value) {
                              if (value.isNotEmpty && actualIndex < 7) {
                                focusNodes[actualIndex + 1].requestFocus();
                              } else if (value.isEmpty && actualIndex > 0) {
                                focusNodes[actualIndex - 1].requestFocus();
                              }

                              // Auto-verify when all 8 digits are entered
                              if (actualIndex == 7 && value.isNotEmpty) {
                                final otp = otpControllers
                                    .map((c) => c.text)
                                    .join();
                                if (otp.length == 8) {
                                  _verifyOTP(context, email, otp, isLoading);
                                }
                              }
                            },
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Verify Button
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: isLoading.value
                      ? null
                      : () {
                          final otp = otpControllers
                              .map((c) => c.text)
                              .join();
                          if (otp.length == 8) {
                            _verifyOTP(context, email, otp, isLoading);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please enter all 8 digits'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: isLoading.value
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Verify',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
              ),
              const SizedBox(height: 24),

              // Resend OTP
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    'Didn\'t receive the code? ',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  TextButton(
                    onPressed: canResend.value
                        ? () => _resendOTP(
                              context,
                              email,
                              resendTimer,
                              canResend,
                            )
                        : null,
                    child: Text(
                      canResend.value
                          ? 'Resend'
                          : 'Resend in ${resendTimer.value}s',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: canResend.value
                            ? theme.colorScheme.primary
                            : Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _verifyOTP(
    BuildContext context,
    String email,
    String otp,
    ValueNotifier<bool> isLoading,
  ) async {
    isLoading.value = true;

    try {
      debugPrint('Verifying OTP for email: $email');
      debugPrint('OTP code: $otp');
      
      final authService = AuthService();
      final response = await authService.verifyOTP(
        email: email,
        token: otp,
      );

      debugPrint('OTP verification response: User=${response.user?.email}, Session=${response.session != null}');

      if (!context.mounted) return;

      if (response.user != null && response.session != null) {
        // Success - Sign out and redirect to login page
        await authService.signOut();
        
        if (!context.mounted) return;
        
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => const LoginPage(),
          ),
          (route) => false,
        );
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Email verified successfully! Please login to continue.',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid or expired OTP. Please try again.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('OTP verification error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _resendOTP(
    BuildContext context,
    String email,
    ValueNotifier<int> resendTimer,
    ValueNotifier<bool> canResend,
  ) async {
    try {
      debugPrint('Resending OTP to: $email');
      
      final authService = AuthService();
      await authService.resendOTP(email: email);

      debugPrint('OTP resend request successful');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verification code sent! Check your email.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );

        // Reset timer
        resendTimer.value = 60;
        canResend.value = false;
      }
    } catch (e) {
      debugPrint('Resend OTP error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to resend code: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }
}

