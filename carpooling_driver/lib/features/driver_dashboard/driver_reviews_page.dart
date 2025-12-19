import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:carpooling_driver/core/utils/timezone_helper.dart';
import 'dart:developer' as developer;

/// Driver Reviews Page - View all ratings and reviews
class DriverReviewsPage extends StatefulWidget {
  const DriverReviewsPage({super.key});

  @override
  State<DriverReviewsPage> createState() => _DriverReviewsPageState();
}

class _DriverReviewsPageState extends State<DriverReviewsPage> {
  final _supabase = Supabase.instance.client;
  
  List<Map<String, dynamic>> _reviews = [];
  bool _isLoading = true;
  String? _errorMessage;
  double _averageRating = 0.0;
  int _totalReviews = 0;

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final driverId = _supabase.auth.currentUser?.id;
      if (driverId == null) {
        throw Exception('Not authenticated');
      }

      developer.log('📊 Loading reviews for driver: $driverId', name: 'DriverReviews');

      // Get all ratings for this driver
      final ratingsResponse = await _supabase
          .from('driver_ratings')
          .select('*')
          .eq('driver_id', driverId)
          .order('created_at', ascending: false);

      // Get passenger profiles separately
      final List<Map<String, dynamic>> reviewsWithPassengers = [];
      for (final rating in ratingsResponse) {
        final passengerId = rating['passenger_id'];
        final passengerProfile = await _supabase
            .from('profiles')
            .select('full_name, email, avatar_url')
            .eq('id', passengerId)
            .maybeSingle();

        reviewsWithPassengers.add({
          ...rating,
          'passenger': passengerProfile ?? {'full_name': 'Passenger', 'email': ''},
        });
      }

      // Calculate average rating
      double totalRating = 0.0;
      for (final review in reviewsWithPassengers) {
        totalRating += (review['rating'] as num?)?.toDouble() ?? 0.0;
      }
      final avgRating = reviewsWithPassengers.isEmpty ? 0.0 : totalRating / reviewsWithPassengers.length;

      developer.log('✅ Loaded ${reviewsWithPassengers.length} reviews, avg: ${avgRating.toStringAsFixed(2)}', name: 'DriverReviews');

      setState(() {
        _reviews = reviewsWithPassengers;
        _totalReviews = reviewsWithPassengers.length;
        _averageRating = avgRating;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      developer.log('❌ Error loading reviews: $e', name: 'DriverReviews', error: e, stackTrace: stackTrace);
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Reviews'),
        backgroundColor: Colors.amber,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildError()
              : _buildReviewsList(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Failed to load reviews',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadReviews,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewsList() {
    return Column(
      children: [
        // Summary Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.amber.shade400, Colors.amber.shade600],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            children: [
              const Icon(Icons.star, size: 64, color: Colors.white),
              const SizedBox(height: 12),
              Text(
                _averageRating.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return Icon(
                    index < _averageRating.round() ? Icons.star : Icons.star_border,
                    color: Colors.white,
                    size: 24,
                  );
                }),
              ),
              const SizedBox(height: 8),
              Text(
                '$_totalReviews ${_totalReviews == 1 ? 'Review' : 'Reviews'}',
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),

        // Reviews List
        Expanded(
          child: _reviews.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.rate_review, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text(
                        'No reviews yet',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Complete rides to get reviews from passengers!',
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _reviews.length,
                  itemBuilder: (context, index) {
                    final review = _reviews[index];
                    return _buildReviewCard(review);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildReviewCard(Map<String, dynamic> review) {
    final passenger = review['passenger'] as Map<String, dynamic>;
    final rating = (review['rating'] as num?)?.toDouble() ?? 0.0;
    final reviewText = review['review'] as String?;
    final createdAt = DateTime.parse(review['created_at'] as String);
    final malaysiaTime = TimezoneHelper.utcToMalaysia(createdAt);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Passenger info
            Row(
              children: [
                CircleAvatar(
                  backgroundImage: passenger['avatar_url'] != null
                      ? NetworkImage(passenger['avatar_url'])
                      : null,
                  child: passenger['avatar_url'] == null
                      ? const Icon(Icons.person)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        passenger['full_name'] ?? passenger['email'] ?? 'Passenger',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        TimezoneHelper.formatMalaysiaDateTime(malaysiaTime),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Rating stars
            Row(
              children: [
                ...List.generate(5, (index) {
                  return Icon(
                    index < rating ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                    size: 20,
                  );
                }),
                const SizedBox(width: 8),
                Text(
                  rating.toStringAsFixed(1),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),

            // Review text
            if (reviewText != null && reviewText.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  reviewText,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

