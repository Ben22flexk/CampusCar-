import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:carpooling_driver/core/utils/timezone_helper.dart';
import 'dart:developer' as developer;

/// Dashboard Statistics Model
class DashboardStats {
  final int todayRides;
  final int weekRides;
  final double todayEarnings;
  final double averageRating;
  final int totalRatings;
  final int pendingRequests;

  const DashboardStats({
    required this.todayRides,
    required this.weekRides,
    required this.todayEarnings,
    required this.averageRating,
    required this.totalRatings,
    required this.pendingRequests,
  });

  factory DashboardStats.empty() {
    return const DashboardStats(
      todayRides: 0,
      weekRides: 0,
      todayEarnings: 0.0,
      averageRating: 0.0,
      totalRatings: 0,
      pendingRequests: 0,
    );
  }
}

/// Service to fetch real-time dashboard statistics for drivers
class DriverDashboardService {
  final SupabaseClient _supabase = Supabase.instance.client;

  DateTime _startOfMalaysiaDay(DateTime malaysiaNow) =>
      DateTime(malaysiaNow.year, malaysiaNow.month, malaysiaNow.day);

  DateTime _startOfMalaysiaWeek(DateTime malaysiaNow) {
    final startOfDay = _startOfMalaysiaDay(malaysiaNow);
    return startOfDay.subtract(Duration(days: malaysiaNow.weekday - 1));
  }

  /// Get dashboard statistics for the current driver
  Future<DashboardStats> getDashboardStats() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        return DashboardStats.empty();
      }

      // Use Malaysia boundaries, but compute in Dart from driver_ride_history to avoid DB timezone/view edge cases.
      // This ensures "today" updates correctly right after a ride is completed.
      final malaysiaNow = TimezoneHelper.nowInMalaysia();
      final startOfTodayMalaysia = _startOfMalaysiaDay(malaysiaNow);
      final startOfWeekMalaysia = _startOfMalaysiaWeek(malaysiaNow);

      final historyResponse = await _supabase
          .from('driver_ride_history')
          .select('completed_at,total_earnings')
          .eq('driver_id', userId)
          .order('completed_at', ascending: false)
          .limit(200);

      final history = List<Map<String, dynamic>>.from(historyResponse as List);

      int todayRidesCount = 0;
      int weekRidesCount = 0;
      double todayEarnings = 0.0;

      for (final ride in history) {
        final completedAtRaw = ride['completed_at'] as String?;
        if (completedAtRaw == null) continue;

        final completedAtUtc = DateTime.parse(completedAtRaw).toUtc();
        final completedAtMalaysia = TimezoneHelper.utcToMalaysia(completedAtUtc);

        final isInWeek = !completedAtMalaysia.isBefore(startOfWeekMalaysia);
        if (!isInWeek) {
          // history is ordered desc; once we're before this week, we can stop.
          break;
        }

        weekRidesCount += 1;

        final isToday = !completedAtMalaysia.isBefore(startOfTodayMalaysia);
        if (isToday) {
          todayRidesCount += 1;
          todayEarnings += ((ride['total_earnings'] as num?)?.toDouble() ?? 0.0);
        }
      }

      // Pending requests: bookings are tied to rides via ride_id (bookings table does NOT have driver_id).
      // So we first fetch the driver's active/scheduled rides, then count pending bookings for them.
      final activeRideIdsResponse = await _supabase
          .from('rides')
          .select('id')
          .eq('driver_id', userId)
          .inFilter('ride_status', ['active', 'scheduled', 'in_progress']);

      final rideIds = (activeRideIdsResponse as List)
          .map((e) => e['id'] as String?)
          .whereType<String>()
          .toList();

      int pendingRequests = 0;
      if (rideIds.isNotEmpty) {
        final pendingBookingsResponse = await _supabase
            .from('bookings')
            .select('id')
            .inFilter('ride_id', rideIds)
            .eq('request_status', 'pending');
        pendingRequests = (pendingBookingsResponse as List).length;
      }

      // Get driver rating from driver_ratings table
      final ratingsResponse = await _supabase
          .from('driver_ratings')
          .select('rating')
          .eq('driver_id', userId);

      double averageRating = 0.0;
      int totalRatings = 0;

      if (ratingsResponse.isNotEmpty) {
        totalRatings = ratingsResponse.length;
        final ratings = ratingsResponse.map((r) => (r['rating'] as num).toDouble()).toList();
        averageRating = ratings.reduce((a, b) => a + b) / ratings.length;
      }
    
      return DashboardStats(
        todayRides: todayRidesCount,
        weekRides: weekRidesCount,
        todayEarnings: todayEarnings,
        averageRating: averageRating,
        totalRatings: totalRatings,
        pendingRequests: pendingRequests,
      );
    } catch (e) {
      developer.log('Error fetching dashboard stats: $e', name: 'DriverDashboardService');
      return DashboardStats.empty();
    }
  }

  /// Stream of dashboard statistics (updates in real-time)
  Stream<DashboardStats> watchDashboardStats() async* {
    yield await getDashboardStats();

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      yield DashboardStats.empty();
      return;
    }

    // Listen to rides table changes
    await for (final _ in _supabase
        .from('rides')
        .stream(primaryKey: ['id'])
        .eq('driver_id', userId)) {
      yield await getDashboardStats();
    }
  }
}

