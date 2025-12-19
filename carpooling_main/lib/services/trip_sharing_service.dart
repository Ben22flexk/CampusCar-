import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer' as developer;

/// Service to handle trip sharing functionality
class TripSharingService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Create a trip share link for a booking
  Future<TripShareResult> createTripShare({
    required String bookingId,
    String? sharedWithName,
    String? sharedWithPhone,
    int hoursValid = 24,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Call database function to create trip share
      final result = await _supabase.rpc(
        'create_trip_share',
        params: {
          'p_booking_id': bookingId,
          'p_shared_with_name': sharedWithName,
          'p_shared_with_phone': sharedWithPhone,
          'p_hours_valid': hoursValid,
        },
      );

      final data = result as Map<String, dynamic>;
      final shareToken = data['share_token'] as String;
      final expiresAt = DateTime.parse(data['expires_at'] as String);

      developer.log(
        '✅ Trip share created: $shareToken',
        name: 'TripSharingService',
      );

      // Generate shareable link (you'll need to configure your app's deep link)
      final shareLink = _generateShareLink(shareToken);

      return TripShareResult(
        shareId: data['share_id'] as String,
        shareToken: shareToken,
        shareLink: shareLink,
        expiresAt: expiresAt,
      );
    } catch (e) {
      developer.log('❌ Error creating trip share: $e', name: 'TripSharingService');
      rethrow;
    }
  }

  /// Get trip share details by token
  Future<Map<String, dynamic>?> getTripShareByToken(String token) async {
    try {
      final response = await _supabase
          .from('trip_shares')
          .select('''
            *,
            booking:bookings!inner(
              *,
              ride:rides!inner(
                *,
                driver_profile:profiles!rides_driver_id_fkey(
                  full_name,
                  phone,
                  avatar_url
                ),
                driver_verification:driver_verifications!driver_verifications_user_id_fkey(
                  vehicle_model,
                  vehicle_color,
                  vehicle_plate_number
                )
              )
            )
          ''')
          .eq('share_token', token)
          .eq('is_active', true)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return response as Map<String, dynamic>;
    } catch (e) {
      developer.log('Error getting trip share: $e', name: 'TripSharingService');
      return null;
    }
  }

  /// Get active trip shares for current user
  Future<List<Map<String, dynamic>>> getMyTripShares() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        return [];
      }

      final response = await _supabase
          .from('trip_shares')
          .select('''
            *,
            booking:bookings!inner(
              ride:rides!inner(
                from_location,
                to_location,
                scheduled_time
              )
            )
          ''')
          .eq('created_by', userId)
          .eq('is_active', true)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      developer.log('Error getting trip shares: $e', name: 'TripSharingService');
      return [];
    }
  }

  /// Revoke a trip share
  Future<void> revokeTripShare(String shareId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      await _supabase
          .from('trip_shares')
          .update({'is_active': false})
          .eq('id', shareId)
          .eq('created_by', userId);

      developer.log('✅ Trip share revoked: $shareId', name: 'TripSharingService');
    } catch (e) {
      developer.log('❌ Error revoking trip share: $e', name: 'TripSharingService');
      rethrow;
    }
  }

  /// Generate shareable link (configure with your app's URL scheme)
  String _generateShareLink(String token) {
    // You can customize this based on your app's deep linking setup
    // For now, return a simple format that can be opened in the app
    return 'campuscar://trip/$token';
    // Or for web: 'https://yourdomain.com/trip/$token'
  }
}

/// Result of creating a trip share
class TripShareResult {
  final String shareId;
  final String shareToken;
  final String shareLink;
  final DateTime expiresAt;

  TripShareResult({
    required this.shareId,
    required this.shareToken,
    required this.shareLink,
    required this.expiresAt,
  });
}
