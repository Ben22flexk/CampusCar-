import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:carpooling_driver/services/distance_service.dart';
import 'package:carpooling_driver/services/fare_service.dart';
import 'package:carpooling_driver/widgets/location_picker_widget.dart';
import 'package:carpooling_driver/widgets/fare_display_widget.dart';
import 'dart:developer' as developer;

/// Google Maps-style route preview with from-to locations
class RoutePreviewWidget extends HookWidget {
  final Function(RouteSelection) onRouteSelected;
  final DateTime? scheduledTime;
  final bool showFareCalculation;

  const RoutePreviewWidget({
    super.key,
    required this.onRouteSelected,
    this.scheduledTime,
    this.showFareCalculation = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final distanceService = DistanceService();
    final fareService = FareService();
    
    final fromLocation = useState<LocationSelection?>(null);
    final toLocation = useState<LocationSelection?>(null);
    final routeData = useState<DistanceCalculationResult?>(null);
    final fareData = useState<FareCalculation?>(null);
    final isCalculating = useState(false);
    final mapController = useMemoized(() => MapController());
    final showRouteOnMap = useState(false);

    // Calculate route when both locations are selected
    Future<void> calculateRoute() async {
      if (fromLocation.value == null || toLocation.value == null) return;

      isCalculating.value = true;
      try {
        // Calculate distance and route
        final result = await distanceService.calculateDistance(
          origin: fromLocation.value!.latLng,
          destination: toLocation.value!.latLng,
        );
        routeData.value = result;
        
        // Debug: Check if polyline was received
        developer.log(
          'Route calculated: ${result.distanceKm}km, Method: ${result.method}, Has polyline: ${result.routePolyline != null}',
          name: 'RoutePreview'
        );
        
        if (context.mounted) {
          if (result.routePolyline == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('⚠️ Using estimated route (straight line). Check console for Google API errors.'),
                duration: const Duration(seconds: 4),
                backgroundColor: Colors.orange,
                action: SnackBarAction(
                  label: 'Details',
                  textColor: Colors.white,
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Method: ${result.method}\nEnable Google Directions API in Google Cloud Console'),
                        duration: const Duration(seconds: 5),
                      ),
                    );
                  },
                ),
              ),
            );
          } else {
            developer.log('✅ Using real curved route with polyline', name: 'RoutePreview');
          }
        }

        // Calculate fare if enabled and time provided
        if (showFareCalculation && scheduledTime != null) {
          final fare = await fareService.calculateFareByDistance(
            fromLocation: fromLocation.value!.displayName,
            toLocation: toLocation.value!.displayName,
            distanceKm: result.distanceKm,
            scheduledTime: scheduledTime!,
          );
          fareData.value = fare;
        }

        // Zoom map to fit route
        showRouteOnMap.value = true;
        // Delay map bounds update to ensure map is rendered
        Future.microtask(() {
          try {
            _fitBounds(mapController, fromLocation.value!.latLng, toLocation.value!.latLng);
          } catch (e) {
            // Map might not be ready yet, ignore
            developer.log('Map controller not ready: $e', name: 'RoutePreview');
          }
        });
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error calculating route: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        isCalculating.value = false;
      }
    }

    // Auto-calculate when both locations are set
    useEffect(() {
      if (fromLocation.value != null && toLocation.value != null) {
        calculateRoute();
      }
      return null;
    }, [fromLocation.value, toLocation.value]);

    return Column(
      children: [
        // Location Selection Cards
        _buildLocationCard(
          context: context,
          icon: Icons.trip_origin,
          title: 'From',
          subtitle: fromLocation.value?.displayName ?? 'Select pickup location',
          color: Colors.green,
          isSelected: fromLocation.value != null,
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => LocationPickerWidget(
                  title: 'Select Pickup Location',
                  initialLocation: fromLocation.value?.latLng,
                  onLocationSelected: (selection) {
                    fromLocation.value = selection;
                    routeData.value = null; // Reset route
                    fareData.value = null;
                    showRouteOnMap.value = false;
                  },
                ),
              ),
            );
          },
        ),
        
        // Connecting Line
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Container(
                width: 2,
                height: 40,
                color: theme.colorScheme.outline.withOpacity(0.3),
              ),
              const SizedBox(width: 12),
              if (isCalculating.value)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (routeData.value != null)
                Expanded(
                  child: Text(
                    '${routeData.value!.distanceDisplay} • ${routeData.value!.durationDisplay}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),

        _buildLocationCard(
          context: context,
          icon: Icons.location_on,
          title: 'To',
          subtitle: toLocation.value?.displayName ?? 'Select destination',
          color: Colors.red,
          isSelected: toLocation.value != null,
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => LocationPickerWidget(
                  title: 'Select Destination',
                  initialLocation: toLocation.value?.latLng,
                  onLocationSelected: (selection) {
                    toLocation.value = selection;
                    routeData.value = null; // Reset route
                    fareData.value = null;
                    showRouteOnMap.value = false;
                  },
                ),
              ),
            );
          },
        ),

        // Map Preview with Route
        if (showRouteOnMap.value && fromLocation.value != null && toLocation.value != null) ...[
          const SizedBox(height: 16),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // Map Header
                Container(
                  padding: const EdgeInsets.all(12),
                  color: theme.colorScheme.primaryContainer,
                  child: Row(
                    children: [
                      Icon(Icons.map, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Route Preview',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      if (routeData.value != null)
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
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                
                // Map
                SizedBox(
                  height: 250,
                  child: FlutterMap(
                    mapController: mapController,
                    options: MapOptions(
                      initialCenter: fromLocation.value!.latLng,
                      initialZoom: 12.0,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.tarc.campuscar',
                      ),
                      
                      // Route Line
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            // Use decoded polyline for curved route, fallback to straight line
                            points: () {
                              final decoded = routeData.value?.decodePolyline();
                              if (decoded != null && decoded.isNotEmpty) {
                                developer.log('Using decoded route with ${decoded.length} points', name: 'RoutePreview');
                                return decoded;
                              } else {
                                developer.log('Using straight line fallback', name: 'RoutePreview');
                                return [
                                  fromLocation.value!.latLng,
                                  toLocation.value!.latLng,
                                ];
                              }
                            }(),
                            color: theme.colorScheme.primary,
                            strokeWidth: 4.0,
                          ),
                        ],
                      ),
                      
                      // Markers
                      MarkerLayer(
                        markers: [
                          // From marker (green)
                          Marker(
                            point: fromLocation.value!.latLng,
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.trip_origin,
                              size: 40,
                              color: Colors.green,
                            ),
                          ),
                          // To marker (red)
                          Marker(
                            point: toLocation.value!.latLng,
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
                
                // Route Info Card
                if (routeData.value != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildRouteInfoItem(
                              icon: Icons.straighten,
                              label: 'Distance',
                              value: routeData.value!.distanceDisplay,
                              theme: theme,
                            ),
                            Container(
                              width: 1,
                              height: 40,
                              color: theme.colorScheme.outline.withOpacity(0.3),
                            ),
                            _buildRouteInfoItem(
                              icon: Icons.access_time,
                              label: 'Duration',
                              value: routeData.value!.durationDisplay,
                              theme: theme,
                            ),
                            if (fareData.value != null) ...[
                              Container(
                                width: 1,
                                height: 40,
                                color: theme.colorScheme.outline.withOpacity(0.3),
                              ),
                              _buildRouteInfoItem(
                                icon: Icons.payments,
                                label: 'Fare',
                                value: fareData.value!.finalFareDisplay,
                                theme: theme,
                                valueColor: Colors.green.shade700,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],

        // Fare Breakdown (if available)
        if (fareData.value != null && showFareCalculation) ...[
          const SizedBox(height: 16),
          FareDisplayWidget(
            fare: fareData.value!,
            showDetails: true,
          ),
        ],

        // Confirm Route Button
        if (routeData.value != null && fromLocation.value != null && toLocation.value != null) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                onRouteSelected(
                  RouteSelection(
                    from: fromLocation.value!,
                    to: toLocation.value!,
                    distance: routeData.value!,
                    fare: fareData.value,
                  ),
                );
              },
              icon: const Icon(Icons.check_circle),
              label: const Text('Confirm Route'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.all(16),
                backgroundColor: Colors.green,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLocationCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.outline,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRouteInfoItem({
    required IconData icon,
    required String label,
    required String value,
    required ThemeData theme,
    Color? valueColor,
  }) {
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
            color: valueColor ?? theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  void _fitBounds(MapController controller, LatLng from, LatLng to) {
    // Calculate center point between two locations
    final center = LatLng(
      (from.latitude + to.latitude) / 2,
      (from.longitude + to.longitude) / 2,
    );

    controller.move(center, 12.0);
  }
}

/// Route selection result
class RouteSelection {
  final LocationSelection from;
  final LocationSelection to;
  final DistanceCalculationResult distance;
  final FareCalculation? fare;

  const RouteSelection({
    required this.from,
    required this.to,
    required this.distance,
    this.fare,
  });
}

