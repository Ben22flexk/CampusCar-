import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:carpooling_main/core/utils/timezone_helper.dart';
import 'dart:developer' as developer;

/// Passenger Ride History Page
/// Shows past completed rides with payment status
class RideHistoryPage extends StatefulWidget {
  const RideHistoryPage({super.key});

  @override
  State<RideHistoryPage> createState() => _RideHistoryPageState();
}

class _RideHistoryPageState extends State<RideHistoryPage> {
  final _supabase = Supabase.instance.client;
  
  List<Map<String, dynamic>> _rideHistory = [];
  bool _isLoading = true;
  bool _showAll = false;
  
  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      setState(() => _isLoading = true);

      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Not authenticated');
      }

      // Get ride history from view
      final response = await _supabase
          .from('passenger_ride_history')
          .select()
          .eq('passenger_id', userId)
          .limit(_showAll ? 100 : 10);

      setState(() {
        _rideHistory = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      developer.log('Error loading ride history: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ride History'),
        backgroundColor: Colors.blue,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _rideHistory.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _rideHistory.length,
                        itemBuilder: (context, index) {
                          return _buildRideCard(_rideHistory[index]);
                        },
                      ),
                    ),
                    if (_rideHistory.length >= 10 && !_showAll)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: TextButton(
                          onPressed: () {
                            setState(() => _showAll = true);
                            _loadHistory();
                          },
                          child: const Text('See All History'),
                        ),
                      ),
                  ],
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No ride history yet',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.grey,
                ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your completed rides will appear here',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildRideCard(Map<String, dynamic> ride) {
    final theme = Theme.of(context);
    final completedAtUtc = ride['completed_at'] != null
        ? DateTime.parse(ride['completed_at'] as String).toUtc()
        : DateTime.parse(ride['scheduled_time'] as String).toUtc();
    final completedAt = TimezoneHelper.utcToMalaysia(completedAtUtc);
    final paymentStatus = ride['payment_status'] as String? ?? 'pending';
    final rideEnded = ride['ride_ended_by_passenger'] as bool? ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: InkWell(
        onTap: () => _showRideDetails(ride),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Date and Status
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    DateFormat('MMM dd, yyyy').format(completedAt),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  _buildStatusChip(paymentStatus, rideEnded),
                ],
              ),
              const Divider(height: 24),
              
              // Route
              Row(
                children: [
                  Column(
                    children: [
                      Icon(Icons.circle, size: 12, color: Colors.green.shade700),
                      Container(
                        width: 2,
                        height: 24,
                        color: Colors.grey.shade400,
                      ),
                      Icon(Icons.location_on, size: 16, color: Colors.red.shade700),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ride['from_location'] ?? 'N/A',
                          style: theme.textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          ride['to_location'] ?? 'N/A',
                          style: theme.textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const Divider(height: 24),
              
              // Bottom Info
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundImage: ride['driver_avatar_url'] != null
                            ? NetworkImage(ride['driver_avatar_url'])
                            : null,
                        child: ride['driver_avatar_url'] == null
                            ? const Icon(Icons.person, size: 12)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        ride['driver_name'] ?? 'N/A',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  Text(
                    'RM ${(((ride['fare_amount'] ?? ride['total_price']) as num?) ?? 0).toStringAsFixed(2)}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(String paymentStatus, bool rideEnded) {
    Color bgColor;
    Color textColor;
    String label;

    if (rideEnded) {
      bgColor = Colors.green.shade50;
      textColor = Colors.green.shade700;
      label = 'COMPLETED';
    } else if (paymentStatus == 'paid_cash' || paymentStatus == 'paid_tng') {
      bgColor = Colors.blue.shade50;
      textColor = Colors.blue.shade700;
      label = 'PAID';
    } else {
      bgColor = Colors.orange.shade50;
      textColor = Colors.orange.shade700;
      label = 'PENDING';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }

  void _showRideDetails(Map<String, dynamic> ride) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ride Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Date', TimezoneHelper.formatMalaysiaDateTime(
                TimezoneHelper.utcToMalaysia(
                  DateTime.parse(ride['scheduled_time'] as String).toUtc(),
                ),
              )),
              _buildDetailRow('From', ride['from_location'] ?? 'N/A'),
              _buildDetailRow('To', ride['to_location'] ?? 'N/A'),
              _buildDetailRow('Driver', ride['driver_name'] ?? 'N/A'),
              if (ride['vehicle_plate'] != null && ride['vehicle_plate'] != 'Not specified')
                _buildDetailRow(
                  'Vehicle',
                  '${ride['vehicle_model'] ?? 'N/A'} (${ride['vehicle_plate']})',
                ),
              _buildDetailRow('Seats', '${ride['seats_booked']}'),
              _buildDetailRow(
                'Price',
                'RM ${(((ride['fare_amount'] ?? ride['total_price']) as num?) ?? 0).toStringAsFixed(2)}',
              ),
              _buildDetailRow(
                'Payment',
                ride['payment_status']?.toString().toUpperCase() ?? 'PENDING',
              ),
              if (ride['payment_method'] != null)
                _buildDetailRow(
                  'Method',
                  ride['payment_method'].toString().toUpperCase(),
                ),
              if (ride['ride_ended_by_passenger'] == true)
                _buildDetailRow(
                  'Completed At',
                  TimezoneHelper.formatMalaysiaDateTime(
                    TimezoneHelper.utcToMalaysia(
                      DateTime.parse(ride['ride_ended_at'] as String).toUtc(),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
