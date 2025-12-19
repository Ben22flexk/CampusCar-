import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer' as developer;

/// Service to manage ride reviews and ratings
class ReviewService {
  final _supabase = Supabase.instance.client;

  /// Submit a review for a ride
  Future<bool> submitReview({
    required String rideId,
    required String driverId,
    required int rating,
    String? comment,
  }) async {
    try {
      final passengerId = _supabase.auth.currentUser?.id;
      if (passengerId == null) {
        developer.log('❌ User not authenticated', name: 'Review');
        return false;
      }

      developer.log('⭐ Submitting review: $rating stars', name: 'Review');

      await _supabase.from('ride_reviews').insert({
        'ride_id': rideId,
        'passenger_id': passengerId,
        'driver_id': driverId,
        'rating': rating,
        'comment': comment,
        'review_type': 'ride',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      developer.log('✅ Review submitted successfully', name: 'Review');
      return true;
    } catch (e) {
      developer.log('❌ Error submitting review: $e', name: 'Review');
      return false;
    }
  }

  /// Check if user has already reviewed a ride
  Future<bool> hasReviewed(String rideId) async {
    try {
      final passengerId = _supabase.auth.currentUser?.id;
      if (passengerId == null) return false;

      final result = await _supabase
          .from('ride_reviews')
          .select('id')
          .eq('ride_id', rideId)
          .eq('passenger_id', passengerId)
          .maybeSingle();

      return result != null;
    } catch (e) {
      developer.log('❌ Error checking review status: $e', name: 'Review');
      return false;
    }
  }

  /// Get reviews for a driver
  Future<List<Map<String, dynamic>>> getDriverReviews(String driverId) async {
    try {
      final reviews = await _supabase
          .from('ride_reviews')
          .select('*, profiles!ride_reviews_passenger_id_fkey(full_name, profile_picture_url)')
          .eq('driver_id', driverId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(reviews);
    } catch (e) {
      developer.log('❌ Error fetching driver reviews: $e', name: 'Review');
      return [];
    }
  }

  /// Get driver's average rating
  Future<DriverRating> getDriverRating(String driverId) async {
    try {
      final result = await _supabase
          .from('profiles')
          .select('driver_rating, total_reviews')
          .eq('id', driverId)
          .single();

      return DriverRating(
        averageRating: (result['driver_rating'] as num?)?.toDouble() ?? 0.0,
        totalReviews: result['total_reviews'] as int? ?? 0,
      );
    } catch (e) {
      developer.log('❌ Error fetching driver rating: $e', name: 'Review');
      return DriverRating(averageRating: 0.0, totalReviews: 0);
    }
  }
}

/// Driver rating data
class DriverRating {
  final double averageRating;
  final int totalReviews;

  DriverRating({
    required this.averageRating,
    required this.totalReviews,
  });
}

