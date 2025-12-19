import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:carpooling_main/core/utils/timezone_helper.dart';
import 'dart:developer' as developer;

/// Service to manage user penalties (1 hour bans for violations)
class PenaltyService {
  final _supabase = Supabase.instance.client;

  /// Check if user currently has an active penalty
  Future<PenaltyStatus> checkUserPenalty(String userId) async {
    try {
      final nowMalaysia = TimezoneHelper.nowInMalaysia();
      final nowUtc = TimezoneHelper.malaysiaToUtc(nowMalaysia);
      
      final response = await _supabase
          .from('penalties')
          .select()
          .eq('user_id', userId)
          .eq('is_active', true)
          .gt('penalty_end', nowUtc.toIso8601String())
          .maybeSingle();

      if (response == null) {
        return PenaltyStatus(hasActivePenalty: false);
      }

      final penaltyEndUtc = DateTime.parse(response['penalty_end'] as String).toUtc();
      final penaltyEnd = TimezoneHelper.utcToMalaysia(penaltyEndUtc);
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

  /// Get formatted penalty message for display
  String getPenaltyMessage(PenaltyStatus status) {
    if (!status.hasActivePenalty) return '';

    final now = TimezoneHelper.nowInMalaysia();
    final minutesRemaining = status.penaltyEnd!.difference(now).inMinutes;
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
        'You can book rides again after the penalty expires.';
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

