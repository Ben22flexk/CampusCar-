import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:carpooling_main/find_carpool.dart';
import 'package:carpooling_main/profile.dart';
import 'package:carpooling_main/pages/ride_details_page.dart' as ride_details;
import 'package:carpooling_main/pages/ride_history_page.dart';
import 'package:carpooling_main/pages/emergency_contacts_page.dart';
import 'package:carpooling_main/features/notifications/presentation/widgets/notification_badge.dart';
import 'package:carpooling_main/features/notifications/presentation/pages/notifications_page.dart';
import 'package:carpooling_main/core/utils/timezone_helper.dart';

// Data Models
@immutable
class PassengerStats {
  final int todayRides;
  final int weekRides;
  final int monthRides;
  final int upcomingRides;

  const PassengerStats({
    required this.todayRides,
    required this.weekRides,
    required this.monthRides,
    required this.upcomingRides,
  });
}

// Providers
final passengerStatsProvider = StreamProvider<PassengerStats>((ref) async* {
  final supabase = Supabase.instance.client;
  final userId = supabase.auth.currentUser?.id;
  
  if (userId == null) {
    yield const PassengerStats(
      todayRides: 0,
      weekRides: 0,
      monthRides: 0,
      upcomingRides: 0,
    );
    return;
  }

  // Stream updates every time bookings change
  final stream = supabase
      .from('bookings')
      .stream(primaryKey: ['id'])
      .eq('passenger_id', userId);

  await for (final _ in stream) {
    try {
      final now = TimezoneHelper.nowInMalaysia();
      final todayStart = DateTime(now.year, now.month, now.day);
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final monthStart = DateTime(now.year, now.month, 1);

      // Count rides from ride_history (completed rides)
      final todayRides = await supabase
          .from('ride_history')
          .select()
          .eq('passenger_id', userId)
          .gte('completed_at', todayStart.toUtc().toIso8601String());

      final weekRides = await supabase
          .from('ride_history')
          .select()
          .eq('passenger_id', userId)
          .gte('completed_at', weekStart.toUtc().toIso8601String());

      final monthRides = await supabase
          .from('ride_history')
          .select()
          .eq('passenger_id', userId)
          .gte('completed_at', monthStart.toUtc().toIso8601String());

      // Count upcoming accepted rides
      final upcomingRides = await supabase
          .from('bookings')
          .select()
          .eq('passenger_id', userId)
          .eq('request_status', 'accepted');

      yield PassengerStats(
        todayRides: todayRides.length,
        weekRides: weekRides.length,
        monthRides: monthRides.length,
        upcomingRides: upcomingRides.length,
      );
    } catch (e) {
      print('Error fetching stats: $e');
      yield const PassengerStats(
        todayRides: 0,
        weekRides: 0,
        monthRides: 0,
        upcomingRides: 0,
      );
    }
  }
});

@immutable
class PassengerRequest {
  final String id;
  final String pickup;
  final String dropoff;
  final DateTime dateTime;
  final String status;
  final String? driverName;
  final String? driverAvatar;

  const PassengerRequest({
    required this.id,
    required this.pickup,
    required this.dropoff,
    required this.dateTime,
    required this.status,
    this.driverName,
    this.driverAvatar,
  });
}

final passengerRequestsProvider = StreamProvider<List<PassengerRequest>>((ref) async* {
  final supabase = Supabase.instance.client;
  final userId = supabase.auth.currentUser?.id;
  
  if (userId == null) {
    print('⚠️ Dashboard: No user ID, returning empty requests');
    yield [];
    return;
  }

  print('✅ Dashboard: Fetching ride requests for user: $userId');

  // Stream from bookings table for current user's requests
  // Show ALL requests: pending, accepted, declined (not completed/cancelled)
  final stream = supabase
      .from('bookings')
      .stream(primaryKey: ['id'])
      .eq('passenger_id', userId)
      .order('requested_at', ascending: false);

  await for (final bookings in stream) {
    print('📋 Dashboard: Received ${bookings.length} bookings from stream');
    final List<PassengerRequest> requests = [];
    
    for (final booking in bookings) {
      // Fetch ride details for each booking
      try {
        final bookingStatus = booking['request_status'] ?? 'pending';
        final rideId = booking['ride_id'];
        
        print('  - Booking ${booking['id']}: status=$bookingStatus, ride=$rideId');
        
        final ride = await supabase
            .from('rides')
            .select('*')
            .eq('id', rideId)
            .maybeSingle();
        
        if (ride != null) {
          final scheduledTime = DateTime.parse(ride['scheduled_time']);
          final malaysiaTime = TimezoneHelper.utcToMalaysia(scheduledTime);
          final rideStatus = ride['ride_status'] ?? 'active';
          final driverId = ride['driver_id'] as String?;
          
          print('    ✓ Ride found: ${ride['from_location']} → ${ride['to_location']}, status=$rideStatus');
          
          // Show all active/scheduled requests (not completed/cancelled rides)
          if (rideStatus != 'completed' && rideStatus != 'cancelled') {
            // Fetch driver profile separately
            String? driverName;
            String? driverAvatar;
            
            if (driverId != null) {
              try {
                final driverProfile = await supabase
                    .from('profiles')
                    .select('full_name, email, avatar_url')
                    .eq('id', driverId)
                    .maybeSingle();
                
                if (driverProfile != null) {
                  driverName = driverProfile['full_name'] as String? ?? driverProfile['email'] as String?;
                  driverAvatar = driverProfile['avatar_url'] as String?;
                }
              } catch (e) {
                print('    ⚠️ Could not fetch driver profile: $e');
              }
            }
            
            requests.add(PassengerRequest(
              id: booking['id'],
              pickup: booking['pickup_location'] ?? ride['from_location'] ?? 'Pickup Location',
              dropoff: booking['destination'] ?? ride['to_location'] ?? 'Dropoff Location',
              dateTime: malaysiaTime,
              status: bookingStatus,
              driverName: driverName,
              driverAvatar: driverAvatar,
            ));
          } else {
            print('    ✗ Skipping completed/cancelled ride');
          }
        } else {
          print('    ✗ Ride not found');
        }
      } catch (e) {
        print('    ❌ Error processing booking: $e');
        continue;
      }
    }
    
    print('✅ Dashboard: Yielding ${requests.length} requests');
    yield requests;
  }
});

final userLocationProvider = StreamProvider<Position?>((ref) async* {
  try {
    final hasPermission = await _checkLocationPermission();
    if (!hasPermission) {
      yield null;
      return;
    }

    yield* Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    );
  } catch (e) {
    yield null;
  }
});

Future<bool> _checkLocationPermission() async {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    return false;
  }

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      return false;
    }
  }

  if (permission == LocationPermission.deniedForever) {
    return false;
  }

  return true;
}

// Main Dashboard Page
class MainDashboardPage extends HookConsumerWidget {
  const MainDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(passengerStatsProvider);
    final requestsAsync = ref.watch(passengerRequestsProvider);
    final locationAsync = ref.watch(userLocationProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: <Widget>[
            const Icon(Icons.directions_car),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'CampusCar',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Text(
                  'Dashboard',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
        actions: <Widget>[
          Container(
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.red.shade200, width: 2),
            ),
            child: NotificationBadge(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const NotificationsPage(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ProfilePage(),
                  ),
                );
              },
              child: CircleAvatar(
                radius: 18,
                backgroundImage: ref.watch(userProfileProvider).photoUrl != null
                    ? NetworkImage(ref.watch(userProfileProvider).photoUrl!)
                    : null,
                child: ref.watch(userProfileProvider).photoUrl == null
                    ? const Icon(Icons.person, size: 18)
                    : null,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _StatsSummary(statsAsync: statsAsync),
            const SizedBox(height: 24),
            _LiveMapSection(locationAsync: locationAsync),
            const SizedBox(height: 24),
            _RequestsSection(requestsAsync: requestsAsync),
            const SizedBox(height: 24),
            const _SafetySection(),
            const SizedBox(height: 80),
          ],
        ),
      ),
      bottomNavigationBar: const _BottomActions(),
    );
  }
}

// Stats Summary
class _StatsSummary extends StatelessWidget {
  final AsyncValue<PassengerStats> statsAsync;

  const _StatsSummary({required this.statsAsync});

  @override
  Widget build(BuildContext context) {
    return statsAsync.when(
      data: (stats) => Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _StatCard(
                  label: 'Rides Today',
                  count: stats.todayRides,
                  icon: Icons.today,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'This Week',
                  count: stats.weekRides,
                  icon: Icons.date_range,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: _StatCard(
                  label: 'This Month',
                  count: stats.monthRides,
                  icon: Icons.calendar_month,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'Upcoming',
                  count: stats.upcomingRides,
                  icon: Icons.event_available,
                  color: Colors.purple,
                ),
              ),
            ],
          ),
        ],
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const SizedBox(),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              '$count',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// Live Map Section
class _LiveMapSection extends HookConsumerWidget {
  final AsyncValue<Position?> locationAsync;

  const _LiveMapSection({required this.locationAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mapController = useState<MapController>(MapController());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Your Location',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        locationAsync.when(
          data: (position) {
            if (position == null) {
              return Card(
                child: Container(
                  height: 250,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        Icons.location_off,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Location permission required',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: () async {
                          await Geolocator.requestPermission();
                        },
                        icon: const Icon(Icons.location_on),
                        label: const Text('Enable Location'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final userLatLng = LatLng(position.latitude, position.longitude);

            return SizedBox(
              height: 250,
              child: Card(
                clipBehavior: Clip.antiAlias,
                elevation: 2,
                child: FlutterMap(
                  mapController: mapController.value,
                  options: MapOptions(
                    initialCenter: userLatLng,
                    initialZoom: 15.0,
                    minZoom: 10.0,
                    maxZoom: 18.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.carpooling_main',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: userLatLng,
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.my_location,
                            color: Colors.blue,
                            size: 40,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
          loading: () => Card(
            child: Container(
              height: 250,
              alignment: Alignment.center,
              child: const CircularProgressIndicator(),
            ),
          ),
          error: (_, __) => Card(
            child: Container(
              height: 250,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Unable to get location',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Requests Section
class _RequestsSection extends StatelessWidget {
  final AsyncValue<List<PassengerRequest>> requestsAsync;

  const _RequestsSection({required this.requestsAsync});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'My Ride Requests',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'LIVE',
                style: TextStyle(
                  color: Colors.blue.shade900,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        requestsAsync.when(
          data: (requests) {
            print('🎨 Dashboard UI: Rendering ${requests.length} requests');
            if (requests.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No pending requests',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
                ),
              );
            }
            return Column(
              children: requests
                  .map((request) => _PassengerRequestCard(request: request))
                  .toList(),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const SizedBox(),
        ),
      ],
    );
  }
}

class _PassengerRequestCard extends StatelessWidget {
  final PassengerRequest request;

  const _PassengerRequestCard({required this.request});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = request.status == 'accepted'
        ? Colors.green
        : request.status == 'rejected'
            ? Colors.red
            : Colors.orange;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () async {
          // Fetch full ride details to navigate properly
          try {
            final supabase = Supabase.instance.client;
            
            // Get ride_id from booking
            final booking = await supabase
                .from('bookings')
                .select('ride_id')
                .eq('id', request.id)
                .single();
            
            final rideId = booking['ride_id'] as String;
            
            // Get driver_id from ride
            final ride = await supabase
                .from('rides')
                .select('driver_id')
                .eq('id', rideId)
                .single();
            
            final driverId = ride['driver_id'] as String;
            
            // Navigate to ride details
            if (context.mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ride_details.RideDetailsPage(
                    rideId: rideId,
                    driverId: driverId,
                  ),
                ),
              );
            }
          } catch (e) {
            print('❌ Error navigating to ride details: $e');
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Failed to load ride details: ${e.toString()}'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${request.dateTime.day}/${request.dateTime.month}/${request.dateTime.year} at ${request.dateTime.hour}:${request.dateTime.minute.toString().padLeft(2, '0')}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      request.status.toUpperCase(),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                const Icon(Icons.location_on, size: 16, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    request.pickup,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                const Icon(Icons.flag, size: 16, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    request.dropoff,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            if (request.driverName != null) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 16,
                    backgroundImage: request.driverAvatar != null
                        ? NetworkImage(request.driverAvatar!)
                        : null,
                    backgroundColor: Colors.grey.shade300,
                    child: request.driverAvatar == null
                        ? const Icon(Icons.person, size: 16)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Driver: ${request.driverName}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        ),
      ),
    );
  }
}

// Bottom Actions
class _BottomActions extends StatelessWidget {
  const _BottomActions();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const FindCarpoolPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.search, size: 20),
                label: const Text('Find a Carpool'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const RideHistoryPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.history, size: 18),
                label: const Text('Ride History'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Safety & SOS quick access section on dashboard
class _SafetySection extends StatelessWidget {
  const _SafetySection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Safety & SOS',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'During a live ride, you can trigger SOS from the '
                        'live tracking screen. Keep your emergency contacts '
                        'up to date here.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const EmergencyContactsPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.contact_phone, size: 18),
                label: const Text('Emergency Contacts & SOS Setup'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  foregroundColor: Colors.red,
                  side: BorderSide(color: Colors.red.shade200),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

