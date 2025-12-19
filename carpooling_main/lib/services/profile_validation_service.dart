import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer' as developer;

/// Service to validate user profiles before performing actions
/// Ensures all users exist in profiles table and are not blocked
class ProfileValidationService {
  final _supabase = Supabase.instance.client;

  /// Check if current user has a valid profile
  Future<bool> validateCurrentUser() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        developer.log('❌ No user logged in', name: 'ProfileValidation');
        return false;
      }

      return await validateUserProfile(userId);
    } catch (e) {
      developer.log('❌ Error validating current user: $e', name: 'ProfileValidation');
      return false;
    }
  }

  /// Check if a specific user has a valid profile
  Future<bool> validateUserProfile(String userId) async {
    try {
      final result = await _supabase.rpc(
        'user_exists_in_profiles',
        params: {'p_user_id': userId},
      );

      final exists = result as bool;
      
      if (!exists) {
        developer.log('❌ User $userId not found in profiles', name: 'ProfileValidation');
      } else {
        developer.log('✅ User $userId validated', name: 'ProfileValidation');
      }

      return exists;
    } catch (e) {
      developer.log('❌ Error validating user profile: $e', name: 'ProfileValidation');
      return false;
    }
  }

  /// Get or create profile for current user
  Future<Map<String, dynamic>?> ensureProfileExists() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('No user logged in');
      }

      // Check if profile exists
      var profile = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      // If profile doesn't exist, create it
      if (profile == null) {
        developer.log('⚠️  Profile not found, creating...', name: 'ProfileValidation');
        
        profile = await _supabase
            .from('profiles')
            .insert({
              'id': user.id,
              'email': user.email,
              'full_name': user.userMetadata?['full_name'] ?? user.email,
            })
            .select()
            .single();

        developer.log('✅ Profile created', name: 'ProfileValidation');
      }

      return profile;
    } catch (e) {
      developer.log('❌ Error ensuring profile exists: $e', name: 'ProfileValidation');
      return null;
    }
  }

  /// Validate user before sending message
  Future<bool> validateForMessaging(String recipientId) async {
    // Validate current user
    if (!await validateCurrentUser()) {
      throw Exception('Your profile is not set up. Please contact support.');
    }

    // Validate recipient
    if (!await validateUserProfile(recipientId)) {
      throw Exception('Recipient profile not found. Cannot send message.');
    }

    return true;
  }

  /// Validate user before creating booking
  Future<bool> validateForBooking(String driverId) async {
    // Validate current user (passenger)
    if (!await validateCurrentUser()) {
      throw Exception('Your profile is not set up. Please contact support.');
    }

    // Validate driver
    if (!await validateUserProfile(driverId)) {
      throw Exception('Driver profile not found. Cannot create booking.');
    }

    return true;
  }

  /// Check if user is blocked
  Future<bool> isUserBlocked(String userId) async {
    try {
      final profile = await _supabase
          .from('profiles')
          .select('is_blocked')
          .eq('id', userId)
          .maybeSingle();

      if (profile == null) {
        developer.log('⚠️  Profile not found for user $userId', name: 'ProfileValidation');
        return true; // Block if profile doesn't exist
      }

      final isBlocked = profile['is_blocked'] as bool? ?? false;
      
      if (isBlocked) {
        developer.log('🚫 User $userId is blocked', name: 'ProfileValidation');
      }

      return isBlocked;
    } catch (e) {
      developer.log('❌ Error checking if user is blocked: $e', name: 'ProfileValidation');
      return true; // Block on error to be safe
    }
  }

  /// Sync current user session with profile
  Future<void> syncUserProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      developer.log('🔄 Syncing user profile...', name: 'ProfileValidation');

      // Upsert profile (insert or update)
      final nowUtc = DateTime.now().toUtc();
      await _supabase.from('profiles').upsert({
        'id': user.id,
        'email': user.email,
        'full_name': user.userMetadata?['full_name'] ?? user.email,
        'updated_at': nowUtc.toIso8601String(),
      });

      developer.log('✅ User profile synced', name: 'ProfileValidation');
    } catch (e) {
      developer.log('❌ Error syncing user profile: $e', name: 'ProfileValidation');
    }
  }
}

