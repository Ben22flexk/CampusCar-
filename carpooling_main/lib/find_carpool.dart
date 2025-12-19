import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:carpooling_main/in_app_messaging.dart';
import 'package:carpooling_main/services/popular_destinations_service.dart';
import 'package:carpooling_main/services/distance_service.dart';
import 'package:carpooling_main/services/smart_matching_service.dart';
import 'package:carpooling_main/pages/ride_details_page.dart' as ride_details;
import 'package:carpooling_main/core/utils/timezone_helper.dart';
import 'dart:developer' as developer;

// Data Models
@immutable
class LocationData {
  final LatLng coordinates;
  final String address;
  final String displayName;

  const LocationData({
    required this.coordinates,
    required this.address,
    required this.displayName,
  });
}

@immutable
class PlaceSuggestion {
  final String displayName;
  final LatLng coordinates;
  final String type;

  const PlaceSuggestion({
    required this.displayName,
    required this.coordinates,
    required this.type,
  });
}

@immutable
class DriverMatch {
  final String id;
  final String name;
  final String photoUrl;
  final double rating;
  final int totalRatings;
  final String vehicleModel;
  final String vehicleColor;
  final String vehiclePlate;
  final int availableSeats;
  final double distance;
  final String matchType;
  final DateTime departureTime;
  final double price;
  
  // Smart Matching AI fields
  final double? smartMatchScore; // 0.0 to 1.0
  final String? smartMatchScoreDisplay; // e.g., "85%"
  final double? destDistanceKm; // Distance to destination
  
  // Safety fields
  final String? driverGender;
  final bool isVerified;

  const DriverMatch({
    required this.id,
    required this.name,
    required this.photoUrl,
    required this.rating,
    required this.totalRatings,
    required this.vehicleModel,
    required this.vehicleColor,
    required this.vehiclePlate,
    required this.availableSeats,
    required this.distance,
    required this.matchType,
    required this.departureTime,
    required this.price,
    this.smartMatchScore,
    this.smartMatchScoreDisplay,
    this.destDistanceKm,
    this.driverGender,
    this.isVerified = false,
  });
}

// Geocoding Service with caching and optimization
class GeocodingService {
  // Cache for reverse geocoding results (coordinate -> address)
  static final Map<String, String> _reverseCache = {};
  // Cache for forward geocoding results (query -> suggestions)
  static final Map<String, List<PlaceSuggestion>> _forwardCache = {};
  // Timeout for API calls
  static const _apiTimeout = Duration(seconds: 5);
  
  // Generate cache key from coordinates (rounded to 5 decimal places ~1m precision)
  static String _getCacheKey(LatLng coordinates) {
    return '${coordinates.latitude.toStringAsFixed(5)},${coordinates.longitude.toStringAsFixed(5)}';
  }
  
  // Reverse geocoding with caching and optimization
  static Future<String> getAddressFromCoordinates(LatLng coordinates) async {
    final cacheKey = _getCacheKey(coordinates);
    
    // Check cache first
    if (_reverseCache.containsKey(cacheKey)) {
      return _reverseCache[cacheKey]!;
    }
    
    try {
      // Use Nominatim with higher zoom for better precision
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?'
        'format=json&'
        'lat=${coordinates.latitude}&'
        'lon=${coordinates.longitude}&'
        'zoom=18&'
        'addressdetails=1&'
        'accept-language=en',
      );

      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'CampusCar-Carpooling/1.0',
          'Accept': 'application/json',
        },
      ).timeout(_apiTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final address = _formatMalaysiaAddress(data);
        _reverseCache[cacheKey] = address; // Cache the result
        return address;
      }
    } catch (e) {
      debugPrint('Nominatim geocoding error: $e');
    }

    // Fallback to geocoding package
    try {
      final placemarks = await placemarkFromCoordinates(
        coordinates.latitude,
        coordinates.longitude,
      );
      
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final address = _formatPlacemarkAddress(place);
        _reverseCache[cacheKey] = address; // Cache the result
        return address;
      }
    } catch (e) {
      debugPrint('Fallback geocoding error: $e');
    }

    // Last resort: return coordinates
    return 'Lat: ${coordinates.latitude.toStringAsFixed(5)}, Lng: ${coordinates.longitude.toStringAsFixed(5)}';
  }
  
  // Format address specifically for Malaysia
  static String _formatMalaysiaAddress(Map<String, dynamic> data) {
    try {
      final address = data['address'] as Map<String, dynamic>?;
      if (address == null) return data['display_name'] ?? 'Unknown location';
      
      // Build address components in Malaysia format
      final components = <String>[];
      
      // Building/House
      if (address['building'] != null) components.add(address['building']);
      if (address['house_number'] != null && address['road'] != null) {
        components.add('${address['house_number']} ${address['road']}');
      } else if (address['road'] != null) {
        components.add(address['road']);
      }
      
      // Area/Neighbourhood
      if (address['neighbourhood'] != null) components.add(address['neighbourhood']);
      if (address['suburb'] != null) components.add(address['suburb']);
      
      // City
      if (address['city'] != null) {
        components.add(address['city']);
      } else if (address['town'] != null) {
        components.add(address['town']);
      } else if (address['municipality'] != null) {
        components.add(address['municipality']);
      }
      
      // State
      if (address['state'] != null) components.add(address['state']);
      
      // Postcode
      if (address['postcode'] != null) components.add(address['postcode']);
      
      // Return formatted address
      if (components.isNotEmpty) {
        return components.join(', ');
      }
      
      return data['display_name'] ?? 'Unknown location';
    } catch (e) {
      return data['display_name'] ?? 'Unknown location';
    }
  }
  
  // Format placemark address
  static String _formatPlacemarkAddress(Placemark place) {
    final components = <String>[];
    
    if (place.name != null && place.name!.isNotEmpty) components.add(place.name!);
    if (place.street != null && place.street!.isNotEmpty && place.street != place.name) {
      components.add(place.street!);
    }
    if (place.subLocality != null && place.subLocality!.isNotEmpty) {
      components.add(place.subLocality!);
    }
    if (place.locality != null && place.locality!.isNotEmpty) {
      components.add(place.locality!);
    }
    if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) {
      components.add(place.administrativeArea!);
    }
    if (place.postalCode != null && place.postalCode!.isNotEmpty) {
      components.add(place.postalCode!);
    }
    
    return components.isNotEmpty ? components.join(', ') : 'Unknown location';
  }

  // Forward geocoding with caching, debouncing, and Malaysia focus
  static Future<List<PlaceSuggestion>> searchPlaces(String query) async {
    if (query.isEmpty || query.length < 3) return [];
    
    final normalizedQuery = query.trim().toLowerCase();
    
    // Check cache
    if (_forwardCache.containsKey(normalizedQuery)) {
      return _forwardCache[normalizedQuery]!;
    }

    try {
      // Search with Malaysia bias and better parameters
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?'
        'format=json&'
        'q=${Uri.encodeComponent(query)}&'
        'limit=10&'
        'countrycodes=my&'
        'addressdetails=1&'
        'bounded=0&'
        'viewbox=99.6,6.5,119.3,1.2&' // Malaysia bounding box
        'accept-language=en',
      );

      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'CampusCar-Carpooling/1.0',
          'Accept': 'application/json',
        },
      ).timeout(_apiTimeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final suggestions = data.map((item) {
          return PlaceSuggestion(
            displayName: item['display_name'],
            coordinates: LatLng(
              double.parse(item['lat']),
              double.parse(item['lon']),
            ),
            type: item['type'] ?? 'place',
          );
        }).toList();
        
        // Cache results
        _forwardCache[normalizedQuery] = suggestions;
        
        // Limit cache size
        if (_forwardCache.length > 100) {
          _forwardCache.remove(_forwardCache.keys.first);
        }
        
        return suggestions;
      }
    } catch (e) {
      debugPrint('Place search error: $e');
    }

    return [];
  }
  
  // Clear cache if needed
  static void clearCache() {
    _reverseCache.clear();
    _forwardCache.clear();
  }
}

// Find Carpool Page
class FindCarpoolPage extends HookConsumerWidget {
  const FindCarpoolPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destinationController = useTextEditingController();
    final pickupController = useTextEditingController(text: 'Getting your location...');
    // Note: Seat capacity removed - always defaults to 1 seat
    final pickupLocation = useState<LatLng?>(null);
    final destinationLocation = useState<LatLng?>(null);
    final isLoadingLocation = useState<bool>(true);
    final popularDestinations = useState<List<PopularDestination>>([]);
    final isLoadingPopular = useState<bool>(true);
    final routeData = useState<DistanceCalculationResult?>(null);
    final isCalculatingRoute = useState<bool>(false);
    final mapController = useMemoized(() => MapController());

    // Get initial location on mount
    useEffect(() {
      _getInitialLocation(pickupController, pickupLocation, isLoadingLocation);
      return null;
    }, []);

    // Load popular destinations
    useEffect(() {
      Future.microtask(() async {
        try {
          final destinations = await PopularDestinationsService().getTopDestinations(limit: 10);
          popularDestinations.value = destinations;
        } catch (e) {
          debugPrint('Error loading popular destinations: $e');
        } finally {
          isLoadingPopular.value = false;
        }
      });
      return null;
    }, []);

    // Calculate route when both locations are selected
    useEffect(() {
      Future.microtask(() async {
        if (pickupLocation.value != null && destinationLocation.value != null) {
          isCalculatingRoute.value = true;
          try {
            final distanceService = DistanceService();
            final result = await distanceService.calculateDistance(
              origin: pickupLocation.value!,
              destination: destinationLocation.value!,
            );
            routeData.value = result;

            developer.log(
              'Route calculated: ${result.distanceKm}km, Method: ${result.method}, Has polyline: ${result.routePolyline != null}',
              name: 'PassengerRoutePreview'
            );

            if (result.routePolyline == null && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('⚠️ Using estimated route (straight line)'),
                  duration: Duration(seconds: 3),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          } catch (e) {
            debugPrint('Error calculating route: $e');
          } finally {
            isCalculatingRoute.value = false;
          }
        } else {
          routeData.value = null;
        }
      });
      return null;
    }, [pickupLocation.value, destinationLocation.value]);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Find Carpool'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Pickup Location (Pre-filled)
            Text(
              'Pickup Location',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: pickupController,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Pickup From',
                border: const OutlineInputBorder(),
                prefixIcon: isLoadingLocation.value
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.my_location),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.map),
                  onPressed: () async {
                    final result = await Navigator.push<Map<String, dynamic>>(
                      context,
                      MaterialPageRoute(
                        builder: (context) => MapPickerPage(
                          title: 'Select Pickup Location',
                          currentLocation: pickupLocation.value,
                          currentAddress: pickupController.text,
                          allowCurrentLocation: true,
                        ),
                      ),
                    );
                    if (result != null) {
                      pickupLocation.value = result['location'] as LatLng;
                      pickupController.text = result['address'] as String;
                    }
                  },
                  tooltip: 'Select on map',
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Destination Field (Not Pre-filled)
            Text(
              'Destination',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: destinationController,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Where are you going?',
                hintText: 'Tap to select destination',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.location_on),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (destinationController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          destinationController.clear();
                          destinationLocation.value = null;
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.map),
                      onPressed: () async {
                        final result = await Navigator.push<Map<String, dynamic>>(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MapPickerPage(
                              title: 'Select Destination',
                              currentLocation: destinationLocation.value,
                              currentAddress: destinationController.text.isNotEmpty
                                  ? destinationController.text
                                  : null,
                              allowCurrentLocation: false,
                            ),
                          ),
                        );
                        if (result != null) {
                          destinationLocation.value = result['location'] as LatLng;
                          destinationController.text = result['address'] as String;
                        }
                      },
                      tooltip: 'Select on map',
                    ),
                  ],
                ),
              ),
              onTap: () async {
                final result = await Navigator.push<Map<String, dynamic>>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MapPickerPage(
                      title: 'Select Destination',
                      currentLocation: destinationLocation.value,
                      currentAddress: destinationController.text.isNotEmpty
                          ? destinationController.text
                          : null,
                      allowCurrentLocation: false,
                    ),
                  ),
                );
                if (result != null) {
                  destinationLocation.value = result['location'] as LatLng;
                  destinationController.text = result['address'] as String;
                }
              },
            ),
            const SizedBox(height: 24),

            // Route Preview Section
            if (isCalculatingRoute.value) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: const [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('Calculating route...'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ] else if (routeData.value != null && pickupLocation.value != null && destinationLocation.value != null) ...[
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    // Map Header
                    Container(
                      padding: const EdgeInsets.all(12),
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: Row(
                        children: [
                          Icon(Icons.map, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Route Preview',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              routeData.value!.methodDisplay,
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Map with Route
                    SizedBox(
                      height: 200,
                      child: FlutterMap(
                        mapController: mapController,
                        options: MapOptions(
                          initialCenter: pickupLocation.value!,
                          initialZoom: 12.0,
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                          ),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.example.carpooling_main',
                          ),
                          
                          // Route Line
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: () {
                                  final decoded = routeData.value?.decodePolyline();
                                  if (decoded != null && decoded.isNotEmpty) {
                                    return decoded;
                                  } else {
                                    return [
                                      pickupLocation.value!,
                                      destinationLocation.value!,
                                    ];
                                  }
                                }(),
                                color: Theme.of(context).colorScheme.primary,
                                strokeWidth: 4.0,
                              ),
                            ],
                          ),
                          
                          // Markers
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: pickupLocation.value!,
                                width: 40,
                                height: 40,
                                child: const Icon(
                                  Icons.trip_origin,
                                  size: 40,
                                  color: Colors.green,
                                ),
                              ),
                              Marker(
                                point: destinationLocation.value!,
                                width: 40,
                                height: 40,
                                child: const Icon(
                                  Icons.location_on,
                                  size: 40,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                    // Route Info
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _RouteInfoItem(
                            icon: Icons.straighten,
                            label: 'Distance',
                            value: routeData.value!.distanceDisplay,
                          ),
                          Container(
                            width: 1,
                            height: 40,
                            color: Colors.grey.shade300,
                          ),
                          _RouteInfoItem(
                            icon: Icons.access_time,
                            label: 'Duration',
                            value: routeData.value!.durationDisplay,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            // Note: Seat selection removed - automatically set to 1 seat
            const SizedBox(height: 16),

            // Available Rides Section
            if (!isLoadingPopular.value && popularDestinations.value.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.local_taxi, size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Available Rides (Currently Active)',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 135,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: popularDestinations.value.length,
                  itemBuilder: (context, index) {
                    final destination = popularDestinations.value[index];
                    return _PopularDestinationCard(
                      destination: destination,
                      onTap: () {
                        destinationLocation.value = destination.coordinates;
                        destinationController.text = destination.name;
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
            ],
            
            // Search Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isLoadingLocation.value
                    ? null
                    : () {
                        _performSearch(
                          context,
                          destinationController.text,
                          pickupLocation.value,
                          pickupController.text,
                          1, // Always 1 seat per search
                          destinationLocation.value,
                        );
                      },
                icon: const Icon(Icons.search),
                label: const Text('Find Car'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _getInitialLocation(
    TextEditingController controller,
    ValueNotifier<LatLng?> location,
    ValueNotifier<bool> isLoading,
  ) async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final coords = LatLng(position.latitude, position.longitude);
      location.value = coords;

      // Get address
      final address = await GeocodingService.getAddressFromCoordinates(coords);
      controller.text = address;
    } catch (e) {
      debugPrint('Location error: $e');
      // Default to Setapak, KL
      final defaultLocation = LatLng(3.2167, 101.7333);
      location.value = defaultLocation;
      controller.text = 'Setapak, Kuala Lumpur, Malaysia';
    } finally {
      isLoading.value = false;
    }
  }

  void _performSearch(
    BuildContext context,
    String destination,
    LatLng? pickupLocation,
    String pickupAddress,
    int seats,
    LatLng? destinationLocation,
  ) {
    // Validation
    if (pickupLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait for pickup location to be detected'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (destination.isEmpty || destinationLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a destination on the map'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Navigate to loading screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SearchingDriversPage(
          destination: destination,
          pickupLocation: pickupLocation,
          pickupAddress: pickupAddress,
          destinationLocation: destinationLocation,
          seats: seats,
        ),
      ),
    );
  }
}

// Searching Drivers Loading Page
class SearchingDriversPage extends StatefulWidget {
  final String destination;
  final LatLng pickupLocation;
  final String pickupAddress;
  final LatLng destinationLocation;
  final int seats;

  const SearchingDriversPage({
    super.key,
    required this.destination,
    required this.pickupLocation,
    required this.pickupAddress,
    required this.destinationLocation,
    required this.seats,
  });

  @override
  State<SearchingDriversPage> createState() => _SearchingDriversPageState();
}

class _SearchingDriversPageState extends State<SearchingDriversPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    // Simulate API call and auto-navigate
    _searchForDrivers();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _searchForDrivers() async {
    try {
      // 🤖 Use Smart Matching AI Service
      final smartMatchingService = SmartMatchingService();
      
      // Find best matches using hybrid scoring algorithm
      final smartMatches = await smartMatchingService.findBestMatches(
        passengerPickup: widget.pickupLocation,
        passengerDestination: widget.destinationLocation,
        seatsRequired: widget.seats,
        maxWillingnessToPay: 100.0, // Max RM100 per seat
        minRatingThreshold: 0.0, // Accept all ratings
        topN: 10, // Get top 10 matches
        maxDistanceKm: 15.0, // Search within 15km radius
      );

      if (!mounted) return;

      // Convert SmartMatch to DriverMatch with scoring details
      final drivers = smartMatches.map((match) {
        return DriverMatch(
          id: match.rideId,
          name: match.driverName,
          photoUrl: match.driverPhotoUrl ?? 'https://i.pravatar.cc/150?img=33',
          rating: match.driverRating,
          totalRatings: match.driverTotalRatings,
          vehicleModel: match.vehicleModel ?? 'Car',
          vehicleColor: match.vehicleColor ?? 'N/A',
          vehiclePlate: match.vehiclePlateNumber ?? 'N/A',
          availableSeats: match.availableSeats,
          distance: match.pickupDistanceKm,
          matchType: match.matchQualityBadge, // Use AI match quality
          departureTime: match.scheduledTime,
          price: match.fare,
          // Store smart match details for display
          smartMatchScore: match.hybridScore,
          smartMatchScoreDisplay: match.scorePercentage,
          destDistanceKm: match.destDistanceKm,
          // Safety information
          driverGender: match.driverGender,
          isVerified: match.isVerified,
        );
      }).toList();

      debugPrint('🎯 Smart Matching found ${drivers.length} matches');

      // Auto-navigate to driver selection page
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => SelectDriverPage(
            drivers: drivers,
            destination: widget.destination,
            pickupAddress: widget.pickupAddress,
            pickupLocation: widget.pickupLocation,
            destinationLocation: widget.destinationLocation,
          ),
        ),
      );
    } catch (e) {
      debugPrint('❌ Error in smart matching: $e');
      
      if (!mounted) return;

      // Show error and navigate to empty results
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error searching for rides: $e'),
          backgroundColor: Colors.red,
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => SelectDriverPage(
            drivers: const [],
            destination: widget.destination,
            pickupAddress: widget.pickupAddress,
            pickupLocation: widget.pickupLocation,
            destinationLocation: widget.destinationLocation,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.primaryContainer,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  // Animated search icon
                  RotationTransition(
                    turns: _animationController,
                    child: Icon(
                      Icons.search,
                      size: 80,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Loading indicator
                  const CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                  const SizedBox(height: 32),
                  
                  // Title
                  const Text(
                    'Searching for Drivers...',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  
                  // Subtitle
                  Text(
                    'Looking for available drivers near your route',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withOpacity(0.8),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  
                  // Trip details card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: <Widget>[
                        _TripDetailRow(
                          icon: Icons.my_location,
                          label: 'From',
                          value: widget.pickupAddress,
                        ),
                        const SizedBox(height: 12),
                        const Divider(color: Colors.white54),
                        const SizedBox(height: 12),
                        _TripDetailRow(
                          icon: Icons.location_on,
                          label: 'To',
                          value: widget.destination,
                        ),
                        const SizedBox(height: 12),
                        const Divider(color: Colors.white54),
                        const SizedBox(height: 12),
                        _TripDetailRow(
                          icon: Icons.event_seat,
                          label: 'Seats',
                          value: '${widget.seats}',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TripDetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _TripDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 12,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Select Driver Page
class SelectDriverPage extends StatefulWidget {
  final List<DriverMatch> drivers;
  final String destination;
  final String pickupAddress;
  final LatLng? pickupLocation;
  final LatLng? destinationLocation;

  const SelectDriverPage({
    super.key,
    required this.drivers,
    required this.destination,
    required this.pickupAddress,
    this.pickupLocation,
    this.destinationLocation,
  });

  @override
  State<SelectDriverPage> createState() => _SelectDriverPageState();
}

class _SelectDriverPageState extends State<SelectDriverPage> {
  String sortBy = 'match';
  late List<DriverMatch> _drivers;
  StreamSubscription? _ridesSubscription;

  @override
  void initState() {
    super.initState();
    _drivers = widget.drivers;
    _setupRealtimeListener();
  }

  @override
  void dispose() {
    _ridesSubscription?.cancel();
    super.dispose();
  }

  void _setupRealtimeListener() {
    // Listen for real-time ride updates
    try {
      final supabase = Supabase.instance.client;
      
      _ridesSubscription = supabase
          .from('rides')
          .stream(primaryKey: ['id'])
          .inFilter('ride_status', ['active', 'scheduled'])
          .listen((List<Map<String, dynamic>> data) {
            print('🔄 Real-time update: ${data.length} active/scheduled rides');
            // Trigger a re-search when new rides are added
            _refreshSearch();
          });
      
      print('✅ Real-time listener setup for rides');
    } catch (e) {
      print('⚠️ Could not setup real-time listener: $e');
    }
  }

  void _refreshSearch() async {
    try {
      // Show notification that new rides are available
      // User can pull down to manually refresh or navigate back to search again
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🔄 New rides available! Search again to see updates.'),
            duration: Duration(seconds: 3),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      print('Error refreshing search: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_drivers.isEmpty) {
      return _NoDriversFoundPage(
        destination: widget.destination,
        pickupAddress: widget.pickupAddress,
      );
    }

    final sortedDrivers = _sortResults(_drivers);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Driver'),
        actions: <Widget>[
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            onSelected: (value) {
              setState(() {
                sortBy = value;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'match',
                child: Text('Best Match'),
              ),
              const PopupMenuItem(
                value: 'rating',
                child: Text('Highest Rating'),
              ),
              const PopupMenuItem(
                value: 'distance',
                child: Text('Closest'),
              ),
              const PopupMenuItem(
                value: 'time',
                child: Text('Earliest Departure'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          // Trip summary header
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.my_location, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.pickupAddress,
                        style: const TextStyle(fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    const Icon(Icons.location_on, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.destination,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Drivers count
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                Text(
                  '${widget.drivers.length} Drivers Available',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
          
          // Drivers list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: sortedDrivers.length,
              itemBuilder: (context, index) {
                final driver = sortedDrivers[index];
                return _DriverCard(
                  driver: driver,
                  pickupAddress: widget.pickupAddress,
                  destination: widget.destination,
                  pickupLocation: widget.pickupLocation,
                  destinationLocation: widget.destinationLocation,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<DriverMatch> _sortResults(List<DriverMatch> results) {
    final sorted = List<DriverMatch>.from(results);
    switch (sortBy) {
      case 'match':
        // Sort by smart match score (highest first)
        sorted.sort((a, b) => 
          (b.smartMatchScore ?? 0.0).compareTo(a.smartMatchScore ?? 0.0)
        );
        break;
      case 'rating':
        sorted.sort((a, b) => b.rating.compareTo(a.rating));
        break;
      case 'distance':
        sorted.sort((a, b) => a.distance.compareTo(b.distance));
        break;
      case 'time':
        sorted.sort((a, b) => a.departureTime.compareTo(b.departureTime));
        break;
      default:
        // Default to smart match score sorting
        sorted.sort((a, b) => 
          (b.smartMatchScore ?? 0.0).compareTo(a.smartMatchScore ?? 0.0)
        );
        break;
    }
    return sorted;
  }
}

// No Drivers Found Page
class _NoDriversFoundPage extends StatelessWidget {
  final String destination;
  final String pickupAddress;

  const _NoDriversFoundPage({
    required this.destination,
    required this.pickupAddress,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Results'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.search_off,
                size: 80,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 24),
              Text(
                'No Drivers Available',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              Text(
                'We couldn\'t find any drivers for your route at this time.',
                style: TextStyle(color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.edit),
                label: const Text('Adjust Search'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Driver Card
class _DriverCard extends StatelessWidget {
  final DriverMatch driver;
  final String pickupAddress;
  final String destination;
  final LatLng? pickupLocation;
  final LatLng? destinationLocation;

  const _DriverCard({
    required this.driver,
    required this.pickupAddress,
    required this.destination,
    this.pickupLocation,
    this.destinationLocation,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matchColor = _getMatchColor(driver.matchType);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RideDetailsPage(driver: driver),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 30,
                    backgroundImage: driver.photoUrl.isNotEmpty
                        ? NetworkImage(driver.photoUrl)
                        : null,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: driver.photoUrl.isEmpty
                        ? Icon(
                            Icons.person,
                            size: 30,
                            color: theme.colorScheme.onPrimaryContainer,
                          )
                        : null,
                    onBackgroundImageError: (exception, stackTrace) {
                      // Handle image load error silently
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          driver.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: <Widget>[
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                const Icon(Icons.star, size: 16, color: Colors.amber),
                                const SizedBox(width: 4),
                                Text(
                                  driver.rating.toStringAsFixed(1),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  ' (${driver.totalRatings})',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                            // Gender badge
                            if (driver.driverGender != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _getGenderColor(driver.driverGender!).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _getGenderColor(driver.driverGender!).withOpacity(0.3),
                                  ),
                                ),
                                child: Text(
                                  _getGenderDisplay(driver.driverGender!),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: _getGenderColor(driver.driverGender!),
                                  ),
                                ),
                              ),
                            // Verification badge
                            if (driver.isVerified)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.green.withOpacity(0.3),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.verified,
                                      size: 12,
                                      color: Colors.green,
                                    ),
                                    SizedBox(width: 2),
                                    Text(
                                      'Verified',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Text(
                          'RM ${driver.price.toStringAsFixed(2)}',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: matchColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: matchColor),
                          ),
                          child: Text(
                            driver.matchType,
                            style: TextStyle(
                              color: matchColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              // Vehicle Info - More Prominent
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.primary.withOpacity(0.3),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.directions_car,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            driver.vehicleModel,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          Text(
                            driver.vehicleColor,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: theme.colorScheme.secondary.withOpacity(0.5),
                        ),
                      ),
                      child: Text(
                        driver.vehiclePlate,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.secondary,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _InfoChip(
                    icon: Icons.event_seat,
                    label: '${driver.availableSeats} seats left',
                    color: driver.availableSeats <= 1 ? Colors.orange : Colors.green,
                  ),
                  _InfoChip(
                    icon: Icons.access_time,
                    label: _formatTime(driver.departureTime),
                    color: Colors.blue,
                  ),
                  _InfoChip(
                    icon: Icons.location_on,
                    label: '${driver.distance.toStringAsFixed(1)} km',
                    color: Colors.purple,
                  ),
                ],
              ),
              // Smart Matching AI Score Display
              if (driver.smartMatchScore != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.colorScheme.primaryContainer,
                        theme.colorScheme.primaryContainer.withOpacity(0.5),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.insights,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'AI Match Score: ${driver.smartMatchScoreDisplay ?? "N/A"}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            if (driver.destDistanceKm != null)
                              Text(
                                'Destination: ${driver.destDistanceKm!.toStringAsFixed(1)} km away',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.grey.shade600,
                                  fontSize: 10,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _getScoreColor(driver.smartMatchScore!),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _getScoreLabel(driver.smartMatchScore!),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Navigate to new real-time ride details page with passenger's locations
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ride_details.RideDetailsPage(
                          rideId: driver.id,
                          driverId: driver.id,
                          passengerPickup: pickupAddress,
                          passengerDestination: destination,
                          passengerPickupLat: pickupLocation?.latitude,
                          passengerPickupLng: pickupLocation?.longitude,
                          passengerDestinationLat: destinationLocation?.latitude,
                          passengerDestinationLng: destinationLocation?.longitude,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.visibility, size: 18),
                  label: const Text('View Details'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getMatchColor(String matchType) {
    switch (matchType) {
      case 'Best Match':
        return Colors.green;
      case 'Nearby':
        return Colors.blue;
      case 'Further Away':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _formatTime(DateTime time) {
    final now = TimezoneHelper.nowInMalaysia();
    final diff = time.difference(now);

    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m';
    } else {
      return '${diff.inHours}h ${diff.inMinutes % 60}m';
    }
  }

  /// Get color based on smart match score (0.0 to 1.0)
  Color _getScoreColor(double score) {
    if (score >= 0.8) return Colors.green.shade700;
    if (score >= 0.6) return Colors.blue.shade700;
    if (score >= 0.4) return Colors.orange.shade700;
    return Colors.grey.shade700;
  }

  /// Get label based on smart match score (0.0 to 1.0)
  String _getScoreLabel(double score) {
    if (score >= 0.8) return 'EXCELLENT';
    if (score >= 0.6) return 'GREAT';
    if (score >= 0.4) return 'GOOD';
    return 'FAIR';
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

// Info Chip Widget
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _InfoChip({
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? Colors.grey;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: chipColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: chipColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: chipColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// Map Picker Page (for editing location)
class MapPickerPage extends HookWidget {
  final String title;
  final LatLng? currentLocation;
  final String? currentAddress;
  final bool allowCurrentLocation;

  const MapPickerPage({
    super.key,
    required this.title,
    this.currentLocation,
    this.currentAddress,
    this.allowCurrentLocation = true,
  });

  @override
  Widget build(BuildContext context) {
    final mapController = useMemoized(() => MapController());
    final pickedLocation = useState<LatLng?>(currentLocation);
    final locationAddress = useState<String>(currentAddress ?? 'Select a location');
    final isLoadingAddress = useState<bool>(false);
    final searchController = useTextEditingController();
    final searchSuggestions = useState<List<PlaceSuggestion>>([]);
    final showSuggestions = useState<bool>(false);
    final isInitialized = useState<bool>(false);

    // Default center: current location, user's GPS, or Setapak
    final defaultCenter = currentLocation ?? LatLng(3.2167, 101.7333);
    final displayLocation = pickedLocation.value ?? defaultCenter;

    // Initialize location if not provided and allowCurrentLocation is true
    useEffect(() {
      if (currentLocation == null && allowCurrentLocation && !isInitialized.value) {
        _initializeCurrentLocation(pickedLocation, locationAddress, isLoadingAddress);
        isInitialized.value = true;
      }
      return null;
    }, []);

    // Update address when location changes
    useEffect(() {
      if (pickedLocation.value != null && 
          (currentLocation == null || pickedLocation.value != currentLocation)) {
        _updateAddress(pickedLocation.value!, locationAddress, isLoadingAddress);
      }
      return null;
    }, [pickedLocation.value]);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              if (pickedLocation.value != null && locationAddress.value != 'Select a location') {
                Navigator.pop(context, {
                  'location': pickedLocation.value,
                  'address': locationAddress.value,
                });
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please select a location on the map'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Done'),
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          // Map
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              initialCenter: displayLocation,
              initialZoom: 15.0,
              onTap: (tapPosition, point) {
                pickedLocation.value = point;
                showSuggestions.value = false;
              },
            ),
            children: <Widget>[
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.carpooling_main',
              ),
              MarkerLayer(
                markers: <Marker>[
                  Marker(
                    point: displayLocation,
                    width: 40,
                    height: 40,
                    child: const Icon(
                      Icons.location_pin,
                      size: 40,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Search overlay
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.white,
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        labelText: 'Search for a place',
                        hintText: 'Enter landmark or address',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  searchController.clear();
                                  searchSuggestions.value = [];
                                  showSuggestions.value = false;
                                },
                              )
                            : null,
                      ),
                      onChanged: (value) async {
                        if (value.length > 2) {
                          showSuggestions.value = true;
                          final suggestions = await GeocodingService.searchPlaces(value);
                          searchSuggestions.value = suggestions;
                        } else {
                          showSuggestions.value = false;
                          searchSuggestions.value = [];
                        }
                      },
                    ),
                  ),

                  if (showSuggestions.value && searchSuggestions.value.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: searchSuggestions.value.length,
                        itemBuilder: (context, index) {
                          final suggestion = searchSuggestions.value[index];
                          return ListTile(
                            leading: const Icon(Icons.location_on),
                            title: Text(
                              suggestion.displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              pickedLocation.value = suggestion.coordinates;
                              locationAddress.value = suggestion.displayName;
                              searchController.text = suggestion.displayName;
                              showSuggestions.value = false;
                              mapController.move(suggestion.coordinates, 15.0);
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Bottom address display
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Icon(Icons.location_on, color: Colors.blue),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Selected Location',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.grey.shade600,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              isLoadingAddress.value
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Text(
                                      locationAddress.value,
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.w500,
                                          ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap anywhere on the map to change location',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade500,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _initializeCurrentLocation(
    ValueNotifier<LatLng?> location,
    ValueNotifier<String> address,
    ValueNotifier<bool> isLoading,
  ) async {
    try {
      isLoading.value = true;
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final coords = LatLng(position.latitude, position.longitude);
      location.value = coords;

      final fetchedAddress = await GeocodingService.getAddressFromCoordinates(coords);
      address.value = fetchedAddress;
    } catch (e) {
      debugPrint('Location error: $e');
      address.value = 'Tap on map to select location';
    } finally {
      isLoading.value = false;
    }
  }

  void _updateAddress(
    LatLng location,
    ValueNotifier<String> address,
    ValueNotifier<bool> isLoading,
  ) async {
    isLoading.value = true;
    final fetchedAddress = await GeocodingService.getAddressFromCoordinates(location);
    address.value = fetchedAddress;
    isLoading.value = false;
  }
}

// Ride Details Page
class RideDetailsPage extends HookWidget {
  final DriverMatch driver;

  const RideDetailsPage({super.key, required this.driver});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tabController = useTabController(initialLength: 2);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ride Details'),
        centerTitle: true,
      ),
      body: Column(
        children: <Widget>[
          // Driver Profile Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withOpacity(0.3),
            ),
            child: Column(
              children: <Widget>[
                CircleAvatar(
                  radius: 50,
                  backgroundImage: NetworkImage(driver.photoUrl),
                ),
                const SizedBox(height: 12),
                Text(
                  driver.name,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Icon(Icons.star, size: 20, color: Colors.amber),
                    const SizedBox(width: 4),
                    Text(
                      '${driver.rating}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      ' (${driver.totalRatings} reviews)',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Price and Seats Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: <Widget>[
                Column(
                  children: <Widget>[
                    Text(
                      'Price',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'RM ${driver.price.toStringAsFixed(2)}',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.white30,
                ),
                Column(
                  children: <Widget>[
                    Text(
                      'Seats Available',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${driver.availableSeats} / 4',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Tab Bar
          TabBar(
            controller: tabController,
            labelColor: theme.colorScheme.primary,
            indicatorColor: theme.colorScheme.primary,
            tabs: const <Widget>[
              Tab(text: 'About'),
              Tab(text: 'Reviews'),
            ],
          ),
          
          // Tab Views
          Expanded(
            child: TabBarView(
              controller: tabController,
              children: <Widget>[
                _AboutTab(driver: driver),
                _ReviewsTab(driver: driver),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Expanded(
                flex: 1,
                child: OutlinedButton.icon(
                  onPressed: () {
                    _showContactDialog(context, driver);
                  },
                  icon: const Icon(Icons.chat),
                  label: const Text('Contact'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: () {
                    _showBookingDialog(context, driver);
                  },
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Request Ride'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showContactDialog(BuildContext context, DriverMatch driver) async {
    // Fetch driver's phone number from database
    String? driverPhone;
    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('phone_number')
          .eq('id', driver.id)
          .maybeSingle();
      
      if (profile != null && profile['phone_number'] != null) {
        driverPhone = profile['phone_number'] as String;
      }
    } catch (e) {
      developer.log('Error fetching driver phone: $e', name: 'FindCarpool');
    }

    // Navigate directly to in-app messaging
    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => InAppMessagingPage(
            recipientName: driver.name,
            recipientPhone: driverPhone,
            recipientAvatar: driver.photoUrl,
            recipientId: driver.id,
            isDriver: true,
          ),
        ),
      );
    }
  }

  void _showBookingDialog(BuildContext context, DriverMatch driver) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Ride Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Driver: ${driver.name}'),
            const SizedBox(height: 8),
            Text('Vehicle: ${driver.vehicleModel} (${driver.vehicleColor})'),
            const SizedBox(height: 8),
            Text('Price: RM ${driver.price.toStringAsFixed(2)}'),
            const SizedBox(height: 8),
            Text('Departure: ${_formatDateTime(driver.departureTime)}'),
            const SizedBox(height: 16),
            const Text(
              'Send a ride request to this driver?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Ride request sent successfully!'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} at $hour:$minute';
  }
}

// About Tab
class _AboutTab extends StatelessWidget {
  final DriverMatch driver;

  const _AboutTab({required this.driver});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Trip Information
          Text(
            'Trip Information',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: <Widget>[
                  _InfoRow(
                    icon: Icons.access_time,
                    label: 'Departure Time',
                    value: _formatTime(driver.departureTime),
                  ),
                  const Divider(height: 24),
                  _InfoRow(
                    icon: Icons.event_seat,
                    label: 'Available Seats',
                    value: '${driver.availableSeats} / 4',
                  ),
                  const Divider(height: 24),
                  _InfoRow(
                    icon: Icons.location_on,
                    label: 'Distance',
                    value: '${driver.distance.toStringAsFixed(1)} km',
                  ),
                  const Divider(height: 24),
                  _InfoRow(
                    icon: Icons.attach_money,
                    label: 'Price',
                    value: 'RM ${driver.price.toStringAsFixed(2)}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // Vehicle Information
          Text(
            'Vehicle Information',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: <Widget>[
                  _InfoRow(
                    icon: Icons.directions_car,
                    label: 'Model',
                    value: driver.vehicleModel,
                  ),
                  const Divider(height: 24),
                  _InfoRow(
                    icon: Icons.palette,
                    label: 'Color',
                    value: driver.vehicleColor,
                  ),
                  const Divider(height: 24),
                  _InfoRow(
                    icon: Icons.pin,
                    label: 'Plate Number',
                    value: driver.vehiclePlate,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // Co-Passengers (Mock Data)
          Text(
            'Co-Passengers',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: <Widget>[
                  if (driver.availableSeats == 4)
                    Center(
                      child: Text(
                        'No passengers yet. Be the first!',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    )
                  else
                    ..._buildCoPassengersList(4 - driver.availableSeats),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCoPassengersList(int count) {
    final passengers = [
      {'name': 'Lisa Wong', 'avatar': 'https://i.pravatar.cc/150?img=5'},
      {'name': 'David Chen', 'avatar': 'https://i.pravatar.cc/150?img=13'},
      {'name': 'Sarah Ali', 'avatar': 'https://i.pravatar.cc/150?img=23'},
    ];

    final widgets = <Widget>[];
    for (int i = 0; i < count && i < passengers.length; i++) {
      if (i > 0) {
        widgets.add(const Divider(height: 24));
      }
      widgets.add(
        Row(
          children: <Widget>[
            CircleAvatar(
              radius: 20,
              backgroundImage: NetworkImage(passengers[i]['avatar']!),
            ),
            const SizedBox(width: 12),
            Text(
              passengers[i]['name']!,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }
    return widgets;
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '${time.day}/${time.month}/${time.year} at $hour:$minute';
  }
}

// Reviews Tab
class _ReviewsTab extends StatelessWidget {
  final DriverMatch driver;

  const _ReviewsTab({required this.driver});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Rating Summary
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: <Widget>[
                  Column(
                    children: <Widget>[
                      Text(
                        driver.rating.toString(),
                        style: theme.textTheme.displayLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        children: List.generate(
                          5,
                          (index) => Icon(
                            index < driver.rating.floor()
                                ? Icons.star
                                : Icons.star_border,
                            color: Colors.amber,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${driver.totalRatings} reviews',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(width: 32),
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        _RatingBar(stars: 5, percentage: 0.75),
                        _RatingBar(stars: 4, percentage: 0.15),
                        _RatingBar(stars: 3, percentage: 0.07),
                        _RatingBar(stars: 2, percentage: 0.02),
                        _RatingBar(stars: 1, percentage: 0.01),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // Reviews List
          Text(
            'Recent Reviews',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ..._buildReviewsList(),
        ],
      ),
    );
  }

  List<Widget> _buildReviewsList() {
    final reviews = [
      {
        'name': 'John Lim',
        'avatar': 'https://i.pravatar.cc/150?img=11',
        'rating': 5.0,
        'date': '2 days ago',
        'comment': 'Great driver! Very punctual and friendly. Smooth ride.',
      },
      {
        'name': 'Mary Tan',
        'avatar': 'https://i.pravatar.cc/150?img=32',
        'rating': 5.0,
        'date': '1 week ago',
        'comment': 'Professional and safe driver. Highly recommended!',
      },
      {
        'name': 'Alex Kumar',
        'avatar': 'https://i.pravatar.cc/150?img=68',
        'rating': 4.0,
        'date': '2 weeks ago',
        'comment': 'Good experience overall. Would ride again.',
      },
    ];

    return reviews.map((review) {
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: NetworkImage(review['avatar'] as String),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          review['name'] as String,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          review['date'] as String,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: List.generate(
                      5,
                      (index) => Icon(
                        index < (review['rating'] as double).floor()
                            ? Icons.star
                            : Icons.star_border,
                        color: Colors.amber,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(review['comment'] as String),
            ],
          ),
        ),
      );
    }).toList();
  }
}

// Rating Bar Widget
class _RatingBar extends StatelessWidget {
  final int stars;
  final double percentage;

  const _RatingBar({
    required this.stars,
    required this.percentage,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Text('$stars', style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          const Icon(Icons.star, size: 12, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: LinearProgressIndicator(
              value: percentage,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${(percentage * 100).toInt()}%',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// Info Row Widget
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
      children: <Widget>[
        Icon(icon, size: 24, color: Colors.grey.shade700),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

// Popular Destination Card Widget
class _PopularDestinationCard extends StatelessWidget {
  final PopularDestination destination;
  final VoidCallback onTap;

  const _PopularDestinationCard({
    required this.destination,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: 12),
      child: Card(
        elevation: 2,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      destination.icon,
                      style: const TextStyle(fontSize: 28),
                    ),
                    const Spacer(),
                    if (destination.rideCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${destination.rideCount}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  destination.shortName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _getCategoryColor(destination.category).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    destination.category,
                    style: TextStyle(
                      fontSize: 10,
                      color: _getCategoryColor(destination.category),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Campus':
        return Colors.blue;
      case 'Shopping':
        return Colors.purple;
      case 'Transport':
        return Colors.green;
      case 'Sport':
        return Colors.orange;
      case 'Tourist':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }
}

// Route Info Item Widget
class _RouteInfoItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _RouteInfoItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Column(
      children: [
        Icon(icon, color: theme.colorScheme.primary, size: 24),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
