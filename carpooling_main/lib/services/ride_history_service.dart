import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer' as developer;

class RideHistoryService {
  final _supabase = Supabase.instance.client;

  /// Get passenger's recent ride history (last 5)
  Future<List<Map<String, dynamic>>> getRecentRideHistory() async {
    try {
      final response = await _supabase
          .from('ride_history')
          .select('''
            *,
            driver:profiles!ride_history_driver_id_fkey (
              display_name,
              avatar_url,
              email
            )
          ''')
          .eq('passenger_id', _supabase.auth.currentUser!.id)
          .order('completed_at', ascending: false)
          .limit(5);

      developer.log(
        '✅ Found ${response.length} recent rides',
        name: 'RideHistoryService',
      );
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      developer.log(
        '❌ Error getting recent history: $e',
        name: 'RideHistoryService',
      );
      return [];
    }
  }

  /// Get all ride history (for "See All" page)
  Future<List<Map<String, dynamic>>> getAllRideHistory({
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final response = await _supabase
          .from('ride_history')
          .select('''
            *,
            driver:profiles!ride_history_driver_id_fkey (
              display_name,
              avatar_url,
              email
            )
          ''')
          .eq('passenger_id', _supabase.auth.currentUser!.id)
          .order('completed_at', ascending: false)
          .range(offset, offset + limit - 1);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      developer.log(
        '❌ Error getting all history: $e',
        name: 'RideHistoryService',
      );
      return [];
    }
  }

  /// Get ride history details by ID
  Future<Map<String, dynamic>?> getRideHistoryById(String historyId) async {
    try {
      final response = await _supabase
          .from('ride_history')
          .select('''
            *,
            driver:profiles!ride_history_driver_id_fkey (
              display_name,
              avatar_url,
              email,
              phone_number
            )
          ''')
          .eq('id', historyId)
          .single();

      return response;
    } catch (e) {
      developer.log(
        '❌ Error getting ride history details: $e',
        name: 'RideHistoryService',
      );
      return null;
    }
  }

  /// Get total number of completed rides
  Future<int> getTotalCompletedRides() async {
    try {
      final response = await _supabase
          .from('ride_history')
          .select('id')
          .eq('passenger_id', _supabase.auth.currentUser!.id);

      return (response as List).length;
    } catch (e) {
      developer.log(
        '❌ Error getting total rides count: $e',
        name: 'RideHistoryService',
      );
      return 0;
    }
  }

  /// Get total amount spent
  Future<double> getTotalAmountSpent() async {
    try {
      final response = await _supabase
          .from('ride_history')
          .select('total_price')
          .eq('passenger_id', _supabase.auth.currentUser!.id);

      if ((response as List).isEmpty) return 0.0;

      final total = (response as List).fold<double>(
        0.0,
        (sum, item) => sum + (item['total_price'] as num).toDouble(),
      );

      return total;
    } catch (e) {
      developer.log(
        '❌ Error calculating total spent: $e',
        name: 'RideHistoryService',
      );
      return 0.0;
    }
  }
}

