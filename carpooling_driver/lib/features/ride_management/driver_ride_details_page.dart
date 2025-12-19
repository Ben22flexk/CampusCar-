import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:carpooling_driver/core/utils/timezone_helper.dart';
import 'package:carpooling_driver/services/penalty_service.dart';
import 'package:carpooling_driver/services/location_tracking_service.dart';
import 'package:carpooling_driver/features/notifications/data/datasources/notification_service.dart';
import 'package:carpooling_driver/features/messaging/driver_passenger_messaging_page.dart';
import 'package:carpooling_driver/features/ride_management/driver_navigation_page.dart';
import 'dart:async';
import 'dart:developer' as developer;

/// Driver-side Ride Details Page - View passengers who joined/requested
class DriverRideDetailsPage extends StatefulWidget {
  final String rideId;

  const DriverRideDetailsPage({
    super.key,
    required this.rideId,
  });

  @override
  State<DriverRideDetailsPage> createState() => _DriverRideDetailsPageState();
}

class _DriverRideDetailsPageState extends State<DriverRideDetailsPage> with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  Map<String, dynamic>? _rideData;
  List<Map<String, dynamic>> _confirmedPassengers = [];
  List<Map<String, dynamic>> _pendingRequests = [];
  String? _error;
  late TabController _tabController;
  
  // Timer for active ride check
  Timer? _activeRideTimer;
  bool _hasShownTimeoutDialog = false;
  DateTime? _rideActivatedAt;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadRideDetails();
    _setupRealtimeListener();
  }

  Future<void> _loadRideDetails() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      developer.log('🔍 Loading ride details for ID: ${widget.rideId}', name: 'DriverRideDetails');

      // Fetch ride data
      final rideResponse = await _supabase
          .from('rides')
          .select()
          .eq('id', widget.rideId)
          .single();

      developer.log('✅ Ride data loaded: $rideResponse', name: 'DriverRideDetails');

      // Fetch approved passengers (confirmed bookings)
      // For all rides (including completed), get from bookings table
      // Completed rides bookings are marked with request_status = 'completed' or 'accepted'
      final confirmedResponse = await _supabase
          .from('bookings')
          .select('''
            id, 
            passenger_id, 
            pickup_location,
            pickup_lat,
            pickup_lng,
            seats_requested,
            fare_per_seat,
            request_status,
            payment_status,
            requested_at,
            responded_at,
            created_at
          ''')
          .eq('ride_id', widget.rideId)
          .or('request_status.eq.accepted,request_status.eq.completed');

      // Get passenger names and avatars separately
      final List<Map<String, dynamic>> confirmedWithNames = [];
      for (final booking in confirmedResponse) {
        final passengerId = booking['passenger_id'];
        final profileResponse = await _supabase
            .from('profiles')
            .select('full_name, avatar_url')
            .eq('id', passengerId)
            .maybeSingle();
        
        confirmedWithNames.add({
          ...booking,
          'profiles': profileResponse ?? {'full_name': 'Passenger', 'avatar_url': null},
        });
      }

      developer.log('✅ Confirmed passengers: ${confirmedWithNames.length}', name: 'DriverRideDetails');

      // Fetch pending requests
      final pendingResponse = await _supabase
          .from('bookings')
          .select('''
            id, 
            passenger_id, 
            pickup_location,
            pickup_lat,
            pickup_lng,
            seats_requested,
            fare_per_seat,
            request_status,
            requested_at,
            created_at
          ''')
          .eq('ride_id', widget.rideId)
          .eq('request_status', 'pending');

      // Get passenger names and avatars separately
      final List<Map<String, dynamic>> pendingWithNames = [];
      for (final booking in pendingResponse) {
        final passengerId = booking['passenger_id'];
        final profileResponse = await _supabase
            .from('profiles')
            .select('full_name, avatar_url')
            .eq('id', passengerId)
            .maybeSingle();
        
        pendingWithNames.add({
          ...booking,
          'profiles': profileResponse ?? {'full_name': 'Passenger', 'avatar_url': null},
        });
      }

      developer.log('✅ Pending requests: ${pendingWithNames.length}', name: 'DriverRideDetails');

      setState(() {
        _rideData = rideResponse;
        _confirmedPassengers = confirmedWithNames;
        _pendingRequests = pendingWithNames;
        _isLoading = false;
      });

      // Start/check timer for active rides
      _checkAndStartActiveRideTimer();

      // DEBUG: Log confirmed passengers data structure
      if (_confirmedPassengers.isNotEmpty) {
        developer.log(
          '📊 Confirmed passengers data - Keys: ${_confirmedPassengers.first.keys.toList()}',
          name: 'DriverRideDetails',
        );
        developer.log(
          '📊 Sample passenger data: ${_confirmedPassengers.first}',
          name: 'DriverRideDetails',
        );
      }
    } catch (e, stackTrace) {
      developer.log('❌ Error loading ride details: $e', name: 'DriverRideDetails', error: e, stackTrace: stackTrace);
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _setupRealtimeListener() {
    // Listen for real-time updates to bookings
    _supabase
        .channel('ride_bookings_${widget.rideId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'bookings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'ride_id',
            value: widget.rideId,
          ),
          callback: (payload) {
            developer.log('🔄 Booking updated in real-time: ${payload.newRecord}', name: 'DriverRideDetails');
            _loadRideDetails(); // Reload data
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _activeRideTimer?.cancel();
    _supabase.removeChannel(_supabase.channel('ride_bookings_${widget.rideId}'));
    _tabController.dispose();
    super.dispose();
  }

  /// Check if ride is active and start timer if needed
  void _checkAndStartActiveRideTimer() {
    final rideStatus = _rideData?['ride_status'] as String?;
    
    // Only start timer for 'active' status rides (NOT in_progress)
    // Timer should stop once driver presses "Start Trip"
    if (rideStatus != 'active') {
      _activeRideTimer?.cancel();
      _activeRideTimer = null;
      _hasShownTimeoutDialog = false;
      _rideActivatedAt = null;
      developer.log('⏱️ Timer not needed - Ride status: $rideStatus', name: 'DriverRideDetails');
      return;
    }

    // If timer already running and dialog not shown yet, don't restart
    if (_activeRideTimer != null && _activeRideTimer!.isActive) {
      developer.log('⏱️ Timer already running', name: 'DriverRideDetails');
      return;
    }

    // If dialog was already shown, don't restart timer
    if (_hasShownTimeoutDialog) {
      developer.log('⏱️ Dialog already shown, not restarting timer', name: 'DriverRideDetails');
      return;
    }

    // Get ride activation time
    final startedAt = _rideData?['started_at'];
    if (startedAt != null && _rideActivatedAt == null) {
      _rideActivatedAt = DateTime.parse(startedAt).toLocal();
    } else {
      _rideActivatedAt ??= DateTime.now();
    }

    // Check if 20 minutes already passed
    final now = DateTime.now();
    final elapsed = now.difference(_rideActivatedAt!);
    
    if (elapsed.inMinutes >= 20) {
      // Show dialog immediately if already past 20 minutes
      developer.log('⏱️ Ride already active for ${elapsed.inMinutes} minutes, showing dialog', name: 'DriverRideDetails');
      _showActiveRideTimeoutDialog();
      return;
    }

    // Calculate remaining time until 20 minutes
    final remainingDuration = const Duration(minutes: 20) - elapsed;
    
    developer.log(
      '⏱️ Starting timer for ${remainingDuration.inMinutes} minutes ${remainingDuration.inSeconds % 60} seconds',
      name: 'DriverRideDetails',
    );

    // Start timer for remaining duration
    _activeRideTimer = Timer(remainingDuration, () {
      if (mounted && !_hasShownTimeoutDialog) {
        _showActiveRideTimeoutDialog();
      }
    });
  }

  /// Show dialog asking driver to continue or delete the ride
  /// Only shown for 'active' status rides (before "Start Trip" is pressed)
  void _showActiveRideTimeoutDialog() {
    if (!mounted || _hasShownTimeoutDialog) return;

    _hasShownTimeoutDialog = true;
    
    developer.log('⏰ Showing 20-minute timeout dialog for active ride', name: 'DriverRideDetails');

    showDialog(
      context: context,
      barrierDismissible: false, // Must choose an option
      builder: (context) => WillPopScope(
        onWillPop: () async => false, // Prevent back button dismiss
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.access_time, color: Colors.orange, size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Ride Active for 20 Minutes',
                  style: TextStyle(fontSize: 18),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your ride has been active for 20 minutes without starting the trip.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'Would you like to:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Continue with the ride and keep it active',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.delete, color: Colors.red, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Delete the ride if you\'re not proceeding',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Confirmed passengers: ${_confirmedPassengers.length}',
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          actions: [
            // Delete button
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _handleTimeoutDelete();
              },
              icon: const Icon(Icons.delete, color: Colors.red),
              label: const Text(
                'Delete Ride',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
            ),
            // Continue button
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _handleTimeoutContinue();
              },
              icon: const Icon(Icons.check),
              label: const Text('Continue Ride'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Handle driver choosing to continue the ride
  void _handleTimeoutContinue() {
    developer.log('✅ Driver chose to continue ride', name: 'DriverRideDetails');
    
    // Reset timer state to allow another 20 minutes
    _hasShownTimeoutDialog = false;
    _rideActivatedAt = DateTime.now(); // Reset activation time
    
    // Restart timer for another 20 minutes
    _checkAndStartActiveRideTimer();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Continuing ride. You\'ll be prompted again in 20 minutes.',
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  /// Handle driver choosing to delete the ride
  void _handleTimeoutDelete() {
    developer.log('🗑️ Driver chose to delete ride after timeout', name: 'DriverRideDetails');
    
    // Show delete confirmation dialog with reason
    // Pass false for hasPassedDeparture since this is a timeout-based deletion
    _confirmDeleteRide(false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Loading...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text('Failed to load ride details', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(_error!, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadRideDetails,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_rideData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ride Not Found')),
        body: const Center(child: Text('Ride details not available')),
      );
    }

    // Parse data
    final fromLocation = _rideData!['from_location'] as String;
    final toLocation = _rideData!['to_location'] as String;
    final scheduledTimeUtc = DateTime.parse(_rideData!['scheduled_time'] as String).toUtc();
    final scheduledTimeMalaysia = TimezoneHelper.utcToMalaysia(scheduledTimeUtc);
    final availableSeats = _rideData!['available_seats'] as int;
    
    // Calculate booked seats and total fare from all confirmed passengers
    int bookedSeats = 0;
    double totalPassengerFares = 0.0;
    for (final passenger in _confirmedPassengers) {
      final farePerSeat = (passenger['fare_per_seat'] as num?)?.toDouble() ?? 0.0;
      final seatsRequested = (passenger['seats_requested'] as int?) ?? 1;
      bookedSeats += seatsRequested;
      totalPassengerFares += farePerSeat * seatsRequested;
    }
    
    // Total seats = available + booked
    final totalSeats = availableSeats + bookedSeats;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Ride Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRideDetails,
            tooltip: 'Refresh',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.check_circle),
              text: 'Confirmed (${_confirmedPassengers.length})',
            ),
            Tab(
              icon: Badge(
                isLabelVisible: _pendingRequests.isNotEmpty,
                label: Text('${_pendingRequests.length}'),
                child: const Icon(Icons.pending),
              ),
              text: 'Pending (${_pendingRequests.length})',
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Ride Summary Card
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.route, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                child: Text(
                      '$fromLocation → $toLocation',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildQuickInfo(Icons.access_time, TimezoneHelper.formatMalaysiaTime(scheduledTimeMalaysia), theme),
                  _buildQuickInfo(Icons.event_seat, '$bookedSeats / $totalSeats seats', theme),
                  _buildQuickInfo(Icons.payments, 'RM ${totalPassengerFares.toStringAsFixed(2)}', theme),
                ],
              ),
              const SizedBox(height: 12),
              // Message All Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _openGroupMessaging(),
                  icon: const Icon(Icons.message),
                  label: Text('Message All Passengers (${_confirmedPassengers.length + _pendingRequests.length})'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
                ],
              ),
            ),
          ),
          
          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Confirmed Passengers Tab
                _buildPassengerList(
                  passengers: _confirmedPassengers,
                  emptyIcon: Icons.people_outline,
                  emptyMessage: 'No confirmed passengers yet',
                  emptySubMessage: 'Accepted requests will appear here',
                  isConfirmed: true,
                ),
                
                // Pending Requests Tab
                _buildPassengerList(
                  passengers: _pendingRequests,
                  emptyIcon: Icons.hourglass_empty,
                  emptyMessage: 'No pending requests',
                  emptySubMessage: 'New ride requests will appear here',
                  isConfirmed: false,
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomButtons(theme, scheduledTimeMalaysia),
    );
  }

  Widget _buildBottomButtons(ThemeData theme, DateTime scheduledTime) {
    final now = TimezoneHelper.nowInMalaysia();
    final rideStatus = _rideData!['ride_status'] as String? ?? 'active';
    final hasPassedDeparture = now.isAfter(scheduledTime);
    
    // Calculate time until scheduled departure
    final timeUntilDeparture = scheduledTime.difference(now);
    final hoursUntilDeparture = timeUntilDeparture.inMinutes / 60;
    final canStartEarly = hoursUntilDeparture <= 2 && hoursUntilDeparture > -1; // Within 2 hours before, or up to 1 hour after

    developer.log('🎯 Building buttons for status: $rideStatus, hours until departure: ${hoursUntilDeparture.toStringAsFixed(1)}', name: 'DriverRideDetails');

    // Status: completed - show completion message
    if (rideStatus == 'completed') {
      return Container(
        padding: const EdgeInsets.all(16),
        color: Colors.green.shade50,
        child: SafeArea(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: Colors.green.shade700),
              const SizedBox(width: 8),
              Text(
                'Ride Completed',
                style: TextStyle(
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Status: in_progress - show Continue Navigation button ONLY
    if (rideStatus == 'in_progress') {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: () => _navigateToNavigationPage(),
            icon: const Icon(Icons.navigation),
            label: const Text('Continue Navigation'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.green,
            ),
          ),
        ),
      );
    }

    // Status: scheduled - show info message and conditional start button
    if (rideStatus == 'scheduled') {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Info message about automatic activation
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: canStartEarly ? Colors.green.shade50 : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: canStartEarly ? Colors.green.shade200 : Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      canStartEarly ? Icons.check_circle_outline : Icons.schedule,
                      color: canStartEarly ? Colors.green.shade700 : Colors.blue.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        canStartEarly
                            ? '✅ Ready to start!\nYou can start the ride now.'
                            : '⏰ Scheduled Ride\nYou can start up to 2 hours before departure time.\nTime remaining: ${_formatTimeRemaining(timeUntilDeparture)}',
                        style: TextStyle(
                          color: canStartEarly ? Colors.green.shade800 : Colors.blue.shade800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  // Delete button
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmDeleteRide(hasPassedDeparture),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ),
                  if (canStartEarly) ...[
                    const SizedBox(width: 12),
                    // Start button (only if within 2 hours)
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () => _startRide(),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start Ride'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.green,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      );
    }

    // Status: active - show both Delete and Start buttons (for immediate rides)
    if (rideStatus == 'active') {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Delete button
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _confirmDeleteRide(hasPassedDeparture),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Start Trip button (for immediate rides)
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: () => _startRide(),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Trip'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.green,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Default: no buttons
    return const SizedBox.shrink();
  }
  
  String _formatTimeRemaining(Duration duration) {
    if (duration.isNegative) {
      return 'Departure time passed';
    }
    
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    
    if (hours > 24) {
      final days = hours ~/ 24;
      return '$days day${days != 1 ? 's' : ''} ${hours.remainder(24)}h';
    } else if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }

  Widget _buildQuickInfo(IconData icon, String text, ThemeData theme) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(text, style: theme.textTheme.bodySmall),
      ],
    );
  }

  Widget _buildPassengerList({
    required List<Map<String, dynamic>> passengers,
    required IconData emptyIcon,
    required String emptyMessage,
    required String emptySubMessage,
    required bool isConfirmed,
  }) {
    if (passengers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(emptyIcon, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(emptyMessage, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              emptySubMessage,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: passengers.length,
      itemBuilder: (context, index) {
        final booking = passengers[index];
        final profile = booking['profiles'] as Map<String, dynamic>;
        final name = profile['full_name'] as String? ?? 'Passenger';
        final photoUrl = profile['avatar_url'] as String?;
        final createdAt = DateTime.parse(booking['created_at'] as String);
        final seatsRequested = booking['seats_requested'] as int? ?? 1;
        final farePerSeat = (booking['fare_per_seat'] as num?)?.toDouble() ?? 0.0;
        final totalFare = farePerSeat * seatsRequested;
        final passengerPickup = booking['pickup_location'] as String? ?? 'Pickup location';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              radius: 28,
              backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                  ? NetworkImage(photoUrl)
                  : null,
              onBackgroundImageError: (exception, stackTrace) {
                // Handle image load error silently
              },
              child: photoUrl == null || photoUrl.isEmpty
                  ? const Icon(Icons.person)
                  : null,
            ),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('$seatsRequested seat • RM ${totalFare.toStringAsFixed(2)} • $passengerPickup', style: const TextStyle(fontSize: 11), maxLines: 2),
            trailing: isConfirmed
                ? Icon(Icons.check_circle, color: Colors.green[700], size: 28)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.check_circle, color: Colors.green[700]),
                        onPressed: () => _acceptRequest(booking['id'] as String),
                        tooltip: 'Accept',
                      ),
                      IconButton(
                        icon: Icon(Icons.cancel, color: Colors.red[700]),
                        onPressed: () => _confirmRejectRequest(booking['id'] as String, booking),
                        tooltip: 'Reject',
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final malaysiaTime = TimezoneHelper.utcToMalaysia(dateTime);
    return TimezoneHelper.formatMalaysiaDateTime(malaysiaTime);
  }

  Future<void> _acceptRequest(String bookingId) async {
    try {
      developer.log('✅ Accepting booking: $bookingId', name: 'DriverRideDetails');
      
      // Get booking and passenger info
      final booking = _pendingRequests.firstWhere((p) => p['id'] == bookingId);
      final passengerId = booking['passenger_id'] as String;
      final seatsRequested = booking['seats_requested'] as int? ?? 1;
      
      // Check if there are enough available seats
      final availableSeats = _rideData!['available_seats'] as int;
      if (seatsRequested > availableSeats) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Not enough seats! Requested: $seatsRequested, Available: $availableSeats'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      
      // Accept the booking
      await _supabase
          .from('bookings')
          .update({
            'request_status': 'accepted',
            'responded_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', bookingId);
      
      // Update available seats in rides table
      await _supabase
          .from('rides')
          .update({
            'available_seats': availableSeats - seatsRequested,
          })
          .eq('id', widget.rideId);
      
      developer.log('✅ Updated available seats: ${availableSeats - seatsRequested}', name: 'DriverRideDetails');
      
      // Send push notification to passenger
      try {
        final notificationService = NotificationService();
        await notificationService.createNotification(
          userId: passengerId,
          title: '✅ Ride Request Approved!',
          message: 'Your ride request has been approved by the driver. Get ready for your trip!',
          type: 'ride_approved',
          relatedId: widget.rideId,
        );
        developer.log('📢 Notification sent to passenger: $passengerId', name: 'DriverRideDetails');
      } catch (e) {
        developer.log('⚠️ Failed to send notification: $e', name: 'DriverRideDetails');
      }
      
      // If ride is now full, auto-reject all pending requests
      if (availableSeats - seatsRequested == 0) {
        await _autoRejectPendingRequests('Ride is now full');
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Request approved! Passenger added to ride.'),
            backgroundColor: Colors.green,
          ),
        );
      }
      
      // Data will auto-refresh via realtime listener
    } catch (e) {
      developer.log('❌ Error accepting request: $e', name: 'DriverRideDetails');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to accept: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  /// Auto-reject all pending requests when ride is full
  Future<void> _autoRejectPendingRequests(String reason) async {
    try {
      developer.log('🚫 Auto-rejecting ${_pendingRequests.length} pending requests: $reason', name: 'DriverRideDetails');
      
      for (final pendingBooking in _pendingRequests) {
        final bookingId = pendingBooking['id'] as String;
        final passengerId = pendingBooking['passenger_id'] as String;
        
        // Reject the booking
        await _supabase
            .from('bookings')
            .update({
              'request_status': 'rejected',
              'responded_at': DateTime.now().toUtc().toIso8601String(),
              'rejection_reason': reason,
            })
            .eq('id', bookingId);
        
        // Notify passenger
        try {
          final notificationService = NotificationService();
          await notificationService.createNotification(
            userId: passengerId,
            title: '❌ Ride Request Declined',
            message: 'Your ride request was declined.\n\nReason: $reason\n\nPlease search for other available rides.',
            type: 'ride_rejected',
            relatedId: widget.rideId,
          );
        } catch (e) {
          developer.log('⚠️ Failed to notify passenger $passengerId: $e', name: 'DriverRideDetails');
        }
      }
      
      developer.log('✅ Auto-rejected all pending requests', name: 'DriverRideDetails');
    } catch (e) {
      developer.log('❌ Error auto-rejecting requests: $e', name: 'DriverRideDetails');
    }
  }

  void _confirmRejectRequest(String bookingId, Map<String, dynamic> booking) {
    String? selectedReason;
    final reasonController = TextEditingController();
    
    final predefinedReasons = [
      'Ride is full',
      'Pickup location too far',
      'Schedule conflict',
      'Vehicle capacity issue',
      'Safety concerns',
      'Other (please specify)',
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.warning, color: Colors.orange),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Reject Request?',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Please select a reason for rejecting this request:'),
                const SizedBox(height: 16),
                
                // Reason selection
                ...predefinedReasons.map((reason) => RadioListTile<String>(
                  title: Text(reason, style: const TextStyle(fontSize: 14)),
                  value: reason,
                  groupValue: selectedReason,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  onChanged: (value) {
                    setState(() {
                      selectedReason = value;
                    });
                  },
                )),
                
                // Custom reason input
                if (selectedReason == 'Other (please specify)') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: reasonController,
                    decoration: const InputDecoration(
                      hintText: 'Enter your reason...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    maxLines: 2,
                  ),
                ],
                
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '📢 The passenger will be notified with your reason.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (selectedReason == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select a reason before rejecting'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                
                String finalReason = selectedReason!;
                if (selectedReason == 'Other (please specify)') {
                  if (reasonController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please specify your reason'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  finalReason = reasonController.text.trim();
                }
                
                Navigator.pop(context);
                _rejectRequest(bookingId, booking, finalReason);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('Reject Request'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rejectRequest(String bookingId, Map<String, dynamic> booking, String reason) async {
    try {
      developer.log('❌ Rejecting booking: $bookingId with reason: $reason', name: 'DriverRideDetails');
      
      final passengerId = booking['passenger_id'] as String;
      
      await _supabase
          .from('bookings')
          .update({
            'request_status': 'rejected',
            'responded_at': DateTime.now().toUtc().toIso8601String(),
            'rejection_reason': reason,
          })
          .eq('id', bookingId);
      
      // Send push notification to passenger with reason
      try {
        final notificationService = NotificationService();
        await notificationService.createNotification(
          userId: passengerId,
          title: '❌ Ride Request Declined',
          message: 'Your ride request was declined.\n\nReason: $reason\n\nPlease search for other available rides.',
          type: 'ride_rejected',
          relatedId: widget.rideId,
        );
        developer.log('📢 Notification sent to passenger: $passengerId', name: 'DriverRideDetails');
      } catch (e) {
        developer.log('⚠️ Failed to send notification: $e', name: 'DriverRideDetails');
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Request rejected. Passenger notified.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      
      // Data will auto-refresh via realtime listener
    } catch (e) {
      developer.log('❌ Error rejecting request: $e', name: 'DriverRideDetails');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to reject: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _startRide() async {
    try {
      // CRITICAL: Validate confirmed passengers BEFORE starting
      if (_confirmedPassengers.isEmpty) {
        developer.log('❌ Cannot start ride: No confirmed passengers', name: 'DriverRideDetails');
        
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.orange),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Cannot Start Trip',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: const Text(
                'You need at least 1 confirmed passenger to start the trip.\n\n'
                'Current confirmed passengers: 0\n\n'
                'Please wait for passengers to request rides and accept their bookings.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }

      final currentStatus = _rideData?['ride_status'] as String?;
      developer.log(
        '🚀 Starting ride: ${widget.rideId} (status: $currentStatus, confirmed passengers: ${_confirmedPassengers.length})',
        name: 'DriverRideDetails',
      );

      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Starting ride and enabling GPS tracking...',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }

      // Import location tracking service
      final locationService = LocationTrackingService();

      // Start ride with location tracking (this calls the SQL function)
      await locationService.startRide(widget.rideId);

      developer.log('✅ Ride started with location tracking', name: 'DriverRideDetails');

      // Send notification to all confirmed passengers
      final notificationService = NotificationService();
      for (final passenger in _confirmedPassengers) {
        final passengerId = passenger['passenger_id'] as String;
        await notificationService.createNotification(
          userId: passengerId,
          title: '🚀 Ride Started!',
          message: 'Your driver has started the ride. Track your driver in real-time!',
          type: 'ride_started',
          relatedId: widget.rideId,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🚀 Ride started! GPS tracking enabled.'),
            backgroundColor: Colors.green,
          ),
        );

        // Navigate to navigation page
        _navigateToNavigationPage();
      }

      // Reload data (timer will be cancelled automatically since status changes to in_progress)
      await _loadRideDetails();
    } catch (e) {
      developer.log('❌ Error starting ride: $e', name: 'DriverRideDetails');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to start ride: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _confirmDeleteRide(bool hasPassedDeparture) {
    final fromLocation = _rideData!['from_location'] as String;
    final toLocation = _rideData!['to_location'] as String;
    final hasConfirmedPassengers = _confirmedPassengers.isNotEmpty;
    
    String? selectedReason;
    final reasonController = TextEditingController();
    
    final predefinedReasons = [
      'Vehicle issues',
      'Personal emergency',
      'Weather conditions',
      'Schedule conflict',
      'Health issues',
      'Other (please specify)',
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning, color: hasPassedDeparture || hasConfirmedPassengers ? Colors.red : Colors.orange),
              const SizedBox(width: 8),
              const Text('Delete Ride?'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Are you sure you want to delete this ride?'),
                const SizedBox(height: 12),
                Text(
                  '$fromLocation → $toLocation',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                
                // Reason selection
                const Text(
                  'Please select a reason:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...predefinedReasons.map((reason) => RadioListTile<String>(
                  title: Text(reason, style: const TextStyle(fontSize: 14)),
                  value: reason,
                  groupValue: selectedReason,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  onChanged: (value) {
                    setState(() {
                      selectedReason = value;
                    });
                  },
                )),
                
                // Custom reason input
                if (selectedReason == 'Other (please specify)') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: reasonController,
                    decoration: const InputDecoration(
                      hintText: 'Enter your reason...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    maxLines: 2,
                  ),
                ],
                
                const SizedBox(height: 16),
                
                // Warning messages
                if (hasConfirmedPassengers) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.warning, color: Colors.orange.shade700, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'PENALTY NOTICE',
                              style: TextStyle(
                                color: Colors.orange.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '⚠️ You have ${_confirmedPassengers.length} confirmed passenger(s)\n\n'
                          '🚫 You will receive 20-MINUTE BAN\n'
                          '📢 Passengers will be notified\n\n'
                          'During this time, you cannot create new rides.',
                          style: TextStyle(
                            color: Colors.orange.shade900,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '✅ No confirmed passengers - No penalty will be applied.',
                      style: TextStyle(color: Colors.blue.shade900, fontSize: 13),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (selectedReason == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select a reason before deleting'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                
                String finalReason = selectedReason!;
                if (selectedReason == 'Other (please specify)') {
                  if (reasonController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please specify your reason'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  finalReason = reasonController.text.trim();
                }
                
                Navigator.pop(context);
                _deleteRide(hasConfirmedPassengers, finalReason);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('Delete Ride'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteRide(bool hasConfirmedPassengers, String reason) async {
    try {
      final rideStatus = _rideData?['ride_status'] as String? ?? 'active';
      developer.log('🗑️ Deleting ride: ${widget.rideId} (Status: $rideStatus, Has Passengers: $hasConfirmedPassengers, Reason: $reason)', name: 'DriverRideDetails');

      // BLOCK deletion if ride is in_progress
      if (rideStatus == 'in_progress') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cannot delete ride after it has started. Please complete the ride first.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final driverId = _supabase.auth.currentUser?.id;
      if (driverId == null) return;

      // Apply 20-minute penalty ONLY if there are confirmed passengers
      if (hasConfirmedPassengers) {
        final penaltyService = PenaltyService();
        await penaltyService.applyPenalty(
          userId: driverId,
          penaltyType: 'ride_deletion_with_passengers',
          reason: 'Ride cancelled with confirmed passengers. Reason: $reason',
          rideId: widget.rideId,
          customDuration: const Duration(minutes: 20), // 20-minute penalty
        );
        developer.log('🚫 20-minute penalty applied to driver', name: 'DriverRideDetails');
      } else {
        developer.log('✅ No penalty - no confirmed passengers', name: 'DriverRideDetails');
      }

      // Send notifications to all confirmed passengers
      final notificationService = NotificationService();
      final notificationTitle = hasConfirmedPassengers ? '🚫 Ride Cancelled by Driver' : '⚠️ Ride Cancelled';
      final notificationMessage = hasConfirmedPassengers
          ? 'The driver has cancelled the ride. Reason: $reason. You can search for other rides.'
          : 'The driver has cancelled the ride. You can search for other rides.';

      for (final passenger in _confirmedPassengers) {
        final passengerId = passenger['passenger_id'] as String;
        await notificationService.createNotification(
          userId: passengerId,
          title: notificationTitle,
          message: notificationMessage,
          type: 'ride_cancelled',
        );
      }

      // Use the safe delete function that handles all dependencies
      try {
        final result = await _supabase.rpc('delete_ride_safely', params: {
          'p_ride_id': widget.rideId,
        });
        
        developer.log('✅ Ride deleted successfully: $result', name: 'DriverRideDetails');
      } catch (rpcError) {
        // If RPC doesn't exist, use manual deletion
        developer.log('⚠️ RPC not available, using manual deletion: $rpcError', name: 'DriverRideDetails');
        
        // Manual deletion with proper ordering
        try {
          // Step 1: Get all booking IDs first
          final bookingIds = await _supabase
              .from('bookings')
              .select('id')
              .eq('ride_id', widget.rideId);
          
          developer.log('Found ${bookingIds.length} bookings to delete', name: 'DriverRideDetails');
          
          // Step 2: Delete each booking by ID only (no ride_id filter to avoid constraint)
          for (final booking in bookingIds) {
            try {
              await _supabase
                  .from('bookings')
                  .delete()
                  .eq('id', booking['id']);
            } catch (e) {
              developer.log('Warning: Could not delete booking ${booking['id']}: $e', name: 'DriverRideDetails');
            }
          }
          
          // Wait a moment for DB to process
          await Future.delayed(const Duration(milliseconds: 500));
          
          // Step 3: Now delete the ride
          await _supabase
              .from('rides')
              .delete()
              .eq('id', widget.rideId);
          
          developer.log('✅ Ride and bookings deleted manually', name: 'DriverRideDetails');
        } catch (manualError) {
          developer.log('❌ Manual deletion failed: $manualError', name: 'DriverRideDetails');
          rethrow;
        }
      }

      if (mounted) {
        final message = hasConfirmedPassengers
            ? '🚫 Ride deleted. You received a 20-minute penalty. Passengers have been notified.'
            : '✅ Ride deleted successfully.';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: hasConfirmedPassengers ? Colors.orange : Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );

        // Go back after showing message and signal successful deletion
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) Navigator.pop(context, true); // Return true to signal deletion
      }
    } catch (e) {
      developer.log('❌ Error deleting ride: $e', name: 'DriverRideDetails');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to delete ride: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _openGroupMessaging() {
    // Show dialog to select passenger to message
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Message Passengers'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select a passenger to message:'),
            const SizedBox(height: 16),
            ...(_confirmedPassengers + _pendingRequests).map((passenger) {
              final profile = passenger['profiles'] as Map<String, dynamic>;
              final name = profile['full_name'] as String? ?? 'Passenger';
              final avatarUrl = profile['avatar_url'] as String?;
              final passengerId = passenger['passenger_id'] as String;
              final status = passenger['request_status'] as String;
              
              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                      ? NetworkImage(avatarUrl)
                      : null,
                  onBackgroundImageError: (exception, stackTrace) {
                    // Handle image load error silently
                  },
                  child: avatarUrl == null || avatarUrl.isEmpty
                      ? const Icon(Icons.person)
                      : null,
                ),
                title: Text(name),
                subtitle: Text(status == 'accepted' ? 'Confirmed' : 'Pending'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  _openDirectMessage(passengerId, name);
                },
              );
            }),
          ],
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

  void _openDirectMessage(String passengerId, String passengerName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DriverPassengerMessagingPage(
          rideId: widget.rideId,
          passengerId: passengerId,
          passengerName: passengerName,
        ),
      ),
    );
  }

  /// Navigate to navigation page with passenger pickup locations
  Future<void> _navigateToNavigationPage() async {
    try {
      developer.log(
        '🔍 Navigation validation - Confirmed passengers count: ${_confirmedPassengers.length}',
        name: 'DriverRideDetails',
      );

      // Validate confirmed passengers exist
      if (_confirmedPassengers.isEmpty) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.orange),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'No Confirmed Passengers',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: const Text(
                'You cannot start navigation without confirmed passengers.\n\n'
                'Please wait for passengers to request and accept their bookings before starting the ride.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }

      // Prepare passenger data with pickup locations
      final List<Map<String, dynamic>> passengersWithLocations = [];

      for (final passenger in _confirmedPassengers) {
        // Use 'id' field which is the booking ID from the query
        final bookingId = passenger['id'] as String?;
        final passengerId = passenger['passenger_id'] as String?;
        final passengerProfile = passenger['profiles'] as Map<String, dynamic>?;
        final passengerName = passengerProfile?['full_name'] as String?;
        
        developer.log(
          '📋 Processing passenger: bookingId=$bookingId, passengerId=$passengerId, name=$passengerName',
          name: 'DriverRideDetails',
        );

        if (bookingId == null || passengerId == null) {
          developer.log('⚠️ Skipping passenger with missing data', name: 'DriverRideDetails');
          continue;
        }

        // Get passenger's specific pickup location from their booking
        final pickupLocation = passenger['pickup_location'] as String? ?? _rideData?['from_location'] ?? 'Pickup Location';
        final pickupLat = passenger['pickup_lat'] as double? ?? _rideData?['from_lat'] ?? 0.0;
        final pickupLng = passenger['pickup_lng'] as double? ?? _rideData?['from_lng'] ?? 0.0;
        
        developer.log(
          '   📍 Pickup: $pickupLocation ($pickupLat, $pickupLng)',
          name: 'DriverRideDetails',
        );
        
        // Use data directly from _confirmedPassengers (already validated as 'accepted')
        passengersWithLocations.add({
          'booking_id': bookingId,
          'passenger_id': passengerId,
          'passenger_name': passengerName ?? 'Passenger',
          'pickup_location': pickupLocation,
          'pickup_lat': pickupLat,
          'pickup_lng': pickupLng,
          'pickup_status': 'pending',
        });
      }

      // Final validation
      if (passengersWithLocations.isEmpty) {
        developer.log('❌ No passengers with valid data after processing', name: 'DriverRideDetails');
        
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.error, color: Colors.red),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Cannot Start Navigation',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: Text(
                'Could not load passenger data.\n\n'
                'Confirmed passengers: ${_confirmedPassengers.length}\n'
                'Valid passengers: ${passengersWithLocations.length}\n\n'
                'Please try refreshing the page.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _loadRideDetails();
                  },
                  child: const Text('Refresh'),
                ),
              ],
            ),
          );
        }
        return;
      }

      developer.log('✅ Starting navigation with ${passengersWithLocations.length} confirmed passengers', 
                    name: 'DriverRideDetails');

      // Navigate to navigation page
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DriverNavigationPage(
              rideId: widget.rideId,
              passengers: passengersWithLocations,
            ),
          ),
        );

        // Reload data when returning
        await _loadRideDetails();
      }
    } catch (e, stackTrace) {
      developer.log(
        '❌ Error navigating to navigation page: $e',
        name: 'DriverRideDetails',
        error: e,
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading navigation: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
