import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:developer' as developer;

/// Driver Ride History Page
/// Shows past completed rides with earnings
class DriverRideHistoryPage extends StatefulWidget {
  const DriverRideHistoryPage({super.key});

  @override
  State<DriverRideHistoryPage> createState() => _DriverRideHistoryPageState();
}

class _DriverRideHistoryPageState extends State<DriverRideHistoryPage> {
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
          .from('driver_ride_history')
          .select()
          .eq('driver_id', userId)
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
        backgroundColor: Colors.green,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _rideHistory.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: [
                    // Summary Card
                    if (_rideHistory.isNotEmpty) _buildSummaryCard(),
                    
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

  Widget _buildSummaryCard() {
    final totalEarnings = _rideHistory.fold<double>(
      0.0,
      (sum, ride) => sum + ((ride['total_earnings'] as num?) ?? 0).toDouble(),
    );
    final totalRides = _rideHistory.length;
    final completedRides = _rideHistory
        .where((r) => r['ride_status'] == 'completed')
        .length;

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildSummaryStat(
              'Total Rides',
              totalRides.toString(),
              Icons.directions_car,
            ),
            _buildSummaryStat(
              'Completed',
              completedRides.toString(),
              Icons.check_circle,
            ),
            _buildSummaryStat(
              'Earnings',
              'RM ${totalEarnings.toStringAsFixed(2)}',
              Icons.payments,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.green.shade700, size: 32),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }

  Widget _buildRideCard(Map<String, dynamic> ride) {
    final theme = Theme.of(context);
    final completedAt = ride['completed_at'] != null
        ? DateTime.parse(ride['completed_at'] as String)
        : DateTime.parse(ride['scheduled_time'] as String);
    final status = ride['ride_status'] as String;
    final passengersCount = ride['passengers_count'] as int? ?? 0;
    final paidCount = ride['paid_count'] as int? ?? 0;
    final totalEarnings = (ride['total_earnings'] as num?)?.toDouble() ?? 0.0;

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
                  _buildStatusChip(status),
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
                      const Icon(Icons.people, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        '$passengersCount passenger${passengersCount != 1 ? 's' : ''}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.payment,
                        size: 16,
                        color: paidCount == passengersCount
                            ? Colors.green
                            : Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$paidCount/$passengersCount paid',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: paidCount == passengersCount
                              ? Colors.green
                              : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'RM ${totalEarnings.toStringAsFixed(2)}',
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

  Widget _buildStatusChip(String status) {
    Color bgColor;
    Color textColor;

    if (status == 'completed') {
      bgColor = Colors.green.shade50;
      textColor = Colors.green.shade700;
    } else if (status == 'cancelled') {
      bgColor = Colors.red.shade50;
      textColor = Colors.red.shade700;
    } else {
      bgColor = Colors.grey.shade200;
      textColor = Colors.grey.shade700;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.toUpperCase(),
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
              _buildDetailRow('Date', DateFormat('MMM dd, yyyy HH:mm').format(
                DateTime.parse(ride['scheduled_time'] as String),
              )),
              _buildDetailRow('From', ride['from_location'] ?? 'N/A'),
              _buildDetailRow('To', ride['to_location'] ?? 'N/A'),
              _buildDetailRow('Status', ride['ride_status'].toString().toUpperCase()),
              _buildDetailRow('Passengers', '${ride['passengers_count']}'),
              _buildDetailRow('Paid', '${ride['paid_count']}/${ride['passengers_count']}'),
              _buildDetailRow(
                'Earnings',
                'RM ${((ride['total_earnings'] as num?) ?? 0).toStringAsFixed(2)}',
              ),
              if (ride['completed_at'] != null)
                _buildDetailRow(
                  'Completed At',
                  DateFormat('MMM dd, yyyy HH:mm').format(
                    DateTime.parse(ride['completed_at'] as String),
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

