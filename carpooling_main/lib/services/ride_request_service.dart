import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer' as developer;

class RideRequestService {
  final _supabase = Supabase.instance.client;

  /// Request to join a ride (Passenger) - ALWAYS 1 SEAT
  Future<String> requestRide({
    required String rideId,
    required double farePerSeat, // Required: calculated fare from fare service
    required String pickupLocation, // Required: passenger's specific pickup location
    double? pickupLat, // Optional: passenger's pickup latitude
    double? pickupLng, // Optional: passenger's pickup longitude
    String? destination, // Optional: passenger's destination (defaults to driver's destination)
    double? destinationLat, // Optional: passenger's destination latitude
    double? destinationLng, // Optional: passenger's destination longitude
    int seatsRequested = 1, // Default to 1, ignore user input
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      // Get the ride details to check if it's "Start Now" or scheduled
      final rideResponse = await _supabase
          .from('rides')
          .select('scheduled_time, ride_type')
          .eq('id', rideId)
          .single();
      
      final scheduledTime = DateTime.parse(rideResponse['scheduled_time']);
      final rideType = rideResponse['ride_type'] ?? 'scheduled';
      final isStartNow = rideType == 'start_now';

      // Check for existing active requests
      final existingBookings = await _supabase
          .from('bookings')
          .select('*, rides!inner(scheduled_time, ride_type, ride_status)')
          .eq('passenger_id', userId)
          .inFilter('request_status', ['pending', 'accepted']);

      if (existingBookings.isNotEmpty) {
        // Rule 1: Only ONE active "Start Now" request allowed
        if (isStartNow) {
          final hasActiveStartNow = existingBookings.any((booking) {
            final ride = booking['rides'] as Map<String, dynamic>;
            return (ride['ride_type'] == 'start_now' || ride['ride_type'] == null) &&
                   ride['ride_status'] == 'active';
          });
          
          if (hasActiveStartNow) {
            throw Exception(
              'You already have an active "Start Now" ride request. '
              'Please complete or cancel it before requesting another.'
            );
          }
        } else {
          // Rule 2: No overlapping scheduled rides (within 30 minutes)
          for (final booking in existingBookings) {
            final ride = booking['rides'] as Map<String, dynamic>;
            final existingTime = DateTime.parse(ride['scheduled_time']);
            
            // Check if rides overlap (within 30 minutes of each other)
            final timeDifference = scheduledTime.difference(existingTime).inMinutes.abs();
            if (timeDifference < 30) {
              throw Exception(
                'Ride time conflicts with another request. '
                'Rides must be at least 30 minutes apart.'
              );
            }
          }
        }
      }

      // ALWAYS request exactly 1 seat
      final Map<String, dynamic> params = {
        'p_ride_id': rideId,
        'p_seats_requested': 1, // FIXED: Always 1 seat per passenger
        'p_fare_per_seat': farePerSeat, // Pass the calculated fare
        'p_pickup_location': pickupLocation, // Pass passenger's specific pickup location
      };
      
      // Add pickup coordinate parameters if provided
      if (pickupLat != null) params['p_pickup_lat'] = pickupLat;
      if (pickupLng != null) params['p_pickup_lng'] = pickupLng;
      
      // Add destination parameters if provided
      if (destination != null) params['p_destination'] = destination;
      if (destinationLat != null) params['p_destination_lat'] = destinationLat;
      if (destinationLng != null) params['p_destination_lng'] = destinationLng;
      
      final bookingId = await _supabase.rpc('request_ride', params: params);
      
      developer.log('✅ Ride requested successfully (1 seat, fare: RM ${farePerSeat.toStringAsFixed(2)})', name: 'RideRequestService');
      return bookingId as String;
    } catch (e) {
      developer.log('❌ Error requesting ride: $e', name: 'RideRequestService');
      
      // Re-throw with cleaned message
      if (e.toString().contains('Exception:')) {
        rethrow;
      }
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

