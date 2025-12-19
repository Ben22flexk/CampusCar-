import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer' as developer;

class RideRequestService {
  final _supabase = Supabase.instance.client;

  /// Request to join a ride (Passenger)
  Future<String> requestRide({
    required String rideId,
    required int seatsRequested,
  }) async {
    try {
      final bookingId = await _supabase.rpc('request_ride', params: {
        'p_ride_id': rideId,
        'p_seats_requested': seatsRequested,
      });
      
      developer.log('✅ Ride requested successfully', name: 'RideRequestService');
      return bookingId as String;
    } catch (e) {
      developer.log('❌ Error requesting ride: $e', name: 'RideRequestService');
      throw Exception('Failed to request ride: $e');
    }
  }

  /// Accept or reject a ride request (Driver)
  Future<void> respondToRequest({
    required String bookingId,
    required bool accept,
  }) async {
    try {
      await _supabase.rpc('respond_to_ride_request', params: {
        'p_booking_id': bookingId,
        'p_accept': accept,
      });
      
      developer.log(
        '✅ Request ${accept ? "accepted" : "rejected"}', 
        name: 'RideRequestService',
      );
    } catch (e) {
      developer.log('❌ Error responding to request: $e', name: 'RideRequestService');
      throw Exception('Failed to respond: $e');
    }
  }

  /// Get pending requests for driver's rides (Driver)
  Stream<List<Map<String, dynamic>>> getMyRideRequests() {
    return _supabase
        .from('ride_requests_view')
        .stream(primaryKey: ['booking_id'])
        .eq('request_status', 'pending')
        .order('requested_at', ascending: false);
  }

  /// Get all requests for a specific ride (Driver)
  Future<List<Map<String, dynamic>>> getRideRequests(String rideId) async {
    try {
      final response = await _supabase
          .from('bookings')
          .select('''
            id,
            passenger_id,
            seats_booked,
            request_status,
            requested_at,
            profiles!passenger_id (
              full_name,
              email
            )
          ''')
          .eq('ride_id', rideId)
          .eq('request_status', 'pending')
          .order('requested_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      developer.log('❌ Error getting ride requests: $e', name: 'RideRequestService');
      return [];
    }
  }

  /// Get passenger's ride requests (Passenger)
  Stream<List<Map<String, dynamic>>> getMyRequests() {
    return _supabase
        .from('my_ride_requests_view')
        .stream(primaryKey: ['booking_id'])
        .order('requested_at', ascending: false);
  }

  /// Check if passenger already has a pending/accepted request for this ride
  Future<bool> hasExistingRequest(String rideId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      final response = await _supabase
          .from('bookings')
          .select()
          .eq('ride_id', rideId)
          .eq('passenger_id', userId)
          .or('request_status.eq.pending,request_status.eq.accepted');

      return (response as List).isNotEmpty;
    } catch (e) {
      developer.log('❌ Error checking existing request: $e', name: 'RideRequestService');
      return false;
    }
  }
}
