import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:carpooling_main/core/utils/timezone_helper.dart';
import 'package:carpooling_main/services/ride_request_service.dart';
import 'package:carpooling_main/services/booking_service.dart';
import 'package:carpooling_main/services/fare_calculation_service.dart';
import 'package:carpooling_main/utils/distance_helper.dart';
import 'package:carpooling_main/pages/chat_page.dart';
import 'package:carpooling_main/pages/track_driver_page_mqtt.dart';
import 'dart:developer' as developer;

/// Passenger-side Ride Details Page - Real-time data from database
class RideDetailsPage extends StatefulWidget {
  final String rideId;
  final String driverId;
  final String? passengerPickup; // Passenger's selected pickup location
  final String? passengerDestination; // Passenger's selected destination
  final double? passengerPickupLat; // Passenger's pickup latitude
  final double? passengerPickupLng; // Passenger's pickup longitude
  final double? passengerDestinationLat; // Passenger's destination latitude
  final double? passengerDestinationLng; // Passenger's destination longitude

  const RideDetailsPage({
    super.key,
    required this.rideId,
    required this.driverId,
    this.passengerPickup,
    this.passengerDestination,
    this.passengerPickupLat,
    this.passengerPickupLng,
    this.passengerDestinationLat,
    this.passengerDestinationLng,
  });

  @override
  State<RideDetailsPage> createState() => _RideDetailsPageState();
}

class _RideDetailsPageState extends State<RideDetailsPage> {
  final _supabase = Supabase.instance.client;
  final _requestService = RideRequestService();
  final _bookingService = BookingService();
  final _fareService = FareCalculationService();
  bool _isLoading = true;
  bool _isRequesting = false;
  bool _isCancelling = false;
  Map<String, dynamic>? _rideData;
  Map<String, dynamic>? _driverData;
  Map<String, dynamic>? _myBooking; // Passenger's booking for this ride
  String? _error;
  double? _calculatedFare; // Calculated student fare for this ride

  @override
  void initState() {
    super.initState();
    _loadRideDetails();
    _setupRealtimeListener();
  }

  Future<void> _checkMyBookingStatus() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final booking = await _supabase
          .from('bookings')
          .select()
          .eq('ride_id', widget.rideId)
          .eq('passenger_id', userId)
          .maybeSingle();

      setState(() {
        _myBooking = booking;
      });

      developer.log('📋 My booking status: ${booking?['request_status']}', name: 'RideDetails');
    } catch (e) {
      developer.log('❌ Error checking booking status: $e', name: 'RideDetails');
    }
  }

  Future<void> _loadRideDetails() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      developer.log('🔍 Loading ride details for ID: ${widget.rideId}', name: 'RideDetails');
      developer.log('🔍 Driver ID passed: ${widget.driverId}', name: 'RideDetails');

      // Check passenger's booking status for this ride
      await _checkMyBookingStatus();

      // Step 1: Fetch ride data first
      final rideResponse = await _supabase
          .from('rides')
          .select()
          .eq('id', widget.rideId)
          .maybeSingle();

      if (rideResponse == null) {
        throw Exception('Ride not found. It may have been deleted or completed.');
      }

      developer.log('✅ Ride data loaded: $rideResponse', name: 'RideDetails');

      // Step 2: Get the actual driver_id from the ride
      final actualDriverId = rideResponse['driver_id'] as String?;
      
      if (actualDriverId == null) {
        throw Exception('No driver assigned to this ride.');
      }

      developer.log('🔍 Actual driver_id from ride: $actualDriverId', name: 'RideDetails');

      // Step 3: Query profiles table directly for driver info
      final driverProfiles = await _supabase
          .from('profiles')
          .select('id, full_name, email, gender, avatar_url')
          .eq('id', actualDriverId);

      developer.log('🔍 Driver profiles query result: $driverProfiles', name: 'RideDetails');

      if (driverProfiles.isEmpty) {
        // If not found in profiles, check if user exists in auth.users
        developer.log('⚠️ Driver not found in profiles table with id: $actualDriverId', name: 'RideDetails');
        throw Exception('Driver profile not found in database. Driver ID: $actualDriverId');
      }

      final driverResponse = driverProfiles[0];
      developer.log('✅ Driver profile loaded: $driverResponse', name: 'RideDetails');

      // Fetch vehicle data - check driver_verifications first, then vehicles table
      Map<String, dynamic>? vehicleData;
      
      try {
        // Try driver_verifications table first (use actual driver ID from ride)
        final verificationResponse = await _supabase
            .from('driver_verifications')
            .select('vehicle_model, vehicle_color, vehicle_plate_number')
            .eq('user_id', actualDriverId)
            .maybeSingle();

        if (verificationResponse != null) {
          vehicleData = {
            'vehicle_model': verificationResponse['vehicle_model'],
            'vehicle_color': verificationResponse['vehicle_color'],
            'vehicle_plate': verificationResponse['vehicle_plate_number'],
          };
          developer.log('✅ Vehicle data from driver_verifications: $vehicleData', name: 'RideDetails');
        }
      } catch (e) {
        developer.log('⚠️ Error fetching from driver_verifications: $e', name: 'RideDetails');
      }

      // Log if vehicle data not found
      if (vehicleData == null) {
        developer.log('⚠️ No vehicle data found for driver in driver_verifications', name: 'RideDetails');
        // Set default values to show "Not specified" instead of "N/A"
        vehicleData = {
          'vehicle_model': 'Not specified',
          'vehicle_color': 'Not specified',
          'vehicle_plate': 'Not specified',
        };
      } else {
        developer.log('✅ Final vehicle data: $vehicleData', name: 'RideDetails');
      }

      // Fetch driver rating using actual driver ID
      final ratingResponse = await _supabase
          .from('driver_ratings')
          .select('rating')
          .eq('driver_id', actualDriverId);

      final ratings = (ratingResponse as List).map((r) => r['rating'] as double).toList();
      final avgRating = ratings.isEmpty ? 0.0 : ratings.reduce((a, b) => a + b) / ratings.length;

      // Calculate fare for this ride
      _calculateFare(rideResponse);

      setState(() {
        _rideData = {
          ...rideResponse,
          'vehicle': vehicleData,
          'driver_rating': avgRating,
          'total_ratings': ratings.length,
        };
        _driverData = driverResponse;
        _isLoading = false;
      });

      developer.log('✅ All data loaded successfully', name: 'RideDetails');
    } catch (e, stackTrace) {
      developer.log('❌ Error loading ride details: $e', name: 'RideDetails', error: e, stackTrace: stackTrace);
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _calculateFare(Map<String, dynamic> rideData) {
    try {
      // Use passenger's selected coordinates if available, otherwise use driver's route
      final startLat = widget.passengerPickupLat ?? rideData['from_lat'] as double?;
      final startLon = widget.passengerPickupLng ?? rideData['from_lng'] as double?;
      final destLat = widget.passengerDestinationLat ?? rideData['to_lat'] as double?;
      final destLon = widget.passengerDestinationLng ?? rideData['to_lng'] as double?;
      final scheduledTime = DateTime.parse(rideData['scheduled_time'] as String);
      
      developer.log('💰 Calculating fare for journey:', name: 'RideDetails');
      developer.log('   From: ($startLat, $startLon)', name: 'RideDetails');
      developer.log('   To: ($destLat, $destLon)', name: 'RideDetails');

      if (startLat == null || startLon == null || destLat == null || destLon == null) {
        developer.log('⚠️ Missing coordinates for fare calculation', name: 'RideDetails');
        _calculatedFare = 5.0; // Use minimum fare as fallback
        return;
      }

      // Calculate distance
      final distanceKm = DistanceHelper.calculateDistance(
        lat1: startLat,
        lon1: startLon,
        lat2: destLat,
        lon2: destLon,
      );

      // Calculate student fare with surge pricing
      _calculatedFare = _fareService.calculateStudentFare(
        distanceInKm: distanceKm,
        tripDateTime: scheduledTime,
      );

      developer.log(
        '💰 Fare calculated: ${_fareService.formatFare(_calculatedFare!)} '
        'for ${DistanceHelper.formatDistance(distanceKm)}',
        name: 'RideDetails',
      );
    } catch (e) {
      developer.log('❌ Error calculating fare: $e', name: 'RideDetails');
      _calculatedFare = 5.0; // Use minimum fare as fallback
    }
  }

  void _setupRealtimeListener() {
    // Listen for real-time updates to the ride
    _supabase
        .channel('ride_${widget.rideId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'rides',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.rideId,
          ),
          callback: (payload) {
            developer.log('🔄 Ride updated in real-time: ${payload.newRecord}', name: 'RideDetails');
            _loadRideDetails(); // Reload data
          },
        )
        .subscribe();

    // Listen for real-time updates to bookings (for status changes)
    _supabase
        .channel('bookings_${widget.rideId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'bookings',
          callback: (payload) {
            developer.log('🔄 Booking updated in real-time', name: 'RideDetails');
            _checkMyBookingStatus(); // Refresh booking status
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _supabase.removeChannel(_supabase.channel('ride_${widget.rideId}'));
    _supabase.removeChannel(_supabase.channel('bookings_${widget.rideId}'));
    super.dispose();
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
      // Check if it's a "ride not found" or deleted ride error
      final isRideDeleted = _error!.contains('Ride not found') || 
                            _error!.contains('0 rows') || 
                            _error!.contains('PGRST116');
      
      return Scaffold(
        appBar: AppBar(title: const Text('Ride Unavailable')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isRideDeleted ? Icons.event_busy : Icons.error_outline, 
                  size: 80, 
                  color: isRideDeleted ? Colors.orange : Colors.red,
                ),
                const SizedBox(height: 24),
                Text(
                  isRideDeleted ? '🚫 Ride No Longer Available' : 'Failed to Load Ride',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  isRideDeleted 
                      ? 'This ride has been cancelled or deleted by the driver.\n\nPlease search for other available rides.'
                      : 'Unable to load ride information. Please try again.',
                  style: theme.textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.search),
                  label: const Text('Find Another Ride'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    backgroundColor: Colors.blue,
                  ),
                ),
                if (!isRideDeleted) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _loadRideDetails,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    if (_rideData == null || _driverData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ride Not Found')),
        body: const Center(child: Text('Ride details not available')),
      );
    }

    // Parse data
    // Priority: 1) Passenger's selected locations, 2) Booking data, 3) Driver's route
    final bool hasBooking = _myBooking != null;
    
    // Use passenger's selected pickup if available, otherwise booking or driver's start
    final fromLocation = widget.passengerPickup ?? 
        (hasBooking 
            ? (_myBooking!['pickup_location'] as String? ?? _rideData!['from_location'] as String)
            : (_rideData!['from_location'] as String));
    
    // Use passenger's selected destination if available, otherwise booking or driver's end
    final toLocation = widget.passengerDestination ?? 
        (hasBooking
            ? (_myBooking!['destination'] as String? ?? _rideData!['to_location'] as String)
            : (_rideData!['to_location'] as String));
    
    developer.log('📍 Displaying route - From: $fromLocation, To: $toLocation', name: 'RideDetails');
    developer.log('   Passenger selected: ${widget.passengerPickup} → ${widget.passengerDestination}', name: 'RideDetails');
    final scheduledTimeUtc = DateTime.parse(_rideData!['scheduled_time'] as String).toUtc();
    final scheduledTimeMalaysia = TimezoneHelper.utcToMalaysia(scheduledTimeUtc);
    // Show passenger's fare if they have a booking, otherwise show calculated fare or driver's base price
    final pricePerSeat = hasBooking
        ? ((_myBooking!['fare_per_seat'] as num?)?.toDouble() ?? _calculatedFare ?? 0.0)
        : (_calculatedFare ?? (_rideData!['price_per_seat'] as num?)?.toDouble() ?? 0.0);
    final availableSeats = _rideData!['available_seats'] as int;
    final rideStatus = _rideData!['ride_status'] as String;
    final rideNotes = _rideData!['ride_notes'] as String?;

    final driverName = _driverData!['full_name'] as String;
    final driverEmail = _driverData!['email'] as String?;
    final driverGender = _driverData!['gender'] as String?;
    final driverRating = (_rideData!['driver_rating'] as num).toDouble();
    final totalRatings = _rideData!['total_ratings'] as int;

    final vehicle = _rideData!['vehicle'] as Map<String, dynamic>?;
    final vehicleModel = vehicle?['vehicle_model'] as String? ?? 'N/A';
    final vehicleColor = vehicle?['vehicle_color'] as String? ?? 'N/A';
    final vehiclePlate = vehicle?['vehicle_plate'] as String? ?? 'N/A';

    return Scaffold(
        appBar: AppBar(
          title: const Text('Ride Details'),
          actions: [
          IconButton(
            icon: const Icon(Icons.message),
            onPressed: () {
              // Use the actual driver_id from the ride data, not the passed parameter
              final actualDriverId = _rideData?['driver_id'] as String?;
              final driverName = _driverData?['full_name'] as String? ?? 'Driver';
              
              if (actualDriverId == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Driver information not available'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatPage(
                    otherUserId: actualDriverId,
                    otherUserName: driverName,
                    rideId: widget.rideId,
                  ),
                ),
              );
            },
            tooltip: 'Message Driver',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRideDetails,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Driver Info Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundImage: _driverData!['avatar_url'] != null
                        ? NetworkImage(_driverData!['avatar_url'])
                        : null,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: _driverData!['avatar_url'] == null
                        ? Text(
                            driverName.isNotEmpty ? driverName[0].toUpperCase() : 'D',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(driverName, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 18),
                            const SizedBox(width: 4),
                            Text('${driverRating.toStringAsFixed(1)} ($totalRatings ratings)'),
                            if (driverGender != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _getGenderColor(driverGender!)
                                      .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _getGenderColor(driverGender!)
                                        .withOpacity(0.3),
                                  ),
                                ),
                                child: Text(
                                  _getGenderDisplay(driverGender!),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: _getGenderColor(driverGender!),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (vehiclePlate != 'Not specified' && vehiclePlate != 'N/A') ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: theme.colorScheme.primary.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.directions_car,
                                  size: 16,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    '$vehicleModel • $vehiclePlate',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.primary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (driverEmail != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.email, size: 16, color: Colors.grey),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  driverEmail,
                                  style: theme.textTheme.bodySmall,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Route Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.route, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('Route', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    children: [
                      const Icon(Icons.trip_origin, color: Colors.green, size: 20),
                      const SizedBox(width: 12),
                      Expanded(child: Text(fromLocation, style: theme.textTheme.bodyLarge)),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Column(
                      children: [
                        SizedBox(height: 4),
                        Icon(Icons.more_vert, size: 16, color: Colors.grey),
                        SizedBox(height: 4),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Colors.red, size: 20),
                      const SizedBox(width: 12),
                      Expanded(child: Text(toLocation, style: theme.textTheme.bodyLarge)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Ride Info Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('Ride Information', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(height: 24),
                  _buildInfoRow(Icons.access_time, 'Departure', TimezoneHelper.formatMalaysiaDateTime(scheduledTimeMalaysia), theme),
                  const SizedBox(height: 12),
                  _buildInfoRow(Icons.event_seat, 'Available Seats', '$availableSeats', theme),
                  const SizedBox(height: 12),
                  _buildInfoRow(Icons.payments, 'Price per Seat', 'RM ${pricePerSeat.toStringAsFixed(2)}', theme),
                  const SizedBox(height: 12),
                  _buildInfoRow(
                    Icons.circle,
                    'Status',
                    rideStatus.toUpperCase(),
                    theme,
                    valueColor: rideStatus == 'active' ? Colors.green : Colors.orange,
                  ),
                  if (rideNotes != null) ...[
                    const SizedBox(height: 12),
                    _buildInfoRow(Icons.notes, 'Notes', rideNotes, theme),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Vehicle Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.directions_car, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('Vehicle', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(height: 24),
                  _buildInfoRow(Icons.car_rental, 'Model', vehicleModel, theme),
                  const SizedBox(height: 12),
                  _buildInfoRow(Icons.palette, 'Color', vehicleColor, theme),
                  const SizedBox(height: 12),
                  _buildInfoRow(Icons.confirmation_number, 'Plate Number', vehiclePlate, theme),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomActions(context, rideStatus, availableSeats),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, ThemeData theme, {Color? valueColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: valueColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActions(BuildContext context, String rideStatus, int availableSeats) {
    final bookingStatus = _myBooking?['request_status'] as String?;
    final theme = Theme.of(context);
    final seatsRequested = _myBooking?['seats_requested'] as int? ?? 1; // Always 1 seat per passenger
    final farePerSeat = (_myBooking?['fare_per_seat'] as num?)?.toDouble() ?? 0.0;
    final totalFare = farePerSeat * seatsRequested;

    // Show status banner if booking exists
    if (bookingStatus != null) {
      if (bookingStatus == 'accepted') {
        // SPECIAL UI FOR APPROVED STATUS
        return SafeArea(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.green.shade50, Colors.green.shade100],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border(
                top: BorderSide(color: Colors.green.shade400, width: 3),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Success icon with animation effect
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_circle,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Approved text
                  Text(
                    '✅ RIDE APPROVED!',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.green.shade900,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You\'re all set! See you at pickup point.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.green.shade800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  // Booking details card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            Icon(Icons.event_seat, color: Colors.green.shade700),
                            const SizedBox(height: 4),
                            Text(
                              '$seatsRequested ${seatsRequested > 1 ? "Seats" : "Seat"}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                        Container(
                          height: 40,
                          width: 1,
                          color: Colors.grey.shade300,
                        ),
                        Column(
                          children: [
                            Icon(Icons.payments, color: Colors.green.shade700),
                            const SizedBox(height: 4),
                            Text(
                              'RM ${totalFare.toStringAsFixed(2)}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Cancel button (if ride hasn't started)
                  if (rideStatus != 'in_progress' && rideStatus != 'completed') ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _isCancelling ? null : () => _cancelBooking(context),
                      icon: _isCancelling
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.close),
                      label: const Text('Cancel Booking'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade300),
                        minimumSize: const Size(double.infinity, 48),
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    // Track Driver Button (when ride is in progress)
                    ElevatedButton.icon(
                      onPressed: () => _navigateToTracking(context),
                      icon: const Icon(Icons.location_on),
                      label: const Text('Track Driver'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline, size: 16, color: Colors.green.shade700),
                          const SizedBox(width: 8),
                          Text(
                            '🚗 Ride in progress - Track your driver!',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }

      // Regular status UI for other statuses
      Color statusColor;
      IconData statusIcon;
      String statusText;

      switch (bookingStatus) {
        case 'pending':
          statusColor = Colors.orange;
          statusIcon = Icons.pending;
          statusText = 'Request Pending';
          break;
        case 'rejected':
          statusColor = Colors.red;
          statusIcon = Icons.cancel;
          statusText = 'Request Declined';
          break;
        case 'cancelled':
          statusColor = Colors.grey;
          statusIcon = Icons.block;
          statusText = 'Cancelled';
          break;
        default:
          statusColor = Colors.grey;
          statusIcon = Icons.help;
          statusText = bookingStatus;
      }

      return SafeArea(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.1),
            border: Border(top: BorderSide(color: statusColor, width: 2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(statusIcon, color: statusColor),
                  const SizedBox(width: 8),
                  Text(
                    statusText,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              // Show cancel button for pending status
              if (bookingStatus == 'pending') ...[
                if (rideStatus != 'in_progress' && rideStatus != 'completed') ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _isCancelling ? null : () => _cancelBooking(context),
                    icon: _isCancelling
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.close),
                    label: const Text('Cancel Request'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      );
    }

    // Show request button if no booking exists
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton.icon(
          onPressed: (rideStatus == 'active' || rideStatus == 'scheduled') &&
                  availableSeats > 0 &&
                  !_isRequesting
              ? () => _requestRide(context)
              : null,
          icon: _isRequesting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.send),
          label: Text(_isRequesting ? 'Sending Request...' : 'Request Ride'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ),
    );
  }

  Future<void> _requestRide(BuildContext context) async {
    final availableSeats = _rideData!['available_seats'] as int;
    
    // Check if seats available
    if (availableSeats < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ No seats available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    // Calculate fare and show confirmation dialog - ALWAYS 1 SEAT
    final fare = _calculatedFare ?? 5.0; // Use calculated fare or minimum
    final scheduledTime = DateTime.parse(_rideData!['scheduled_time'] as String);
    final surgeInfo = _fareService.getSurgeInfo(scheduledTime);
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Request Ride'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Request 1 seat for this ride?'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Student Fare',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _fareService.formatFare(fare),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      surgeInfo,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '40% student discount applied',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm Request'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() => _isRequesting = true);

    try {
      // Use passenger's selected pickup/destination, or fall back to ride's locations
      final pickupLocation = widget.passengerPickup ?? _rideData!['from_location'] as String;
      final pickupLat = widget.passengerPickupLat ?? _rideData!['from_lat'] as double?;
      final pickupLng = widget.passengerPickupLng ?? _rideData!['from_lng'] as double?;
      final destination = widget.passengerDestination ?? _rideData!['to_location'] as String;
      final destinationLat = widget.passengerDestinationLat ?? _rideData!['to_lat'] as double?;
      final destinationLng = widget.passengerDestinationLng ?? _rideData!['to_lng'] as double?;
      
      developer.log('📤 Requesting ride with:', name: 'RideDetails');
      developer.log('   Pickup: $pickupLocation ($pickupLat, $pickupLng)', name: 'RideDetails');
      developer.log('   Destination: $destination ($destinationLat, $destinationLng)', name: 'RideDetails');
      developer.log('   Fare: RM ${fare.toStringAsFixed(2)}', name: 'RideDetails');
      
      await _requestService.requestRide(
        rideId: widget.rideId,
        farePerSeat: fare, // Pass the calculated student fare
        pickupLocation: pickupLocation, // Passenger's actual pickup location
        pickupLat: pickupLat, // Pickup coordinates
        pickupLng: pickupLng,
        destination: destination, // Passenger's actual destination
        destinationLat: destinationLat, // Destination coordinates
        destinationLng: destinationLng,
        seatsRequested: 1, // ALWAYS 1 SEAT
      );

      if (mounted) {
        await _checkMyBookingStatus(); // Refresh booking status
        
        // Navigate back to dashboard with success message
        Navigator.of(context).popUntil((route) => route.isFirst);
        
        // Show success dialog with prominent message
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                icon: const Icon(Icons.check_circle, color: Colors.green, size: 64),
                title: const Text('Request Sent!', textAlign: TextAlign.center),
                content: const Text(
                  'Your ride request has been sent to the driver.\n\n'
                  'Check "My Ride Requests" on the dashboard for updates.',
                  textAlign: TextAlign.center,
                ),
                actions: [
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      minimumSize: const Size(double.infinity, 45),
                    ),
                    child: const Text('View My Requests'),
                  ),
                ],
              ),
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRequesting = false);
      }
    }
  }

  Future<void> _cancelBooking(BuildContext context) async {
    // Show dialog to get cancellation reason
    final reason = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Cancel Booking'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Please provide a reason for cancellation:'),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: 'e.g., Change of plans',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Keep Booking'),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please provide a reason'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                Navigator.pop(context, controller.text.trim());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('Cancel Booking'),
            ),
          ],
        );
      },
    );

    if (reason == null || reason.isEmpty) return;

    setState(() => _isCancelling = true);

    try {
      final bookingId = _myBooking!['id'] as String;
      developer.log('🛑 Cancelling booking $bookingId. Reason: $reason', name: 'RideDetails');

      final result = await _bookingService.cancelBooking(bookingId);

      if (mounted) {
        await _checkMyBookingStatus(); // Refresh booking status
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: result.success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCancelling = false);
      }
    }
  }

  /// Navigate to driver tracking page
  Future<void> _navigateToTracking(BuildContext context) async {
    try {
      // Verify tracking data exists before navigating
      developer.log('🗺️ Checking tracking data availability', name: 'RideDetails');
      
      final trackingData = await _supabase
          .from('ride_tracking')
          .select()
          .eq('ride_id', widget.rideId)
          .eq('is_active', true)
          .maybeSingle();

      if (trackingData == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Driver location not available yet. Please wait...'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // Get pickup coordinates
      final fromLat = _rideData!['from_lat'] as double?;
      final fromLng = _rideData!['from_lng'] as double?;

      if (fromLat == null || fromLng == null) {
        throw Exception('Pickup location not available');
      }

      // Get destination coordinates
      final toLat = widget.passengerDestinationLat ?? _rideData!['to_lat'] as double?;
      final toLng = widget.passengerDestinationLng ?? _rideData!['to_lng'] as double?;
      final destinationName = widget.passengerDestination ?? _rideData!['to_location'] as String?;

      // Navigate to tracking page
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TrackDriverPageMqtt(
              driverId: widget.driverId,
              pickupLat: fromLat,
              pickupLng: fromLng,
              rideId: widget.rideId,
              bookingId: _myBooking?['id'] as String?,
              destinationLat: toLat,
              destinationLng: toLng,
              destinationName: destinationName,
            ),
          ),
        );
      }
    } catch (e) {
      developer.log('❌ Error navigating to tracking: $e', name: 'RideDetails');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Unable to open tracking: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Get gender display text
  String _getGenderDisplay(String gender) {
    switch (gender) {
      case 'female':
        return '♀ Female';
      case 'male':
        return '♂ Male';
      case 'non_binary':
        return '⚧ Non-Binary';
      default:
        return '';
    }
  }

  /// Get gender color
  Color _getGenderColor(String gender) {
    switch (gender) {
      case 'female':
        return Colors.pink;
      case 'male':
        return Colors.blue;
      case 'non_binary':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }
}

