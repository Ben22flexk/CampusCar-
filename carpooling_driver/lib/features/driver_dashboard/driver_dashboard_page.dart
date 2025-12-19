import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:carpooling_driver/features/notifications/presentation/widgets/notification_badge.dart';
import 'package:carpooling_driver/features/notifications/presentation/pages/notifications_page.dart';
import 'package:carpooling_driver/features/ride_management/create_ride_page_v2.dart';
import 'package:carpooling_driver/features/ride_management/my_rides_page.dart';
import 'package:carpooling_driver/features/profile/driver_profile_page.dart';
import 'package:carpooling_driver/services/auth_service.dart';
import 'package:carpooling_driver/services/driver_verification_service.dart';
import 'package:carpooling_driver/services/driver_dashboard_service.dart';
import 'package:carpooling_driver/features/driver_verification/driver_verification_page.dart';
import 'package:carpooling_driver/features/driver_dashboard/driver_reviews_page.dart';
import 'package:carpooling_driver/features/reports/driver_reports_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:carpooling_driver/core/utils/timezone_helper.dart';

/// Driver Dashboard - Main page for drivers
class DriverDashboardPage extends ConsumerStatefulWidget {
  const DriverDashboardPage({super.key});

  @override
  ConsumerState<DriverDashboardPage> createState() => _DriverDashboardPageState();
}

class _DriverDashboardPageState extends ConsumerState<DriverDashboardPage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authService = AuthService();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.local_taxi),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CampusCar',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Driver Dashboard',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
        actions: [
          NotificationBadge(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NotificationsPage(),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DriverProfilePage(),
                  ),
                );
              },
              child: CircleAvatar(
                radius: 18,
                backgroundColor: theme.colorScheme.primary,
                child: Text(
                  authService.userFullName.isNotEmpty
                      ? authService.userFullName[0].toUpperCase()
                      : 'D',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _getSelectedPage(),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CreateRidePageV2(),
                  ),
                );
              },
              icon: const Icon(Icons.add_road),
              label: const Text('Create Ride'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route),
            label: 'My Rides',
          ),
          NavigationDestination(
            icon: Icon(Icons.attach_money_outlined),
            selectedIcon: Icon(Icons.attach_money),
            label: 'Earnings',
          ),
        ],
      ),
    );
  }

  Widget _getSelectedPage() {
    switch (_selectedIndex) {
      case 0:
        return const _DashboardOverview();
      case 1:
        return const MyRidesPage();
      case 2:
        return const _EarningsPage();
      default:
        return const _DashboardOverview();
    }
  }
}

/// Dashboard Overview Widget
class _DashboardOverview extends ConsumerWidget {
  const _DashboardOverview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dashboardService = DriverDashboardService();

    return StreamBuilder<DashboardStats>(
      stream: dashboardService.watchDashboardStats(),
      builder: (context, snapshot) {
        // Show centered loading indicator on initial load
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading dashboard...'),
              ],
            ),
          );
        }

        final stats = snapshot.data ?? DashboardStats.empty();
        final isLoading = !snapshot.hasData;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Verification Status Banner
            const _VerificationStatusBanner(),
            const SizedBox(height: 16),
            
            // Stats Cards (original layout - prevents Grid fixed-height overflows)
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    title: 'Today',
                    value: isLoading ? '-' : '${stats.todayRides}',
                    subtitle: 'Rides',
                    icon: Icons.directions_car,
                    color: Colors.blue,
                    isLoading: isLoading,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _StatCard(
                    title: 'This Week',
                    value: isLoading ? '-' : '${stats.weekRides}',
                    subtitle: 'Rides',
                    icon: Icons.calendar_today,
                    color: Colors.green,
                    isLoading: isLoading,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    title: 'Earnings Today',
                    value: isLoading ? '-' : 'RM ${stats.todayEarnings.toStringAsFixed(2)}',
                    subtitle: 'Completed bookings',
                    icon: Icons.monetization_on,
                    color: Colors.orange,
                    isLoading: isLoading,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _StatCard(
                    title: 'Rating',
                    value: isLoading ? '-' : stats.averageRating.toStringAsFixed(2),
                    subtitle: stats.totalRatings > 0 ? '${stats.totalRatings} reviews' : 'No reviews yet',
                    icon: Icons.star,
                    color: Colors.amber,
                    isLoading: isLoading,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Quick Actions
            Text(
              'Quick Actions',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _QuickActionCard(
              icon: Icons.add_road,
              title: 'Create New Ride',
              subtitle: 'Offer a ride to passengers',
              color: Colors.blue,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CreateRidePageV2(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _QuickActionCard(
              icon: Icons.star,
              title: 'My Reviews',
              subtitle: isLoading 
                  ? 'Loading...'
                  : '${stats.totalRatings} reviews (${stats.averageRating.toStringAsFixed(1)} ⭐)',
              color: Colors.amber,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DriverReviewsPage(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _QuickActionCard(
              icon: Icons.assessment,
              title: 'Summary Reports',
              subtitle: 'Daily, weekly & monthly reports with PDF export',
              color: Colors.teal,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DriverReportsPage(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _QuickActionCard(
              icon: Icons.history,
              title: 'Ride History',
              subtitle: 'View past rides',
              color: Colors.purple,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MyRidesPage(),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

/// Stat Card Widget
class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool isLoading;

  const _StatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            isLoading
                ? const SizedBox(
                    height: 32,
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: (theme.textTheme.headlineMedium?.fontSize ?? 28) - 6,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Quick Action Card Widget
class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: theme.colorScheme.onSurface.withOpacity(0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Verification Status Banner
class _VerificationStatusBanner extends ConsumerWidget {
  const _VerificationStatusBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final verificationService = DriverVerificationService();

    return FutureBuilder<DriverVerificationResult>(
      future: verificationService.checkVerificationStatus(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final result = snapshot.data!;

        // If not verified, show prominent call-to-action
        if (!result.isApproved) {
          return Card(
            color: Colors.orange.shade50,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DriverVerificationPage(),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.verified_user,
                        color: Colors.orange,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Verify Your Driver Account',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Complete verification to create rides',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.orange.shade700,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // If verified, hide the banner completely
        return const SizedBox.shrink();
      },
    );
  }
}

/// Earnings Page - Shows ride earnings with search
class _EarningsPage extends HookConsumerWidget {
  const _EarningsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    final searchController = useTextEditingController();
    final searchQuery = useState('');

    if (userId == null) {
      return const Center(
        child: Text('Please log in to view earnings'),
      );
    }

    final earningsSnapshot = useFuture(
      useMemoized(
        () => _fetchEarnings(supabase, userId),
        [userId],
      ),
    );

    return Column(
      children: [
        // Search Bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: searchController,
            decoration: InputDecoration(
              hintText: 'Search by passenger name...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searchQuery.value.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        searchController.clear();
                        searchQuery.value = '';
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (value) {
              searchQuery.value = value.toLowerCase();
            },
          ),
        ),

        // Earnings List
        Expanded(
          child: _buildEarningsList(
            context,
            theme,
            earningsSnapshot,
            searchQuery.value,
          ),
        ),
      ],
    );
  }

  Future<List<Map<String, dynamic>>> _fetchEarnings(
    SupabaseClient supabase,
    String userId,
  ) async {
    try {
      // Get all completed rides
      final rides = await supabase
          .from('rides')
          .select('id, from_location, to_location, scheduled_time')
          .eq('driver_id', userId)
          .eq('ride_status', 'completed')
          .order('scheduled_time', ascending: false);

      // For each ride, get bookings and passenger names
      final List<Map<String, dynamic>> earnings = [];
      
      for (final ride in rides) {
        final rideId = ride['id'] as String;
        
        // Get all accepted/completed bookings for this ride
        final bookings = await supabase
            .from('bookings')
            .select('passenger_id, fare_per_seat, seats_requested, payment_status')
            .eq('ride_id', rideId)
            .or('request_status.eq.accepted,request_status.eq.completed');

        // Get passenger details
        final List<Map<String, dynamic>> passengers = [];
        double totalFare = 0.0;
        
        for (final booking in bookings) {
          final passengerId = booking['passenger_id'] as String;
          final profile = await supabase
              .from('profiles')
              .select('full_name')
              .eq('id', passengerId)
              .maybeSingle();
          
          final farePerSeat = (booking['fare_per_seat'] as num?)?.toDouble() ?? 0.0;
          final seats = (booking['seats_requested'] as int?) ?? 1;
          final fare = farePerSeat * seats;
          totalFare += fare;
          
          passengers.add({
            'name': profile?['full_name'] ?? 'Passenger',
            'fare': fare,
            'paymentStatus': booking['payment_status'] ?? 'pending',
          });
        }

        if (passengers.isNotEmpty) {
          earnings.add({
            'rideId': rideId,
            'from': ride['from_location'],
            'to': ride['to_location'],
            'date': ride['scheduled_time'],
            'passengers': passengers,
            'totalFare': totalFare,
          });
        }
      }

      return earnings;
    } catch (e) {
      print('Error fetching earnings: $e');
      return [];
    }
  }

  Widget _buildEarningsList(
    BuildContext context,
    ThemeData theme,
    AsyncSnapshot<List<Map<String, dynamic>>> snapshot,
    String searchQuery,
  ) {
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
          ],
        ),
      );
    }

    final earnings = snapshot.data ?? [];

    if (earnings.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.attach_money,
              size: 80,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No completed rides yet',
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      );
    }

    // Filter earnings by search query (search in passenger names)
    final filteredEarnings = searchQuery.isEmpty
        ? earnings
        : earnings.where((earning) {
            final passengers = earning['passengers'] as List<Map<String, dynamic>>;
            return passengers.any((p) =>
                (p['name'] as String).toLowerCase().contains(searchQuery));
          }).toList();

    if (filteredEarnings.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 80,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No results found for "$searchQuery"',
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: filteredEarnings.length,
      itemBuilder: (context, index) {
        final earning = filteredEarnings[index];
        return _EarningCard(earning: earning);
      },
    );
  }
}

/// Earning Card Widget
class _EarningCard extends StatelessWidget {
  final Map<String, dynamic> earning;

  const _EarningCard({required this.earning});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final passengers = earning['passengers'] as List<Map<String, dynamic>>;
    final totalFare = earning['totalFare'] as double;
    final scheduledTimeUtc = DateTime.parse(earning['date'] as String).toUtc();
    final scheduledTime = TimezoneHelper.utcToMalaysia(scheduledTimeUtc);
    final dateStr = TimezoneHelper.formatMalaysiaDateTime(scheduledTime);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with total fare
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dateStr,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${earning['from']} → ${earning['to']}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'RM ${totalFare.toStringAsFixed(2)}',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    Text(
                      '${passengers.length} passenger${passengers.length > 1 ? 's' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const Divider(height: 24),

            // Passengers list
            ...passengers.map((passenger) {
              final name = passenger['name'] as String;
              final fare = passenger['fare'] as double;
              final paymentStatus = passenger['paymentStatus'] as String;
              final isPaid = paymentStatus == 'paid_cash' || paymentStatus == 'paid_tng';

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      isPaid ? Icons.check_circle : Icons.pending,
                      size: 16,
                      color: isPaid ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      'RM ${fare.toStringAsFixed(2)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isPaid ? Colors.green : Colors.orange,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

