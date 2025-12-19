import 'dart:async';

import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DeepLinkService {
  StreamSubscription? _linkSubscription;
  final SupabaseClient _supabase = Supabase.instance.client;
  final AppLinks _appLinks = AppLinks();

  // Initialize deep link listener
  Future<void> initialize({
    required Function(String) onEmailConfirmed,
    required Function(String) onError,
  }) async {
    try {
      // Check for initial link (when app is opened from link while closed)
      final initialUri = await _appLinks.getInitialAppLink();
      if (initialUri != null) {
        _handleDeepLink(initialUri.toString(), onEmailConfirmed, onError);
      }

      // Listen for links while app is running
      _linkSubscription = _appLinks.uriLinkStream.listen(
        (Uri uri) {
          _handleDeepLink(uri.toString(), onEmailConfirmed, onError);
        },
        onError: (err) {
          debugPrint('Deep link error: $err');
          onError('Failed to process link');
        },
      );
    } catch (e) {
      debugPrint('Deep link initialization error: $e');
      onError('Failed to initialize deep linking');
    }
  }

  // Handle incoming deep link
  Future<void> _handleDeepLink(
    String link,
    Function(String) onEmailConfirmed,
    Function(String) onError,
  ) async {
    try {
      final uri = Uri.parse(link);
      debugPrint('Deep link received: $link');
      debugPrint('Scheme: ${uri.scheme}, Host: ${uri.host}');

      // Handle email confirmation links
      // Format: campuscar://confirm?type=signup&token_hash=XXX&access_token=XXX&refresh_token=XXX
      if (uri.host == 'confirm' || uri.host == 'login') {
        final type = uri.queryParameters['type'];
        final accessToken = uri.queryParameters['access_token'];
        final refreshToken = uri.queryParameters['refresh_token'];

        debugPrint('Type: $type, Has Access Token: ${accessToken != null}');

        // Handle email confirmation
        if (type == 'signup' || type == 'magiclink' || type == 'email') {
          if (accessToken != null && refreshToken != null) {
            try {
              // Set the session with the tokens from the email link
              final response = await _supabase.auth.setSession(accessToken);

              // Get user info
              final user = response.session?.user;
              if (user != null) {
                final userName = user.userMetadata?['full_name'] ?? 'User';
                onEmailConfirmed('Welcome, $userName! Your email has been verified.');
              } else {
                onEmailConfirmed('Your email has been verified successfully!');
              }
            } catch (e) {
              debugPrint('Error setting session: $e');
              // Fallback: session might already be set by Supabase
              final user = _supabase.auth.currentUser;
              if (user != null) {
                final userName = user.userMetadata?['full_name'] ?? 'User';
                onEmailConfirmed('Welcome, $userName! Your email has been verified.');
              } else {
                onEmailConfirmed('Your email has been verified successfully!');
              }
            }
          } else {
            onError('Invalid confirmation link');
          }
        }
        // Handle password reset
        else if (type == 'recovery') {
          if (accessToken != null) {
            onEmailConfirmed('password_reset');
          } else {
            onError('Invalid password reset link');
          }
        }
      }
      // Handle OAuth callback
      else if (uri.host == 'login-callback' || uri.scheme == 'com.tarc.campuscar') {
        // OAuth callback is handled automatically by Supabase
        onEmailConfirmed('Sign in successful!');
      }
    } catch (e) {
      debugPrint('Error handling deep link: $e');
      onError('Failed to process confirmation link');
    }
  }

  // Dispose the subscription
  void dispose() {
    _linkSubscription?.cancel();
  }

  // Handle recovery/password reset link
  Future<void> handleRecoveryLink(String accessToken) async {
    try {
      // The access token from recovery link can be used to update password
      // User will be redirected to password reset page with this token
      debugPrint('Recovery token received: ${accessToken.substring(0, 10)}...');
    } catch (e) {
      debugPrint('Error handling recovery link: $e');
      rethrow;
    }
  }
}

