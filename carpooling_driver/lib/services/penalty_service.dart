import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer' as developer;

/// Service to manage user penalties (1 hour bans for violations)
class PenaltyService {
  final _supabase = Supabase.instance.client;

  /// Check if user currently has an active penalty
  Future<PenaltyStatus> checkUserPenalty(String userId) async {
    try {
      final response = await _supabase
          .from('penalties')
          .select()
          .eq('user_id', userId)
          .eq('is_active', true)
          .gt('penalty_end', DateTime.now().toUtc().toIso8601String())
          .maybeSingle();

      if (response == null) {
        return PenaltyStatus(hasActivePenalty: false);
      }

      final penaltyEnd = DateTime.parse(response['penalty_end'] as String);
      final reason = response['reason'] as String?;
      final penaltyType = response['penalty_type'] as String;

      return PenaltyStatus(
        hasActivePenalty: true,
        penaltyEnd: penaltyEnd,
        reason: reason,
        penaltyType: penaltyType,
      );
    } catch (e) {
      developer.log('❌ Error checking penalty: $e', name: 'PenaltyService');
      return PenaltyStatus(hasActivePenalty: false);
    }
  }

  /// Apply penalty to a user with custom duration
  Future<void> applyPenalty({
    required String userId,
    required String penaltyType,
    required String reason,
    String? rideId,
    Duration? customDuration,
  }) async {
    try {
      final penaltyStart = DateTime.now().toUtc();
      // Default to 20 minutes for ride deletion violations
      final penaltyDuration = customDuration ?? const Duration(minutes: 20);
      final penaltyEnd = penaltyStart.add(penaltyDuration);

      await _supabase.from('penalties').insert({
        'user_id': userId,
        'penalty_type': penaltyType,
        'ride_id': rideId,
        'penalty_start': penaltyStart.toIso8601String(),
        'penalty_end': penaltyEnd.toIso8601String(),
        'reason': reason,
        'is_active': true,
      });

      final minutes = penaltyDuration.inMinutes;
      developer.log(
        '🚫 Penalty applied to user $userId: $reason ($minutes min penalty until $penaltyEnd)',
        name: 'PenaltyService',
      );
    } catch (e) {
      developer.log('❌ Error applying penalty: $e', name: 'PenaltyService');
      rethrow;
    }
  }

  /// Apply penalties to all participants of a ride (driver + all confirmed passengers)
  Future<void> applyPenaltyToAllRideParticipants({
    required String rideId,
    required String driverId,
    required String reason,
  }) async {
    try {
      developer.log('🚫 Applying penalties to all participants of ride $rideId', name: 'PenaltyService');

      // Apply penalty to driver
      await applyPenalty(
        userId: driverId,
        penaltyType: 'ride_deletion_violation',
        reason: 'Driver violation: $reason',
        rideId: rideId,
      );

      // Get all confirmed passengers
      final bookings = await _supabase
          .from('bookings')
          .select('passenger_id')
          .eq('ride_id', rideId)
          .eq('request_status', 'accepted');

      // Apply penalty to each passenger
      for (final booking in bookings) {
        final passengerId = booking['passenger_id'] as String;
        await applyPenalty(
          userId: passengerId,
          penaltyType: 'ride_deletion_violation',
          reason: 'Penalty due to driver violation: $reason',
          rideId: rideId,
        );
      }

      developer.log(
        '✅ Applied penalties to driver and ${bookings.length} passengers',
        name: 'PenaltyService',
      );
    } catch (e) {
      developer.log('❌ Error applying penalties to participants: $e', name: 'PenaltyService');
      rethrow;
    }
  }

  /// Get formatted penalty message for display
  String getPenaltyMessage(PenaltyStatus status) {
    if (!status.hasActivePenalty) return '';

    final minutesRemaining = status.penaltyEnd!.difference(DateTime.now()).inMinutes;
    final hoursRemaining = (minutesRemaining / 60).floor();
    final minsRemaining = minutesRemaining % 60;

    String timeStr;
    if (hoursRemaining > 0) {
      timeStr = '$hoursRemaining hour${hoursRemaining > 1 ? 's' : ''} $minsRemaining min';
    } else {
      timeStr = '$minsRemaining min';
    }

    return '🚫 You are temporarily banned for $timeStr\n'
        'Reason: ${status.reason ?? "Rule violation"}\n\n'
        'You can create/book rides again after the penalty expires.';
  }
}

/// Penalty status data class
class PenaltyStatus {
  final bool hasActivePenalty;
  final DateTime? penaltyEnd;
  final String? reason;
  final String? penaltyType;

  PenaltyStatus({
    required this.hasActivePenalty,
    this.penaltyEnd,
    this.reason,
    this.penaltyType,
  });
}

