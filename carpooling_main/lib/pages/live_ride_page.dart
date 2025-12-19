import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:carpooling_main/services/directions_service.dart';
import 'package:carpooling_main/services/sos_service.dart';
import 'package:carpooling_main/services/trip_sharing_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:developer' as developer;

/// Live ride tracking page - Shows driver location during the ride
class LiveRidePage extends StatefulWidget {
  final String rideId;
  final String bookingId;
  final double destinationLat;
  final double destinationLng;
  final String destinationName;

  const LiveRidePage({
    super.key,
    required this.rideId,
    required this.bookingId,
    required this.destinationLat,
    required this.destinationLng,
    required this.destinationName,
  });

  @override
  State<LiveRidePage> createState() => _LiveRidePageState();
}

class _LiveRidePageState extends State<LiveRidePage> {
  final _supabase = Supabase.instance.client;
  final _sosService = SosService();
  final _tripSharingService = TripSharingService();
  GoogleMapController? _mapController;
  StreamSubscription? _locationSubscription;
  
  LatLng? _driverLocation;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  
  String _distance = 'Calculating...';
  String _eta = 'Calculating...';
  bool _isCalculatingRoute = false;
  String? _routeError;
  bool _isSosActive = false;

  @override
  void initState() {
    super.initState();
    _startLocationTracking();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  void _startLocationTracking() {
    developer.log('🗺️ Starting live ride tracking for ride: ${widget.rideId}', name: 'LiveRidePage');
    
    _locationSubscription = _supabase
        .from('ride_tracking')
        .stream(primaryKey: ['id'])
        .listen((data) {
          developer.log('📍 Received tracking data: ${data.length} items', name: 'LiveRidePage');
          
          // Filter for active tracking of this ride
          final activeTracking = data.where((item) {
            try {
              final rideId = item['ride_id']?.toString();
              final isActive = item['is_active'] == true;
              return rideId == widget.rideId && isActive;
            } catch (e) {
              developer.log('⚠️ Error filtering tracking item: $e', name: 'LiveRidePage');
              return false;
            }
          }).toList();

          if (activeTracking.isEmpty) {
            developer.log('⚠️ No active tracking data found', name: 'LiveRidePage');
            return;
          }

          final location = activeTracking.first;
          _updateDriverLocation(location);
        },
        onError: (error) {
          developer.log('❌ Location stream error: $error', name: 'LiveRidePage');
        },
      );
  }

  void _updateDriverLocation(Map<String, dynamic> location) {
    try {
      final lat = (location['latitude'] as num?)?.toDouble();
      final lng = (location['longitude'] as num?)?.toDouble();
      
      if (lat == null || lng == null) {
        developer.log('⚠️ Invalid coordinates in tracking data', name: 'LiveRidePage');
        return;
      }

      final newLocation = LatLng(lat, lng);
      developer.log('📍 Driver location: $lat, $lng', name: 'LiveRidePage');

      if (mounted) {
        setState(() {
          _driverLocation = newLocation;
        });

        _updateMarkers();
        _fetchRouteAndETA();
        _moveCameraToShowRoute();
      }
    } catch (e) {
      developer.log('❌ Error updating driver location: $e', name: 'LiveRidePage');
    }
  }

  void _updateMarkers() {
    if (_driverLocation == null) return;

    try {
      final newMarkers = <Marker>{};

      // Driver marker
      newMarkers.add(Marker(
        markerId: const MarkerId('driver'),
        position: _driverLocation!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: const InfoWindow(title: 'Driver Location'),
      ));

      // Destination marker
      newMarkers.add(Marker(
        markerId: const MarkerId('destination'),
        position: LatLng(widget.destinationLat, widget.destinationLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: widget.destinationName),
      ));

      setState(() {
        _markers = newMarkers;
      });
    } catch (e) {
      developer.log('❌ Error updating markers: $e', name: 'LiveRidePage');
    }
  }

  Future<void> _fetchRouteAndETA() async {
    if (_driverLocation == null || _isCalculatingRoute) return;

    setState(() {
      _isCalculatingRoute = true;
      _routeError = null;
    });

    try {
      final directionsService = DirectionsService();
      final result = await directionsService.getDirections(
        origin: _driverLocation!,
        destination: LatLng(widget.destinationLat, widget.destinationLng),
      );

      if (result != null && mounted) {
        final routePoints = DirectionsService.decodePolyline(result.polylinePoints);
        
        setState(() {
          _distance = result.distanceText;
          _eta = result.durationInTrafficText ?? result.durationText;
          
          _polylines = {
            Polyline(
              polylineId: const PolylineId('route'),
              points: routePoints,
              color: Colors.blue,
              width: 5,
            ),
          };
        });

        developer.log('✅ Route updated: $_distance, ETA: $_eta', name: 'LiveRidePage');
      }
    } catch (e) {
      developer.log('❌ Error fetching route: $e', name: 'LiveRidePage');
      setState(() {
        _routeError = 'Unable to calculate route';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCalculatingRoute = false;
        });
      }
    }
  }

  void _moveCameraToShowRoute() {
    if (_mapController == null || _driverLocation == null) return;

    try {
      final bounds = LatLngBounds(
        southwest: LatLng(
          _driverLocation!.latitude < widget.destinationLat 
              ? _driverLocation!.latitude 
              : widget.destinationLat,
          _driverLocation!.longitude < widget.destinationLng 
              ? _driverLocation!.longitude 
              : widget.destinationLng,
        ),
        northeast: LatLng(
          _driverLocation!.latitude > widget.destinationLat 
              ? _driverLocation!.latitude 
              : widget.destinationLat,
          _driverLocation!.longitude > widget.destinationLng 
              ? _driverLocation!.longitude 
              : widget.destinationLng,
        ),
      );

      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 100),
      );
    } catch (e) {
      developer.log('❌ Error moving camera: $e', name: 'LiveRidePage');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        // Prevent back navigation during live ride
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please wait for the ride to complete'),
            backgroundColor: Colors.orange,
          ),
        );
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Live Ride'),
          automaticallyImplyLeading: false,
          backgroundColor: Colors.green,
        ),
        body: Stack(
          children: [
            // Google Map
            _driverLocation == null
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Waiting for driver location...'),
                      ],
                    ),
                  )
                : GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _driverLocation!,
                      zoom: 14,
                    ),
                    markers: _markers,
                    polylines: _polylines,
                    myLocationEnabled: false,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    onMapCreated: (controller) {
                      _mapController = controller;
                      _moveCameraToShowRoute();
                    },
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

            // Share Trip Button (floating)
            Positioned(
              top: 16,
              left: 16,
              child: FloatingActionButton(
                onPressed: _shareTrip,
                backgroundColor: Colors.blue,
                child: const Icon(Icons.share, color: Colors.white),
              ),
            ),

            // Info card at bottom
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Card(
                margin: EdgeInsets.zero,
                elevation: 8,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.navigation, color: Colors.green, size: 32),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Heading to Destination',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.destinationName,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: _buildInfoCard(
                              icon: Icons.straighten,
                              label: 'Distance',
                              value: _distance,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildInfoCard(
                              icon: Icons.access_time,
                              label: 'ETA',
                              value: _eta,
                            ),
                          ),
                        ],
                      ),
                      if (_routeError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            _routeError!,
                            style: const TextStyle(color: Colors.orange, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.green, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
      String formattedNumber =
          phone.replaceAll(RegExp(r'[^\d+]'), '');

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
        name: 'LiveRidePage',
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
      developer.log('Error triggering SOS: $e', name: 'LiveRidePage');
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

  Future<void> _shareTrip() async {
    try {
      // Show loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Creating share link...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      // Create trip share
      final result = await _tripSharingService.createTripShare(
        bookingId: widget.bookingId,
        hoursValid: 24,
      );

      // Share the link
      if (mounted) {
        await Share.share(
          'I\'m sharing my trip with you. Track my ride here: ${result.shareLink}\n\n'
          'Destination: ${widget.destinationName}\n'
          'Link expires: ${result.expiresAt.toLocal().toString().substring(0, 16)}',
          subject: 'Trip Share - CampusCar',
        );
      }
    } catch (e) {
      developer.log('Error sharing trip: $e', name: 'LiveRidePage');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing trip: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

