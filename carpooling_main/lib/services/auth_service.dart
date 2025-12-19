import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Get current user
  User? get currentUser => _supabase.auth.currentUser;

  // Get auth state changes stream
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  // Check if user is logged in
  bool get isLoggedIn => currentUser != null;

  // Sign up with email and password (sends OTP code)
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    required String contactNumber,
  }) async {
    try {
      debugPrint('=== SIGNUP DEBUG ===');
      debugPrint('Email: $email');
      debugPrint('Full Name: $fullName');
      debugPrint('Contact: $contactNumber');
      
      // Sign up without emailRedirectTo to trigger OTP flow
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          'contact_number': contactNumber,
        },
      );
      
      // Detailed response logging
      debugPrint('=== SIGNUP RESPONSE ===');
      debugPrint('User ID: ${response.user?.id}');
      debugPrint('User Email: ${response.user?.email}');
      debugPrint('Email Confirmed: ${response.user?.emailConfirmedAt}');
      debugPrint('Session exists: ${response.session != null}');
      debugPrint('User metadata: ${response.user?.userMetadata}');
      
      if (response.session == null) {
        debugPrint('⚠️ NO SESSION - Email confirmation required');
        debugPrint('User should receive OTP email at: $email');
      } else {
        debugPrint('✅ SESSION ACTIVE - User logged in immediately');
        debugPrint('Email confirmation is DISABLED in Supabase');
      }
      
      return response;
    } catch (e) {
      debugPrint('=== SIGNUP ERROR ===');
      debugPrint('Error type: ${e.runtimeType}');
      debugPrint('Error message: $e');
      rethrow;
    }
  }

  // Verify OTP
  Future<AuthResponse> verifyOTP({
    required String email,
    required String token,
  }) async {
    try {
      final response = await _supabase.auth.verifyOTP(
        email: email,
        token: token,
        type: OtpType.signup,
      );
      return response;
    } catch (e) {
      debugPrint('OTP verification error: $e');
      rethrow;
    }
  }

  // Resend OTP
  Future<void> resendOTP({required String email}) async {
    try {
      debugPrint('=== RESEND OTP DEBUG ===');
      debugPrint('Email: $email');
      debugPrint('OTP Type: signup');
      
      // Try resending with signup type
      await _supabase.auth.resend(
        type: OtpType.signup,
        email: email,
      );
      
      debugPrint('✅ Resend OTP request completed successfully');
      debugPrint('Check email: $email (including spam folder)');
    } catch (e) {
      debugPrint('=== RESEND OTP ERROR ===');
      debugPrint('Error type: ${e.runtimeType}');
      debugPrint('Error message: $e');
      
      // Check for specific error types
      if (e.toString().contains('rate limit') || e.toString().contains('email_send_rate_limit')) {
        debugPrint('⚠️ RATE LIMIT - Too many requests. Wait 60 seconds.');
        throw Exception('Please wait 60 seconds before requesting another code');
      } else if (e.toString().contains('not found') || e.toString().contains('User not found')) {
        debugPrint('⚠️ USER NOT FOUND - Email may not be registered or already confirmed.');
        throw Exception('Email not found or already confirmed');
      } else if (e.toString().contains('already confirmed')) {
        debugPrint('⚠️ EMAIL ALREADY CONFIRMED');
        throw Exception('Email is already confirmed. Please try logging in.');
      }
      
      rethrow;
    }
  }

  // Sign in with email and password
  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return response;
    } catch (e) {
      debugPrint('Sign in error: $e');
      rethrow;
    }
  }

  // Sign in with Google
  Future<bool> signInWithGoogle() async {
    try {
      final response = await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'com.tarc.campuscar://login-callback/',
      );
      return response;
    } catch (e) {
      debugPrint('Google sign in error: $e');
      rethrow;
    }
  }

  // Send password reset email
  Future<void> resetPassword({required String email}) async {
    try {
      await _supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: 'campuscar://confirm', // Deep link for password reset
      );
    } catch (e) {
      debugPrint('Password reset error: $e');
      rethrow;
    }
  }

  // Update password
  Future<UserResponse> updatePassword({required String newPassword}) async {
    try {
      final response = await _supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      return response;
    } catch (e) {
      debugPrint('Update password error: $e');
      rethrow;
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      debugPrint('Sign out error: $e');
      rethrow;
    }
  }

  // Get user profile data
  Map<String, dynamic>? get userMetadata => currentUser?.userMetadata;

  // Get user's full name
  String get userFullName => userMetadata?['full_name'] ?? 'User';

  // Get user's contact number (from metadata, fallback to profiles table)
  String get userContactNumber => userMetadata?['contact_number'] ?? '';
  
  // Get user's phone number from profiles table
  Future<String> getUserPhoneNumber() async {
    try {
      final userId = currentUser?.id;
      if (userId == null) return '';
      
      final profile = await _supabase
          .from('profiles')
          .select('phone_number')
          .eq('id', userId)
          .maybeSingle();
      
      return profile?['phone_number'] as String? ?? '';
    } catch (e) {
      debugPrint('Error getting phone number: $e');
      return '';
    }
  }
}

