import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlong2;
import 'package:google_maps_flutter/google_maps_flutter.dart' as google_maps;
import 'package:carpooling_main/core/network/mqtt_service.dart';
import 'package:carpooling_main/core/network/mqtt_config.dart';
import 'package:carpooling_main/services/driver_tracking_controller.dart';
import 'package:carpooling_main/services/sos_service.dart';
import 'package:carpooling_main/services/directions_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:developer' as developer;

/// Page to track driver location in real-time using MQTT
class TrackDriverPageMqtt extends StatefulWidget {
  final String driverId;
  final double pickupLat;
  final double pickupLng;
  final String? rideId;
  final String? bookingId;
  final double? destinationLat;
  final double? destinationLng;
  final String? destinationName;

  const TrackDriverPageMqtt({
    super.key,
    required this.driverId,
    required this.pickupLat,
    required this.pickupLng,
    this.rideId,
    this.bookingId,
    this.destinationLat,
    this.destinationLng,
    this.destinationName,
  });

  @override
  State<TrackDriverPageMqtt> createState() => _TrackDriverPageMqttState();
}

class _TrackDriverPageMqttState extends State<TrackDriverPageMqtt> {
  static const String _errorTag = '[TRACK_DRIVER_ERROR]';

  MqttService? _mqttService;
  DriverTrackingController? _trackingController;
  final MapController _mapController = MapController();
  final _supabase = Supabase.instance.client;
  final _sosService = SosService();
  bool _isInitialized = false;
  String? _errorMessage;
  bool _isSosActive = false;
  
  // Tracking state
  bool _isPickedUp = false;
  latlong2.LatLng? _currentTargetLocation;
  String? _currentTargetName;
  String _trackingStatus = 'Heading to pickup';
  RealtimeChannel? _pickupStatusChannel;
  
  // Driver profile
  Map<String, dynamic>? _driverProfile;
  Map<String, dynamic>? _vehicleData;
  
  // Route polyline
  List<latlong2.LatLng> _routePoints = [];
  bool _isCalculatingRoute = false;
  final _directionsService = DirectionsService();

  @override
  void initState() {
    super.initState();
    _loadDriverProfile();
    _checkPickupStatus();
    _initializeTracking();
    _setupPickupStatusListener();
  }
  
  /// Load driver profile and vehicle information
  Future<void> _loadDriverProfile() async {
    try {
      // Load driver profile
      final driverProfile = await _supabase
          .from('profiles')
          .select('id, full_name, email, avatar_url')
          .eq('id', widget.driverId)
          .maybeSingle();
      
      if (driverProfile != null) {
        setState(() {
          _driverProfile = driverProfile;
        });
      }
      
      // Load vehicle data
      final vehicleData = await _supabase
          .from('driver_verifications')
          .select('vehicle_model, vehicle_color, vehicle_plate_number')
          .eq('user_id', widget.driverId)
          .maybeSingle();
      
      if (vehicleData != null) {
        setState(() {
          _vehicleData = vehicleData;
        });
      }
    } catch (e) {
      developer.log(
        'Error loading driver profile: $e',
        name: 'TrackDriverMqtt',
      );
    }
  }
  
  /// Check if passenger has been picked up and update target location
  Future<void> _checkPickupStatus() async {
    if (widget.bookingId == null || widget.rideId == null) {
      // No booking ID, assume not picked up yet
      _updateTargetLocation(
        latlong2.LatLng(widget.pickupLat, widget.pickupLng),
        'Pickup Location',
        'Heading to pickup',
      );
      return;
    }

    try {
      // Check current passenger's pickup status
      final booking = await _supabase
          .from('bookings')
          .select('pickup_status')
          .eq('id', widget.bookingId!)
          .maybeSingle();

      final pickupStatus = booking?['pickup_status'] as String?;
      final isPickedUp = pickupStatus == 'arrived';

      if (isPickedUp) {
        // Passenger has been picked up, check for next pickup or destination
        await _updateTargetAfterPickup();
      } else {
        // Still heading to pickup
        _updateTargetLocation(
          latlong2.LatLng(widget.pickupLat, widget.pickupLng),
          'Pickup Location',
          'Heading to pickup',
        );
      }

      setState(() {
        _isPickedUp = isPickedUp;
      });
    } catch (e) {
      developer.log(
        'Error checking pickup status: $e',
        name: 'TrackDriverMqtt',
      );
      // Default to pickup location
      _updateTargetLocation(
        latlong2.LatLng(widget.pickupLat, widget.pickupLng),
        'Pickup Location',
        'Heading to pickup',
      );
    }
  }

  /// Update target location after passenger is picked up
  Future<void> _updateTargetAfterPickup() async {
    if (widget.rideId == null) {
      // No ride ID, use destination if available
      if (widget.destinationLat != null && widget.destinationLng != null) {
        _updateTargetLocation(
          latlong2.LatLng(widget.destinationLat!, widget.destinationLng!),
          widget.destinationName ?? 'Destination',
          'Heading to destination',
        );
      }
      return;
    }

    try {
      // Get all bookings for this ride
      final bookings = await _supabase
          .from('bookings')
          .select('id, pickup_status, pickup_location, pickup_lat, pickup_lng, passenger_id')
          .eq('ride_id', widget.rideId!)
          .eq('request_status', 'accepted')
          .order('created_at');

      // Find next passenger who hasn't been picked up
      final currentUserId = _supabase.auth.currentUser?.id;
      Map<String, dynamic>? nextPickup;
      
      for (final booking in bookings) {
        final passengerId = booking['passenger_id'] as String;
        final pickupStatus = booking['pickup_status'] as String?;
        
        // Skip current passenger
        if (passengerId == currentUserId) continue;
        
        // Find first passenger not yet picked up
        if (pickupStatus != 'arrived') {
          nextPickup = booking;
          break;
        }
      }

      if (nextPickup != null) {
        // Show next pickup location
        final lat = (nextPickup['pickup_lat'] as num?)?.toDouble();
        final lng = (nextPickup['pickup_lng'] as num?)?.toDouble();
        final location = nextPickup['pickup_location'] as String?;
        
        if (lat != null && lng != null) {
          _updateTargetLocation(
            latlong2.LatLng(lat, lng),
            location ?? 'Next Pickup',
            'Heading to next pickup',
          );
          return;
        }
      }

      // No more pickups, show destination
      if (widget.destinationLat != null && widget.destinationLng != null) {
        _updateTargetLocation(
          latlong2.LatLng(widget.destinationLat!, widget.destinationLng!),
          widget.destinationName ?? 'Destination',
          'Heading to destination',
        );
      } else {
        // Try to get destination from ride
        final ride = await _supabase
            .from('rides')
            .select('to_location, to_lat, to_lng')
            .eq('id', widget.rideId!)
            .maybeSingle();
        
        if (ride != null) {
          final lat = (ride['to_lat'] as num?)?.toDouble();
          final lng = (ride['to_lng'] as num?)?.toDouble();
          final location = ride['to_location'] as String?;
          
          if (lat != null && lng != null) {
            _updateTargetLocation(
              latlong2.LatLng(lat, lng),
              location ?? 'Destination',
              'Heading to destination',
            );
          }
        }
      }
    } catch (e) {
      developer.log(
        'Error updating target after pickup: $e',
        name: 'TrackDriverMqtt',
      );
      // Fallback to destination if available
      if (widget.destinationLat != null && widget.destinationLng != null) {
        _updateTargetLocation(
          latlong2.LatLng(widget.destinationLat!, widget.destinationLng!),
          widget.destinationName ?? 'Destination',
          'Heading to destination',
        );
      }
    }
  }

  /// Update the target location and status
  void _updateTargetLocation(latlong2.LatLng location, String name, String status) {
    setState(() {
      _currentTargetLocation = location;
      _currentTargetName = name;
      _trackingStatus = status;
      // Clear route when target changes
      _routePoints = [];
    });
    
    // Update map camera to show both driver and target location
    final driverLocation = _trackingController?.driverLatLng;
    if (driverLocation != null) {
      // Fetch new route to new target
      _fetchRoute(driverLocation, location);
      
      final bounds = LatLngBounds.fromPoints([driverLocation, location]);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(100),
        ),
      );
    } else {
      // If no driver location yet, center on target location
      _mapController.move(location, 14.0);
    }
  }

  /// Setup real-time listener for pickup status changes
  void _setupPickupStatusListener() {
    if (widget.bookingId == null || widget.rideId == null) return;

    try {
      _pickupStatusChannel = _supabase
          .channel('pickup_status_${widget.bookingId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'bookings',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: widget.bookingId,
            ),
            callback: (payload) {
              developer.log(
                '📡 Pickup status updated: ${payload.newRecord['pickup_status']}',
                name: 'TrackDriverMqtt',
              );
              _checkPickupStatus();
            },
          )
          .subscribe();
    } catch (e) {
      developer.log(
        'Error setting up pickup status listener: $e',
        name: 'TrackDriverMqtt',
      );
    }
  }

  Future<void> _initializeTracking() async {
    try {
      setState(() {
        _isInitialized = false;
        _errorMessage = null;
      });

      // Dispose existing service if already initialized
      if (_trackingController != null) {
        _trackingController!.removeListener(_onTrackingUpdate);
        _trackingController!.dispose();
        _trackingController = null;
      }
      if (_mqttService != null) {
        await _mqttService!.disconnect();
        _mqttService!.dispose();
        _mqttService = null;
      }

      // Wait a bit before creating new instances
      await Future.delayed(const Duration(milliseconds: 300));

      // Create new instances
      _mqttService = MqttService();
      _trackingController = DriverTrackingController(_mqttService!);

      // Listen to tracking updates
      _trackingController!.addListener(_onTrackingUpdate);

      // Start tracking
      developer.log(
        '🚀 Starting tracking for driver: ${widget.driverId}',
        name: 'TrackDriverMqtt',
      );
      developer.log(
        '🚀 Expected topic will be: carpool/drivers/${widget.driverId}/location',
        name: 'TrackDriverMqtt',
      );
      
      final success = await _trackingController!.startTracking(
        driverId: widget.driverId,
        mqttUsername: MqttConfig.passengerUsername,
        mqttPassword: MqttConfig.passengerPassword,
      );

      if (success) {
        developer.log(
          '✅ Tracking started successfully',
          name: 'TrackDriverMqtt',
        );
        setState(() {
          _isInitialized = true;
          _errorMessage = null;
        });
      } else {
        developer.log(
          '❌ $_errorTag Failed to start tracking',
          name: 'TrackDriverMqtt',
        );
        final diagnostic = _trackingController?.lastErrorMessage;
        // Clean up diagnostic message - remove duplicate tags and format nicely
        String? cleanDiagnostic;
        if (diagnostic != null) {
          cleanDiagnostic = diagnostic
              .replaceAll(RegExp(r'\[TRACK_DRIVER_ERROR\]\s*'), '')
              .trim();
          // Remove duplicate lines (case-insensitive comparison)
          final seen = <String>{};
          final uniqueLines = <String>[];
          for (final line in cleanDiagnostic.split('\n')) {
            final normalized = line.trim().toLowerCase();
            if (normalized.isNotEmpty && !seen.contains(normalized)) {
              seen.add(normalized);
              uniqueLines.add(line.trim());
            }
          }
          cleanDiagnostic = uniqueLines.join('\n');
          
          // If it's just a timeout message, simplify it
          if (cleanDiagnostic.toLowerCase().contains('timeout') && 
              cleanDiagnostic.toLowerCase().contains('connack')) {
            cleanDiagnostic = 'Connection timeout: Unable to reach server. Please check your network connection.';
          }
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..removeCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: const Text('Unable to connect to real-time server'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 4),
              ),
            );
        }
        setState(() {
          _errorMessage = 'Unable to connect to real-time server.\n\n'
              '${cleanDiagnostic ?? 'Please check your network connection and try again.'}\n\n'
              'Tap Retry to try again.';
        });
      }
    } catch (e, stackTrace) {
      developer.log(
        '❌ $_errorTag Error initializing tracking: $e',
        name: 'TrackDriverMqtt',
        error: e,
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..removeCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Unable to connect to real-time server'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
      }
      setState(() {
        _errorMessage = 'Unable to connect to real-time server.\n\n'
            'Please check your network connection and try again.\n\n'
            'Tap Retry to try again.';
      });
    }
  }

  void _onTrackingUpdate() {
    if (!mounted) return;

    final driverLocation = _trackingController?.driverLatLng;
    final targetLocation = _currentTargetLocation ?? latlong2.LatLng(widget.pickupLat, widget.pickupLng);
    
    if (driverLocation != null) {
      // Fetch route when driver location updates
      _fetchRoute(driverLocation, targetLocation);
      
      // Fit camera to show both driver and pickup/destination locations
      final bounds = LatLngBounds.fromPoints([driverLocation, targetLocation]);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(100), // Add padding so markers aren't at edge
        ),
      );
    }

    setState(() {});
  }
  
  /// Fetch route from Google Directions API
  Future<void> _fetchRoute(latlong2.LatLng origin, latlong2.LatLng destination) async {
    if (_isCalculatingRoute) return;
    
    // Only fetch route if driver location has changed significantly
    // (to avoid too many API calls)
    if (_routePoints.isNotEmpty) {
      final lastRouteStart = _routePoints.first;
      final distance = const latlong2.Distance().as(
        latlong2.LengthUnit.Meter,
        origin,
        lastRouteStart,
      );
      // Only refetch if driver moved more than 100 meters
      if (distance < 100) {
        return;
      }
    }
    
    setState(() {
      _isCalculatingRoute = true;
    });
    
    try {
      // Convert latlong2 LatLng to Google Maps LatLng
      final googleOrigin = google_maps.LatLng(origin.latitude, origin.longitude);
      final googleDestination = google_maps.LatLng(destination.latitude, destination.longitude);
      
      final result = await _directionsService.getDirections(
        origin: googleOrigin,
        destination: googleDestination,
      );
      
      if (result != null && mounted) {
        // Decode polyline to list of points
        final googlePoints = DirectionsService.decodePolyline(result.polylinePoints);
        
        // Convert Google Maps LatLng back to latlong2 LatLng
        final routePoints = googlePoints.map((p) => latlong2.LatLng(p.latitude, p.longitude)).toList();
        
        setState(() {
          _routePoints = routePoints;
          _isCalculatingRoute = false;
        });
        
        developer.log(
          '✅ Route updated: ${routePoints.length} points',
          name: 'TrackDriverMqtt',
        );
      } else {
        setState(() {
          _isCalculatingRoute = false;
        });
      }
    } catch (e) {
      developer.log(
        '❌ Error fetching route: $e',
        name: 'TrackDriverMqtt',
      );
      setState(() {
        _isCalculatingRoute = false;
        // Fallback to straight line if route fetch fails
        _routePoints = [origin, destination];
      });
    }
  }

  @override
  void dispose() {
    _trackingController?.removeListener(_onTrackingUpdate);
    // Dispose tracking controller first, then MQTT service
    _trackingController?.dispose();
    _trackingController = null;
    _mqttService?.dispose();
    _mqttService = null;
    _pickupStatusChannel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Driver'),
        backgroundColor: Colors.blue,
      ),
      body: _errorMessage != null
          ? SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: 220,
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _errorMessage = null;
                              _isInitialized = false;
                            });
                            _initializeTracking();
                          },
                          child: const Text('Retry'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : !_isInitialized
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Connecting to tracking service...'),
                      SizedBox(height: 8),
                      Text(
                        'Please wait while we connect to the driver\'s location.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : _buildMap(),
    );
  }

  Widget _buildMap() {
    final driverLocation = _trackingController?.driverLatLng;
    final speed = _trackingController?.currentSpeedKmh;
    final targetLocation = _currentTargetLocation ?? latlong2.LatLng(widget.pickupLat, widget.pickupLng);
    final etaText = _estimateEtaText(
      driverLocation: driverLocation,
      targetLocation: targetLocation,
      speedKmh: speed,
    );

    return Stack(
      children: [
        // OpenStreetMap
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: driverLocation ?? targetLocation,
            initialZoom: 14.0,
            minZoom: 10.0,
            maxZoom: 18.0,
            onMapReady: () {
              // Fit camera to show both driver and pickup location when map is ready
              if (driverLocation != null) {
                final bounds = LatLngBounds.fromPoints([driverLocation, targetLocation]);
                _mapController.fitCamera(
                  CameraFit.bounds(
                    bounds: bounds,
                    padding: const EdgeInsets.all(100),
                  ),
                );
              } else {
                // If no driver location yet, center on pickup location
                _mapController.move(targetLocation, 14.0);
              }
            },
          ),
          children: [
            // OpenStreetMap tiles
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.tarc.campuscar',
            ),

            // Route polyline (following actual roads)
            if (driverLocation != null)
              PolylineLayer(
                polylines: [
                  if (_routePoints.isNotEmpty)
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 5.0,
                      color: Colors.blue.withValues(alpha: 0.7),
                    )
                  else
                    // Fallback to straight line while route is being calculated
                    Polyline(
                      points: [driverLocation, targetLocation],
                      strokeWidth: 4.0,
                      color: Colors.blue.withValues(alpha: 0.4),
                    ),
                ],
              ),

            // Driver marker with smooth updates (always show if location available)
            if (driverLocation != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: driverLocation,
                    width: 50,
                    height: 50,
                    child: _buildDriverMarker(speed),
                  ),
                ],
              ),

            // Target location marker (pickup or destination) - ALWAYS visible
            MarkerLayer(
              markers: [
                Marker(
                  point: targetLocation,
                  width: 50,
                  height: 50,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      _isPickedUp && _trackingStatus.contains('destination')
                          ? Icons.flag
                          : Icons.location_on,
                      color: _isPickedUp && _trackingStatus.contains('destination')
                          ? Colors.red
                          : Colors.green,
                      size: 40,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),

        // Info card
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Driver profile section
                  if (_driverProfile != null) ...[
                    Row(
                      children: [
                        // Driver avatar or icon
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.blue.shade100,
                          backgroundImage: _driverProfile!['avatar_url'] != null &&
                                  (_driverProfile!['avatar_url'] as String).isNotEmpty
                              ? NetworkImage(_driverProfile!['avatar_url'] as String)
                              : null,
                          onBackgroundImageError: (_, __) {
                            // Handle image load error silently
                          },
                          child: _driverProfile!['avatar_url'] == null ||
                                  (_driverProfile!['avatar_url'] as String?)?.isEmpty == true
                              ? Text(
                                  (_driverProfile!['full_name'] as String? ?? 'D')
                                      .substring(0, 1)
                                      .toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _driverProfile!['full_name'] as String? ?? 'Driver',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (_vehicleData != null)
                                Text(
                                  '${_vehicleData!['vehicle_model'] ?? ''} ${_vehicleData!['vehicle_color'] ?? ''} - ${_vehicleData!['vehicle_plate_number'] ?? ''}'
                                      .trim(),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: driverLocation != null
                                ? Colors.green
                                : Colors.orange,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.directions_car,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                  ],
                  
                  // Status section
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: driverLocation != null
                              ? Colors.green
                              : Colors.orange,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.directions_car,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _trackingStatus,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (_currentTargetName != null)
                              Text(
                                _currentTargetName!,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            if (driverLocation != null)
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Colors.green,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'Live tracking active',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  // Driver location details
                  if (driverLocation != null) ...[
                    const Divider(height: 24),
                    Wrap(
                      alignment: WrapAlignment.spaceAround,
                      spacing: 16,
                      runSpacing: 12,
                      children: [
                        _buildInfoItem(
                          icon: Icons.speed,
                          label: 'Speed',
                          value: speed != null
                              ? '${speed.toStringAsFixed(0)} km/h'
                              : '--',
                        ),
                        _buildInfoItem(
                          icon: Icons.route,
                          label: 'ETA',
                          value: etaText,
                        ),
                        _buildInfoItem(
                          icon: Icons.access_time,
                          label: 'Last Update',
                          value: _trackingController?.lastUpdateTime != null
                              ? _formatTime(_trackingController!.lastUpdateTime!)
                              : '--',
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),

        // No location message
        if (driverLocation == null)
          Positioned(
            bottom: 100,
            left: 16,
            right: 16,
            child: Card(
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Waiting for driver location...',
                        style: TextStyle(color: Colors.orange.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // SOS Button (floating)
        Positioned(
          top: 16,
          right: 16,
          child: _isSosActive
              ? Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withValues(alpha: 0.5),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'SOS Active',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                )
              : FloatingActionButton.extended(
                  onPressed: _showSosDialog,
                  backgroundColor: Colors.red,
                  icon: const Icon(Icons.warning, color: Colors.white),
                  label: const Text(
                    'SOS',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
        ),

        // Call + SOS Button (floating)
        Positioned(
          top: 82,
          right: 16,
          child: FloatingActionButton(
            heroTag: 'call_sos_button',
            onPressed: _callCampusSecurityAndTriggerSos,
            backgroundColor: Colors.white,
            child: const Icon(
              Icons.phone_in_talk,
              color: Colors.red,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDriverMarker(double? speed) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(
        Icons.directions_car,
        color: Colors.blue,
        size: 28,
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, size: 24, color: Colors.blue),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inSeconds < 60) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else {
      return '${diff.inHours}h ago';
    }
  }

  String _estimateEtaText({
    required latlong2.LatLng? driverLocation,
    required latlong2.LatLng targetLocation,
    required double? speedKmh,
  }) {
    if (driverLocation == null || speedKmh == null || speedKmh <= 1) {
      return '--';
    }

    final meters = const latlong2.Distance().as(
      latlong2.LengthUnit.Meter,
      driverLocation,
      targetLocation,
    );

    final speedMps = speedKmh / 3.6;
    if (speedMps <= 0) return '--';

    final seconds = (meters / speedMps).round();
    if (seconds.isNaN || seconds.isInfinite || seconds <= 0) return '--';

    final duration = Duration(seconds: seconds);
    return _formatEta(duration);
  }

  String _formatEta(Duration duration) {
    if (duration.inHours >= 1) {
      final hours = duration.inHours;
      final minutes = duration.inMinutes.remainder(60);
      return '${hours}h ${minutes}m';
    }
    if (duration.inMinutes >= 1) {
      return '${duration.inMinutes}m';
    }
    return '${duration.inSeconds}s';
  }

  void _showSosDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning, color: Colors.red, size: 28),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Emergency SOS',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: const Text(
          'This will send your location, vehicle details, and driver information '
          'to your emergency contact and campus security. '
          'Only use this in a real emergency.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _triggerSos();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Trigger SOS'),
          ),
        ],
      ),
    );
  }

  Future<void> _triggerSos() async {
    try {
      setState(() {
        _isSosActive = true;
      });

      final result = await _sosService.triggerSos(
        rideId: widget.rideId,
        bookingId: widget.bookingId,
      );

      final smsDraft = result.smsDraft;
      if (smsDraft != null) {
        final launched = await _sosService.launchSmsComposer(smsDraft);
        if (!launched && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to open SMS app on this device.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Emergency phone numbers are not set. Please set them in Emergency Contacts.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '🚨 SOS triggered! Emergency contacts have been notified.',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      developer.log('Error triggering SOS: $e', name: 'TrackDriverMqtt');
      setState(() {
        _isSosActive = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error triggering SOS: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Call campus security and trigger SOS in one tap
  Future<void> _callCampusSecurityAndTriggerSos() async {
    // Show confirmation dialog first
    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.phone_in_talk, color: Colors.red, size: 28),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Call Campus Security & Trigger SOS',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: const Text(
          'This will:\n\n'
          '1. Call campus security immediately\n'
          '2. Trigger an SOS alert to your emergency contacts\n'
          '3. Send your location and ride details\n\n'
          'Only use this in a real emergency.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Call & Trigger SOS'),
          ),
        ],
      ),
    );

    if (shouldProceed != true) {
      return;
    }

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        return;
      }

      // Get campus security phone from profile
      final profile = await _supabase
          .from('profiles')
          .select('campus_security_phone')
          .eq('id', userId)
          .maybeSingle();

      final phone = profile?['campus_security_phone'] as String?;
      if (phone == null || phone.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Campus security phone not set. Please set it in Emergency Contacts.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Normalize Malaysian phone format
      String formattedNumber = phone.replaceAll(RegExp(r'[^\d+]'), '');

      if (!formattedNumber.startsWith('+')) {
        if (formattedNumber.startsWith('60')) {
          formattedNumber = '+$formattedNumber';
        } else if (formattedNumber.startsWith('0')) {
          formattedNumber = '+60${formattedNumber.substring(1)}';
        } else {
          formattedNumber = '+60$formattedNumber';
        }
      }

      final uri = Uri(scheme: 'tel', path: formattedNumber);

      // Trigger SOS first (records event & notifies contacts)
      await _triggerSos();

      // Then attempt to start the call
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to make phone call'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      developer.log(
        'Error calling campus security: $e',
        name: 'TrackDriverMqtt',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error calling campus security: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

