import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:carpooling_driver/features/ride_management/driver_ride_details_page.dart';
import 'package:carpooling_driver/core/utils/timezone_helper.dart';
import 'dart:developer' as developer;
import 'dart:async';

/// My Rides Page - Shows driver's created rides with tabs
class MyRidesPage extends HookConsumerWidget {
  const MyRidesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;

    if (userId == null) {
      return const Center(
        child: Text('Please log in to view your rides'),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('My Rides'),
          automaticallyImplyLeading: false,
          bottom: TabBar(
            indicatorColor: theme.colorScheme.primary,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.6),
            tabs: const [
              Tab(text: 'All'),
              Tab(text: 'Active'),
              Tab(text: 'Scheduled'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _AllRidesTab(userId: userId, supabase: supabase),
            _ActiveRidesTab(userId: userId, supabase: supabase),
            _ScheduledRidesTab(userId: userId, supabase: supabase),
          ],
        ),
      ),
    );
  }
}

/// All Rides Tab - Shows active, scheduled, and 5 most recent completed rides
class _AllRidesTab extends HookWidget {
  final String userId;
  final SupabaseClient supabase;

  const _AllRidesTab({required this.userId, required this.supabase});

  @override
  Widget build(BuildContext context) {
    final refreshKey = useState(0);
    final ridesSnapshot = useFuture(
      useMemoized(
        () => _fetchAllRides(supabase, userId),
        [userId, refreshKey.value],
      ),
    );

    return _RideListView(
      snapshot: ridesSnapshot,
      emptyMessage: 'No rides yet. Create your first ride!',
      onRefresh: () async {
        refreshKey.value++;
      },
    );
  }

  Future<List<Map<String, dynamic>>> _fetchAllRides(
    SupabaseClient supabase,
    String userId,
  ) async {
    // Fetch ALL rides (not cancelled), and sort by priority and time
    final response = await supabase
        .from('rides')
        .select()
        .eq('driver_id', userId)
        .neq('ride_status', 'cancelled')
        .order('scheduled_time', ascending: false);

    final allRides = List<Map<String, dynamic>>.from(response);

    // Separate completed and active/scheduled rides
    final completed = allRides.where((r) => r['ride_status'] == 'completed').toList();
    final active = allRides.where((r) => r['ride_status'] != 'completed').toList();
    
    // Sort active rides by priority
    active.sort((a, b) {
      final statusA = a['ride_status'] as String? ?? 'scheduled';
      final statusB = b['ride_status'] as String? ?? 'scheduled';
      
      // Define priority order
      int getPriority(String status) {
        switch (status) {
          case 'active':
            return 1;
          case 'scheduled':
            return 2;
          case 'in_progress':
            return 3;
          default:
            return 5;
        }
      }
      
      final priorityA = getPriority(statusA);
      final priorityB = getPriority(statusB);
      
      if (priorityA != priorityB) {
        return priorityA.compareTo(priorityB);
      }
      
      // If same priority, sort by time (newest first)
      final timeA = DateTime.parse(a['scheduled_time'] as String);
      final timeB = DateTime.parse(b['scheduled_time'] as String);
      return timeB.compareTo(timeA);
    });
    
    // Sort completed rides by time (newest first)
    completed.sort((a, b) {
      final timeA = DateTime.parse(a['scheduled_time'] as String);
      final timeB = DateTime.parse(b['scheduled_time'] as String);
      return timeB.compareTo(timeA);
    });
    
    // Take only 5 most recent completed rides
    final recentCompleted = completed.take(5).toList();
    
    // Combine: active rides first, then 5 most recent completed
    return [...active, ...recentCompleted];
  }
}

/// Active Rides Tab - Shows active and in_progress rides (NOT completed/expired)
class _ActiveRidesTab extends HookWidget {
  final String userId;
  final SupabaseClient supabase;

  const _ActiveRidesTab({required this.userId, required this.supabase});

  @override
  Widget build(BuildContext context) {
    final refreshKey = useState(0);
    final ridesSnapshot = useFuture(
      useMemoized(
        () => _fetchActiveRides(supabase, userId),
        [userId, refreshKey.value],
      ),
    );

    return _RideListView(
      snapshot: ridesSnapshot,
      emptyMessage: 'No active rides',
      onRefresh: () async {
        refreshKey.value++;
      },
    );
  }

  Future<List<Map<String, dynamic>>> _fetchActiveRides(
    SupabaseClient supabase,
    String userId,
  ) async {
    // Fetch rides with status = active OR in_progress
    // Don't filter by time - let the driver manage their rides
    final response = await supabase
        .from('rides')
        .select()
        .eq('driver_id', userId)
        .or('ride_status.eq.active,ride_status.eq.in_progress')
        .order('scheduled_time', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }
}

/// Scheduled Rides Tab - Shows only scheduled rides with future dates
class _ScheduledRidesTab extends HookWidget {
  final String userId;
  final SupabaseClient supabase;

  const _ScheduledRidesTab({required this.userId, required this.supabase});

  @override
  Widget build(BuildContext context) {
    final refreshKey = useState(0);
    final ridesSnapshot = useFuture(
      useMemoized(
        () => _fetchScheduledRides(supabase, userId),
        [userId, refreshKey.value],
      ),
    );

    return _RideListView(
      snapshot: ridesSnapshot,
      emptyMessage: 'No scheduled rides',
      onRefresh: () async {
        refreshKey.value++;
      },
    );
  }

  Future<List<Map<String, dynamic>>> _fetchScheduledRides(
    SupabaseClient supabase,
    String userId,
  ) async {
    final response = await supabase
        .from('rides')
        .select()
        .eq('driver_id', userId)
        .eq('ride_status', 'scheduled')
        .order('scheduled_time', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }
}

/// Reusable Ride List View Widget
class _RideListView extends StatelessWidget {
  final AsyncSnapshot<List<Map<String, dynamic>>> snapshot;
  final String emptyMessage;
  final Future<void> Function() onRefresh;

  // Helper method to sort rides
  List<Map<String, dynamic>> _sortRides(List<Map<String, dynamic>> rides) {
    final completed = rides.where((r) => r['ride_status'] == 'completed').toList();
    final active = rides.where((r) => r['ride_status'] != 'completed').toList();
    
    // Sort active rides by priority
    active.sort((a, b) {
      final statusA = a['ride_status'] as String? ?? 'scheduled';
      final statusB = b['ride_status'] as String? ?? 'scheduled';
      
      int getPriority(String status) {
        switch (status) {
          case 'active':
            return 1;
          case 'scheduled':
            return 2;
          case 'in_progress':
            return 3;
          default:
            return 5;
        }
      }
      
      final priorityA = getPriority(statusA);
      final priorityB = getPriority(statusB);
      
      if (priorityA != priorityB) {
        return priorityA.compareTo(priorityB);
      }
      
      final timeA = DateTime.parse(a['scheduled_time'] as String);
      final timeB = DateTime.parse(b['scheduled_time'] as String);
      return timeB.compareTo(timeA);
    });
    
    completed.sort((a, b) {
      final timeA = DateTime.parse(a['scheduled_time'] as String);
      final timeB = DateTime.parse(b['scheduled_time'] as String);
      return timeB.compareTo(timeA);
    });
    
    return [...active, ...completed.take(5)];
  }

  const _RideListView({
    required this.snapshot,
    required this.emptyMessage,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
            ElevatedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final allRides = snapshot.data ?? [];
    final rides = _sortRides(allRides);

    if (rides.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.route_outlined,
              size: 80,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              emptyMessage,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: rides.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _RideCard(ride: rides[index]),
          );
        },
      ),
    );
  }
}

/// Ride Card Widget with real data
class _RideCard extends HookWidget {
  final Map<String, dynamic> ride;

  const _RideCard({required this.ride});

  Future<double> _calculateTotalEarnings(SupabaseClient supabase, String rideId) async {
    try {
      // Get all accepted bookings with their individual fares
      final bookings = await supabase
          .from('bookings')
          .select('fare_per_seat, seats_requested, total_price')
          .eq('ride_id', rideId)
          .or('request_status.eq.accepted,request_status.eq.completed');
      
      // Calculate total: sum of each passenger's fare
      // Each passenger has their own fare based on pickup/dropoff location
      double total = 0.0;
      for (final booking in bookings) {
        // First try total_price (if available), otherwise calculate from fare_per_seat
        final totalPrice = (booking['total_price'] as num?)?.toDouble();
        if (totalPrice != null && totalPrice > 0) {
          total += totalPrice;
        } else {
          final farePerSeat = (booking['fare_per_seat'] as num?)?.toDouble() ?? 0.0;
          final seatsRequested = (booking['seats_requested'] as int?) ?? 1;
          // Total fare for this passenger = fare_per_seat × seats_requested
          total += farePerSeat * seatsRequested;
        }
      }
      return total;
    } catch (e) {
      developer.log('Error calculating total earnings: $e', name: 'MyRidesPage');
      return 0.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final supabase = Supabase.instance.client;
    
    // Extract ride data
    final from = ride['from_location'] as String;
    final to = ride['to_location'] as String;
    final scheduledTimeUtc = DateTime.parse(ride['scheduled_time'] as String).toUtc();
    final scheduledTime = TimezoneHelper.utcToMalaysia(scheduledTimeUtc); // Convert to Malaysia time
    final availableSeats = ride['available_seats'] as int;
    final distance = ride['calculated_distance_km'] as num?;
    final duration = ride['calculated_duration_minutes'] as int?;
    final rideStatus = ride['ride_status'] as String? ?? 'scheduled';
    final rideId = ride['id'] as String;
    
    // For completed rides, fetch total earnings
    final earningsFuture = useMemoized(
      () => rideStatus == 'completed' ? _calculateTotalEarnings(supabase, rideId) : Future.value(0.0),
      [rideId, rideStatus],
    );
    final earningsSnapshot = useFuture(earningsFuture);
    
    // Format date in Malaysia timezone
    final now = TimezoneHelper.nowInMalaysia();
    final isToday = scheduledTime.year == now.year &&
        scheduledTime.month == now.month &&
        scheduledTime.day == now.day;
    final isTomorrow = scheduledTime.difference(now).inDays == 0 &&
        scheduledTime.day == now.day + 1;
    
    String dateStr;
    if (isToday) {
      dateStr = 'Today, ${TimezoneHelper.formatMalaysiaTime(scheduledTime)}';
    } else if (isTomorrow) {
      dateStr = 'Tomorrow, ${TimezoneHelper.formatMalaysiaTime(scheduledTime)}';
    } else {
      dateStr = TimezoneHelper.formatMalaysiaDateTime(scheduledTime);
    }
    
    // Determine status and color - Use actual database status
    String status;
    Color statusColor;
    
    switch (rideStatus) {
      case 'scheduled':
        status = 'SCHEDULED';
        statusColor = Colors.blue;
        break;
      case 'active':
        status = 'ACTIVE';
        statusColor = Colors.green;
        break;
      case 'in_progress':
        status = 'IN PROGRESS';
        statusColor = Colors.orange;
        break;
      case 'completed':
        status = 'COMPLETED';
        statusColor = Colors.grey;
        break;
      default:
        status = rideStatus.toUpperCase();
        statusColor = Colors.grey;
    }
    
    return Card(
      child: InkWell(
        onTap: () {
          // Navigate to ride details page with real-time passenger list
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DriverRideDetailsPage(
                rideId: ride['id'] as String,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  rideStatus == 'completed'
                      ? (earningsSnapshot.hasData
                          ? Text(
                              'Total Earnings: RM ${earningsSnapshot.data!.toStringAsFixed(2)}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            )
                          : const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ))
                      : StreamBuilder<List<Map<String, dynamic>>>(
                          stream: supabase
                              .from('bookings')
                              .stream(primaryKey: ['id'])
                              .eq('ride_id', rideId)
                              .order('requested_at', ascending: false),
                          builder: (context, bookingSnapshot) {
                            // Filter for accepted/completed bookings
                            final acceptedBookings = bookingSnapshot.data?.where((b) {
                              final status = b['request_status'] as String?;
                              return status == 'accepted' || status == 'completed';
                            }).toList() ?? [];
                            
                            final bookingCount = acceptedBookings.length;
                            
                            if (bookingCount > 0) {
                              // Calculate total seats booked
                              int totalSeatsBooked = 0;
                              for (final booking in acceptedBookings) {
                                totalSeatsBooked += (booking['seats_booked'] as int? ?? 1);
                              }
                              
                              final totalSeats = ride['available_seats'] as int? ?? 0;
                              final originalSeats = totalSeats + totalSeatsBooked; // Calculate original seats
                              
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '$bookingCount Passenger${bookingCount != 1 ? 's' : ''}',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                  Text(
                                    '$totalSeatsBooked / $originalSeats seats',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.grey,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              );
                            }
                            return Text(
                              'No bookings yet',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.grey,
                              ),
                            );
                          },
                        ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.trip_origin, size: 16, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      from,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 16, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      to,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 14,
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        dateStr,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.event_seat,
                        size: 14,
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$availableSeats seat${availableSeats != 1 ? 's' : ''} available',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  if (distance != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.straighten,
                          size: 14,
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${distance.toStringAsFixed(1)} km',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  if (duration != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.schedule,
                          size: 14,
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$duration min',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

