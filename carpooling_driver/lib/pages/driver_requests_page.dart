import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:carpooling_driver/services/ride_request_service.dart';
import 'package:carpooling_driver/pages/chat_page.dart';
import 'dart:developer' as developer;

/// Driver page to view and respond to ride requests
class DriverRequestsPage extends HookWidget {
  const DriverRequestsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final requestService = RideRequestService();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ride Requests'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // Triggers rebuild with new stream
              (context as Element).markNeedsBuild();
            },
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: requestService.getMyRideRequests(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      (context as Element).markNeedsBuild();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final requests = snapshot.data ?? [];

          if (requests.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inbox_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No Ride Requests',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Requests from passengers will appear here',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final request = requests[index];
              return _RequestCard(
                request: request,
                requestService: requestService,
              );
            },
          );
        },
      ),
    );
  }
}

class _RequestCard extends HookWidget {
  final Map<String, dynamic> request;
  final RideRequestService requestService;

  const _RequestCard({
    required this.request,
    required this.requestService,
  });

  @override
  Widget build(BuildContext context) {
    final isProcessing = useState(false);
    final theme = Theme.of(context);

    final bookingId = request['booking_id'] as String;
    final passengerId = request['passenger_id'] as String;
    final passengerName = request['passenger_name'] as String;
    final passengerEmail = request['passenger_email'] as String?;
    final seatsBooked = request['seats_booked'] as int;
    final totalPrice = request['total_price'] as num?;
    final requestStatus = request['request_status'] as String;
    final fromLocation = request['from_location'] as String;
    final toLocation = request['to_location'] as String;
    final requestedAt = DateTime.parse(request['requested_at'] as String);

    // Only show pending requests prominently
    final isPending = requestStatus == 'pending';
    
    Color statusColor;
    IconData statusIcon;
    
    switch (requestStatus) {
      case 'pending':
        statusColor = Colors.orange;
        statusIcon = Icons.pending;
        break;
      case 'accepted':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'rejected':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help;
    }

    Future<void> respondToRequest(bool accept) async {
      isProcessing.value = true;
      try {
        await requestService.respondToRequest(
          bookingId: bookingId,
          accept: accept,
        );

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                accept
                    ? '✅ Request accepted!'
                    : '❌ Request rejected',
              ),
              backgroundColor: accept ? Colors.green : Colors.orange,
            ),
          );
        }
      } catch (e) {
        developer.log('❌ Error responding to request: $e', name: 'DriverRequests');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        isProcessing.value = false;
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: isPending ? 4 : 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Passenger Info
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    passengerName.isNotEmpty
                        ? passengerName[0].toUpperCase()
                        : 'P',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        passengerName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (passengerEmail != null)
                        Text(
                          passengerEmail,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.message),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatPage(
                          otherUserId: passengerId,
                          otherUserName: passengerName,
                          rideId: request['ride_id'] as String?,
                        ),
                      ),
                    );
                  },
                  tooltip: 'Message Passenger',
                ),
              ],
            ),
            const Divider(height: 24),

            // Request Details
            _InfoRow(
              icon: Icons.event_seat,
              label: 'Seats Requested',
              value: '$seatsBooked',
            ),
            const SizedBox(height: 8),
            if (totalPrice != null) ...[
              _InfoRow(
                icon: Icons.payments,
                label: 'Total Price',
                value: 'RM ${totalPrice.toStringAsFixed(2)}',
              ),
              const SizedBox(height: 8),
            ],
            _InfoRow(
              icon: Icons.trip_origin,
              label: 'From',
              value: fromLocation,
            ),
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.location_on,
              label: 'To',
              value: toLocation,
            ),
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.access_time,
              label: 'Requested',
              value: _formatDateTime(requestedAt),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(statusIcon, size: 20, color: statusColor),
                const SizedBox(width: 8),
                Text(
                  'Status: ${requestStatus.toUpperCase()}',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            // Action Buttons (only for pending requests)
            if (isPending) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: isProcessing.value
                          ? null
                          : () => respondToRequest(false),
                      icon: const Icon(Icons.close),
                      label: const Text('Reject'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: isProcessing.value
                          ? null
                          : () => respondToRequest(true),
                      icon: isProcessing.value
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check),
                      label: const Text('Accept'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final difference = now.difference(dt);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${dt.day}/${dt.month}/${dt.year}';
    }
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 14,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}

