import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:carpooling_main/core/utils/timezone_helper.dart';
import 'package:postgrest/postgrest.dart';
import 'dart:developer' as developer;

/// Service to manage passenger bookings and cancellations
class BookingService {
  final _supabase = Supabase.instance.client;

  /// Create a booking request (must be approved by driver)
  Future<BookingRequestResult> createBookingRequest({
    required String rideId,
    required int seatsRequired,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        return BookingRequestResult(
          success: false,
          message: 'User not authenticated',
        );
      }

      // Check if user already has a pending or approved request for this ride
      final existing = await _supabase
          .from('bookings')
          .select()
          .eq('ride_id', rideId)
          .eq('passenger_id', userId)
          .inFilter('request_status', ['pending', 'accepted']);

      if (existing.isNotEmpty) {
        return BookingRequestResult(
          success: false,
          message: 'You already have a request for this ride',
        );
      }

      // Create booking request
      final result = await _supabase.from('bookings').insert({
        'ride_id': rideId,
        'passenger_id': userId,
        'seats_booked': seatsRequired,
        'request_status': 'pending',
        'requested_at': DateTime.now().toUtc().toIso8601String(),
      }).select().single();

      developer.log(
        '📤 Booking request created: ${result['id']}',
        name: 'BookingService',
      );

      return BookingRequestResult(
        success: true,
        message: 'Request sent! Waiting for driver approval.',
        bookingId: result['id'] as String,
      );
    } catch (e) {
      developer.log('❌ Error creating booking request: $e', name: 'BookingService');
      return BookingRequestResult(
        success: false,
        message: 'Failed to send request: $e',
      );
    }
  }

  /// Get all booking requests for current user
  Future<List<BookingRequest>> getMyBookingRequests() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return [];

      final response = await _supabase
          .from('bookings')
          .select('''
            id,
            ride_id,
            seats_booked,
            request_status,
            requested_at,
            responded_at,
            rides!inner(
              id,
              from_location,
              to_location,
              scheduled_time,
              price_per_seat,
              ride_type,
              driver_id,
              profiles!inner(
                full_name
              )
            )
          ''')
          .eq('passenger_id', userId)
          .inFilter('request_status', ['pending', 'accepted'])
          .order('requested_at', ascending: false);

      return (response as List).map((data) {
        final ride = data['rides'] as Map<String, dynamic>;
        final driver = ride['profiles'] as Map<String, dynamic>;
        
        return BookingRequest(
          bookingId: data['id'] as String,
          rideId: data['ride_id'] as String,
          seatsBooked: data['seats_booked'] as int,
          requestStatus: data['request_status'] as String,
          requestedAt: DateTime.parse(data['requested_at'] as String),
          approvedAt: data['responded_at'] != null 
              ? DateTime.parse(data['responded_at'] as String) 
              : null,
          fromLocation: ride['from_location'] as String,
          toLocation: ride['to_location'] as String,
          scheduledTime: DateTime.parse(ride['scheduled_time'] as String),
          pricePerSeat: (ride['price_per_seat'] as num).toDouble(),
          rideType: ride['ride_type'] as String,
          driverName: driver['full_name'] as String,
          driverPhone: null, // Phone column doesn't exist in profiles table
        );
      }).toList();
    } catch (e) {
      developer.log('❌ Error fetching booking requests: $e', name: 'BookingService');
      return [];
    }
  }

  /// Cancel a booking with penalty check
  Future<CancellationResult> cancelBooking(String bookingId) async {
    try {
      // Get booking details
      final booking = await _supabase
          .from('bookings')
          .select('*, rides!inner(*)')
          .eq('id', bookingId)
          .single();

      final rideData = booking['rides'] as Map<String, dynamic>;
      final rideStarted = rideData['ride_started'] as bool? ?? false;
      final scheduledTimeUtc = DateTime.parse(rideData['scheduled_time'] as String).toUtc();
      final scheduledTime = TimezoneHelper.utcToMalaysia(scheduledTimeUtc);
      final now = TimezoneHelper.nowInMalaysia();
      final hasPassedDeparture = now.isAfter(scheduledTime);

      // Check if this is a violation (ride started OR past departure time)
      final isViolation = rideStarted || hasPassedDeparture;

      // If violation, apply penalty to passenger only
      if (isViolation) {
        final passengerId = _supabase.auth.currentUser?.id;
        if (passengerId != null) {
          await applyPenalty(
            userId: passengerId,
            penaltyType: 'booking_cancellation_violation',
            reason: 'Cancelled booking after ride started/departure time',
            rideId: rideData['id'] as String,
          );
        }
      }

      // Update booking status with constraint-safe fallback
      try {
        await _supabase
            .from('bookings')
            .update({'request_status': 'cancelled'})
            .eq('id', bookingId);
      } on PostgrestException catch (e) {
        developer.log('⚠️ Cancel update hit constraint, retrying as rejected: $e',
            name: 'BookingService');
        await _supabase
            .from('bookings')
            .update({'request_status': 'rejected'})
            .eq('id', bookingId);
      }

      // Update available seats (increment by 1)
      final currentSeats = rideData['available_seats'] as int;
      await _supabase
          .from('rides')
          .update({'available_seats': currentSeats + 1})
          .eq('id', rideData['id']);

      return CancellationResult(
        success: true,
        isViolation: isViolation,
        message: isViolation
            ? 'Booking cancelled. You received a 1-hour penalty for cancelling after ride started/departure time.'
            : 'Booking cancelled successfully.',
      );
    } catch (e) {
      developer.log('Error cancelling booking: $e', name: 'BookingService');
      return CancellationResult(
        success: false,
        isViolation: false,
        message: 'Failed to cancel booking: $e',
      );
    }
  }

  /// Apply penalty to passenger only (not driver or other passengers)
  Future<void> applyPenalty({
    required String userId,
    required String penaltyType,
    required String reason,
    String? rideId,
  }) async {
    try {
      final penaltyStart = DateTime.now().toUtc();
      final penaltyEnd = penaltyStart.add(const Duration(hours: 1));

      await _supabase.from('penalties').insert({
        'user_id': userId,
        'penalty_type': penaltyType,
        'ride_id': rideId,
        'penalty_start': penaltyStart.toIso8601String(),
        'penalty_end': penaltyEnd.toIso8601String(),
        'reason': reason,
        'is_active': true,
      });

      developer.log(
        '🚫 Penalty applied to passenger $userId: $reason',
        name: 'BookingService',
      );
    } catch (e) {
      developer.log('❌ Error applying penalty: $e', name: 'BookingService');
      rethrow;
    }
  }
}

/// Result of a cancellation attempt
class CancellationResult {
  final bool success;
  final bool isViolation;
  final String message;

  CancellationResult({
    required this.success,
    required this.isViolation,
    required this.message,
  });
}

/// Result of a booking request
class BookingRequestResult {
  final bool success;
  final String message;
  final String? bookingId;

  BookingRequestResult({
    required this.success,
    required this.message,
    this.bookingId,
  });
}

/// Booking request model
class BookingRequest {
  final String bookingId;
  final String rideId;
  final int seatsBooked;
  final String requestStatus;
  final DateTime requestedAt;
  final DateTime? approvedAt;
  final String fromLocation;
  final String toLocation;
  final DateTime scheduledTime;
  final double pricePerSeat;
  final String rideType;
  final String driverName;
  final String? driverPhone;

  BookingRequest({
    required this.bookingId,
    required this.rideId,
    required this.seatsBooked,
    required this.requestStatus,
    required this.requestedAt,
    this.approvedAt,
    required this.fromLocation,
    required this.toLocation,
    required this.scheduledTime,
    required this.pricePerSeat,
    required this.rideType,
    required this.driverName,
    this.driverPhone,
  });
}

