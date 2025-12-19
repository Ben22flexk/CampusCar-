import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:carpooling_driver/services/location_service.dart';
import 'dart:async';

/// Location Picker Widget with OpenStreetMap
/// Allows search and selection of locations
class LocationPickerWidget extends HookWidget {
  final String title;
  final LatLng? initialLocation;
  final Function(LocationSelection) onLocationSelected;

  const LocationPickerWidget({
    super.key,
    required this.title,
    this.initialLocation,
    required this.onLocationSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locationService = LocationService();
    
    final searchController = useTextEditingController();
    final mapController = useMemoized(() => MapController());
    
    final searchResults = useState<List<LocationSearchResult>>([]);
    final isSearching = useState(false);
    final selectedLocation = useState<LocationSelection?>(null);
    final currentMapCenter = useState<LatLng>(
      initialLocation ?? const LatLng(3.2175, 101.7258), // TARC KL
    );
    final showSuggestions = useState(false);
    final popularLocations = useMemoized(() => locationService.getPopularLocations());
    
    // Debounce search
    Timer? searchDebounce;
    
    void performSearch(String query) {
      searchDebounce?.cancel();
      
      if (query.trim().isEmpty) {
        searchResults.value = [];
        showSuggestions.value = true;
        return;
      }
      
      searchDebounce = Timer(const Duration(milliseconds: 500), () async {
        isSearching.value = true;
        try {
          final results = await locationService.searchLocations(query);
          searchResults.value = results;
          showSuggestions.value = false;
        } catch (e) {
          searchResults.value = [];
        } finally {
          isSearching.value = false;
        }
      });
    }
    
    void selectLocation(String displayName, LatLng latLng) {
      selectedLocation.value = LocationSelection(
        displayName: displayName,
        latLng: latLng,
      );
      currentMapCenter.value = latLng;
      mapController.move(latLng, 15.0);
      searchController.text = displayName;
      searchResults.value = [];
      showSuggestions.value = false;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (selectedLocation.value != null)
            TextButton.icon(
              onPressed: () {
                onLocationSelected(selectedLocation.value!);
                Navigator.pop(context);
              },
              icon: const Icon(Icons.check, color: Colors.white),
              label: const Text(
                'Confirm',
                style: TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            color: theme.colorScheme.surface,
            child: Column(
              children: [
                TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: 'Search location in Malaysia...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              searchController.clear();
                              searchResults.value = [];
                              showSuggestions.value = true;
                            },
                          )
                        : null,
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                  onChanged: performSearch,
                  onTap: () {
                    if (searchController.text.isEmpty) {
                      showSuggestions.value = true;
                    }
                  },
                ),
                
                // Selected Location Display
                if (selectedLocation.value != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.location_on, color: Colors.green.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Selected Location',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                selectedLocation.value!.displayName,
                                style: theme.textTheme.bodyMedium,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          // Search Results / Suggestions Overlay
          if (isSearching.value || 
              searchResults.value.isNotEmpty || 
              showSuggestions.value)
            Expanded(
              child: Container(
                color: theme.colorScheme.surface,
                child: isSearching.value
                    ? const Center(child: CircularProgressIndicator())
                    : showSuggestions.value
                        ? _buildPopularLocations(
                            context,
                            popularLocations,
                            selectLocation,
                          )
                        : _buildSearchResults(
                            context,
                            searchResults.value,
                            selectLocation,
                          ),
              ),
            )
          else
            // Map View
            Expanded(
              child: FlutterMap(
                mapController: mapController,
                options: MapOptions(
                  initialCenter: currentMapCenter.value,
                  initialZoom: 13.0,
                  minZoom: 5.0,
                  maxZoom: 18.0,
                  onTap: (tapPosition, latLng) async {
                    // Reverse geocode tapped location
                    final address = await locationService.getAddressFromCoordinates(
                      latLng.latitude,
                      latLng.longitude,
                    );
                    selectLocation(address, latLng);
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.tarc.campuscar',
                    maxZoom: 19,
                  ),
                  if (selectedLocation.value != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: selectedLocation.value!.latLng,
                          width: 60,
                          height: 60,
                          child: const Icon(
                            Icons.location_on,
                            size: 60,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: selectedLocation.value != null
          ? FloatingActionButton.extended(
              onPressed: () {
                onLocationSelected(selectedLocation.value!);
                Navigator.pop(context);
              },
              icon: const Icon(Icons.check),
              label: const Text('Confirm Location'),
              backgroundColor: Colors.green,
            )
          : null,
    );
  }

  Widget _buildSearchResults(
    BuildContext context,
    List<LocationSearchResult> results,
    Function(String, LatLng) onSelect,
  ) {
    if (results.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No locations found.\nTry a different search term.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final result = results[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.blue.shade100,
            child: Icon(
              Icons.location_on,
              color: Colors.blue.shade700,
            ),
          ),
          title: Text(
            result.shortName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            result.displayName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => onSelect(result.displayName, result.latLng),
        );
      },
    );
  }

  Widget _buildPopularLocations(
    BuildContext context,
    List<LocationSuggestion> suggestions,
    Function(String, LatLng) onSelect,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Popular Locations',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        ...suggestions.map((suggestion) {
          IconData icon;
          Color color;
          
          switch (suggestion.category) {
            case 'Campus':
              icon = Icons.school;
              color = Colors.purple;
              break;
            case 'Shopping':
              icon = Icons.shopping_bag;
              color = Colors.orange;
              break;
            case 'Transit':
              icon = Icons.train;
              color = Colors.blue;
              break;
            case 'Tourist':
              icon = Icons.photo_camera;
              color = Colors.green;
              break;
            default:
              icon = Icons.place;
              color = Colors.grey;
          }
          
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: color.withOpacity(0.2),
                child: Icon(icon, color: color),
              ),
              title: Text(
                suggestion.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(suggestion.address),
              trailing: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  suggestion.category,
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              onTap: () => onSelect(
                '${suggestion.name}, ${suggestion.address}',
                suggestion.latLng,
              ),
            ),
          );
        }),
      ],
    );
  }
}

/// Selected location data
class LocationSelection {
  final String displayName;
  final LatLng latLng;

  const LocationSelection({
    required this.displayName,
    required this.latLng,
  });
  
  double get latitude => latLng.latitude;
  double get longitude => latLng.longitude;
}

