# CampusCar - APIs & Important Code Reference
## Final Year Project (FYP) - Presentation Material

---

## 📱 PROJECT OVERVIEW

**Project Name:** CampusCar - Student Carpooling System for TARC  
**Platform:** Flutter (iOS & Android)  
**Backend:** Supabase (PostgreSQL + Real-time)  
**Target Users:** TARC Students & Drivers

---

## 🌐 EXTERNAL APIs & SERVICES

### 1. **Supabase (Backend-as-a-Service)**
- **URL:** `https://nldxaxthaqefugkokwhh.supabase.co`
- **Purpose:** Database, Authentication, Real-time subscriptions, Storage
- **Features Used:**
  - PostgreSQL database
  - Row Level Security (RLS)
  - Real-time listeners
  - User authentication (Email/Password)
  - Remote Procedure Calls (RPC functions)
  - File storage for profile pictures

**Key Implementation:**
```dart
// Initialize Supabase
await Supabase.initialize(
  url: 'https://nldxaxthaqefugkokwhh.supabase.co',
  anonKey: 'your_anon_key',
  authOptions: const FlutterAuthClientOptions(
    authFlowType: AuthFlowType.pkce,
  ),
);

// Real-time listener example
_supabase.channel('ride_updates')
  .onPostgresChanges(
    event: PostgresChangeEvent.update,
    schema: 'public',
    table: 'rides',
    callback: (payload) {
      // Handle real-time updates
    },
  ).subscribe();
```

---

### 2. **OpenStreetMap Nominatim API**
- **URL:** `https://nominatim.openstreetmap.org`
- **Purpose:** Geocoding & Reverse Geocoding
- **Cost:** FREE (Open-source)
- **Rate Limit:** 1 request/second (with caching implemented)

**Features:**
- Convert coordinates to addresses (Reverse Geocoding)
- Search locations by name (Forward Geocoding)
- Malaysia-specific location search
- Address details extraction

**Key Implementation:**
```dart
// Reverse geocoding (coordinates → address)
final url = Uri.parse(
  'https://nominatim.openstreetmap.org/reverse?'
  'format=json&'
  'lat=$latitude&lon=$longitude&'
  'zoom=18&addressdetails=1'
);

// Forward geocoding (address → coordinates)
final searchUrl = Uri.parse(
  'https://nominatim.openstreetmap.org/search?'
  'format=json&'
  'q=$searchQuery&'
  'limit=10&'
  'countrycodes=my&'  // Malaysia-specific
  'viewbox=99.6,6.5,119.3,1.2&'  // Malaysia bounding box
  'bounded=1'
);
```

**Location:** `carpooling_main/lib/find_carpool.dart` (lines 115, 248)

---

### 3. **Google Maps Directions API**
- **API Key:** `AIzaSyCq-OE3mBpewP0435n0w5jrnzFXUGF-aYY`
- **URL:** `https://maps.googleapis.com/maps/api/directions/json`
- **Purpose:** Calculate real driving routes, distance, and ETA
- **Cost:** Pay-per-use (free tier: $200 credit/month)

**Features:**
- Real-time route calculation
- Turn-by-turn navigation data
- Traffic-aware ETA
- Distance matrix calculation

**Key Implementation:**
```dart
// Get driving directions
final url = Uri.parse(
  'https://maps.googleapis.com/maps/api/directions/json?'
  'origin=$originLat,$originLng&'
  'destination=$destLat,$destLng&'
  'mode=driving&'
  'key=$_googleApiKey'
);

final response = await http.get(url);
final data = json.decode(response.body);

// Extract distance and duration
final route = data['routes'][0];
final leg = route['legs'][0];
final distanceKm = leg['distance']['value'] / 1000;
final durationMinutes = leg['duration']['value'] / 60;
```

**Location:** 
- `carpooling_main/lib/services/directions_service.dart`
- `carpooling_main/lib/services/distance_service.dart`

---

### 4. **Firebase Cloud Messaging (FCM)**
- **Purpose:** Push notifications (real-time alerts)
- **Cost:** FREE
- **Features Used:**
  - Remote push notifications
  - Topic-based messaging
  - Background message handling
  - Token management

**Key Implementation:**
```dart
// Initialize Firebase
await Firebase.initializeApp();

// Request permission
await FirebaseMessaging.instance.requestPermission(
  alert: true,
  badge: true,
  sound: true,
);

// Get FCM token
final token = await FirebaseMessaging.instance.getToken();

// Save token to Supabase
await _supabase.from('profiles')
  .update({'fcm_token': token})
  .eq('id', userId);

// Listen for messages
FirebaseMessaging.onMessage.listen((message) {
  // Show local notification
  _showLocalNotification(message);
});
```

**Location:** 
- `carpooling_main/lib/main.dart`
- `carpooling_main/lib/services/push_notification_service.dart`
- `carpooling_driver/lib/services/push_notification_service.dart`

---

### 5. **Google Maps SDK**
- **Purpose:** Interactive map display
- **Features:**
  - Map rendering
  - Marker placement
  - Route visualization
  - User location tracking

**Key Implementation:**
```dart
GoogleMap(
  initialCameraPosition: CameraPosition(
    target: LatLng(latitude, longitude),
    zoom: 15.0,
  ),
  markers: _markers,
  polylines: _polylines,
  myLocationEnabled: true,
  myLocationButtonEnabled: true,
);
```

---

### 6. **Geolocator (Device GPS)**
- **Purpose:** Real-time GPS location tracking
- **Features:**
  - Get current location
  - Track location changes
  - Calculate distance between coordinates
  - Location accuracy monitoring

**Key Implementation:**
```dart
// Get current position
final position = await Geolocator.getCurrentPosition(
  desiredAccuracy: LocationAccuracy.high,
);

// Calculate distance between two points
final distance = Geolocator.distanceBetween(
  startLat, startLng,
  endLat, endLng,
);

// Check if within radius (100m)
if (distance <= 100) {
  // Driver has arrived
}
```

**Location:** `carpooling_driver/lib/features/ride_management/driver_navigation_page.dart`

---

## 🗄️ DATABASE STRUCTURE (Supabase/PostgreSQL)

### Core Tables:

1. **`profiles`** - User information
   - `id` (UUID, Primary Key)
   - `full_name`, `email`, `phone`
   - `role` (student/driver)
   - `fcm_token` (for notifications)
   - `tng_qr_code`, `tng_phone_number`

2. **`rides`** - Ride listings
   - `id` (UUID, Primary Key)
   - `driver_id` (Foreign Key → profiles)
   - `from_location`, `to_location`
   - `from_lat`, `from_lng`, `to_lat`, `to_lng`
   - `scheduled_time`
   - `available_seats`
   - `price_per_seat`
   - `ride_status` (scheduled/active/in_progress/completed/cancelled)

3. **`bookings`** - Passenger requests
   - `id` (UUID, Primary Key)
   - `ride_id` (Foreign Key → rides, CASCADE DELETE)
   - `passenger_id` (Foreign Key → profiles)
   - `seats_requested`
   - `fare_per_seat`, `total_price`
   - `request_status` (pending/accepted/rejected/completed)
   - `payment_status` (pending/paid_cash/paid_tng)
   - `pickup_location`, `pickup_lat`, `pickup_lng`
   - `rejection_reason`

4. **`messages`** - In-app chat
   - `id` (UUID, Primary Key)
   - `sender_id`, `receiver_id`
   - `message_text`
   - `sent_at`

5. **`notifications`** - Push notification logs
   - `id` (UUID, Primary Key)
   - `user_id` (Foreign Key → profiles)
   - `title`, `message`
   - `type`, `related_id`
   - `is_read`

6. **`driver_verifications`** - Driver approval
   - `user_id` (Foreign Key → profiles)
   - `vehicle_model`, `vehicle_color`, `vehicle_plate_number`
   - `license_number`
   - `verification_status`

7. **`penalties`** - Driver penalties
   - `user_id`, `penalty_type`
   - `expires_at`
   - `reason`

### Important SQL Functions (RPC):

```sql
-- Safely delete ride with cascade
CREATE OR REPLACE FUNCTION delete_ride_safely(p_ride_id UUID)
RETURNS jsonb AS $$
BEGIN
  DELETE FROM bookings WHERE ride_id = p_ride_id;
  DELETE FROM rides WHERE id = p_ride_id;
  RETURN jsonb_build_object('success', true);
END;
$$ LANGUAGE plpgsql;

-- Start ride with location tracking
CREATE OR REPLACE FUNCTION start_ride_with_location(...)
-- Updates ride status and initializes GPS tracking
```

---

## 🔑 KEY FEATURES & CODE SECTIONS

### 1. **Real-Time GPS Tracking**
**File:** `carpooling_driver/lib/features/ride_management/driver_navigation_page.dart`

**Key Code:**
```dart
// GPS verification (100m radius)
Future<bool> _checkLocationAccuracy(
  double targetLat, 
  double targetLng,
  String locationName
) async {
  final position = await Geolocator.getCurrentPosition();
  
  final distance = Geolocator.distanceBetween(
    position.latitude,
    position.longitude,
    targetLat,
    targetLng,
  );

  const double accuracyRadius = 100.0; // 100 meters
  
  if (distance > accuracyRadius) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'You are ${distance.toStringAsFixed(0)}m away from $locationName. '
          'Please get closer.'
        ),
      ),
    );
    return false;
  }
  return true;
}
```

---

### 2. **Smart Fare Calculation**
**File:** `carpooling_main/lib/services/fare_calculation_service.dart`

**Algorithm:**
```dart
double calculateStudentFare({
  required double distanceInKm,
  required DateTime tripDateTime,
}) {
  // Base fare
  const double baseFare = 3.00;
  const double perKmRate = 1.20;
  
  // Calculate base amount
  double fare = baseFare + (distanceInKm * perKmRate);
  
  // Peak hours surcharge (7-9 AM, 5-7 PM)
  final hour = tripDateTime.hour;
  if ((hour >= 7 && hour < 9) || (hour >= 17 && hour < 19)) {
    fare *= 1.2; // 20% surcharge
  }
  
  // Minimum fare
  if (fare < 5.0) fare = 5.0;
  
  return double.parse(fare.toStringAsFixed(2));
}
```

---

### 3. **Auto-Reject When Full**
**File:** `carpooling_driver/lib/features/ride_management/driver_ride_details_page.dart`

**Key Code:**
```dart
Future<void> _acceptRequest(String bookingId) async {
  // Get booking details
  final booking = _pendingRequests.firstWhere((p) => p['id'] == bookingId);
  final seatsRequested = booking['seats_requested'] as int;
  final availableSeats = _rideData!['available_seats'] as int;
  
  // Check if enough seats
  if (seatsRequested > availableSeats) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Not enough seats! Requested: $seatsRequested, '
          'Available: $availableSeats'
        ),
      ),
    );
    return;
  }
  
  // Accept booking
  await _supabase.from('bookings').update({
    'request_status': 'accepted',
  }).eq('id', bookingId);
  
  // Update available seats
  await _supabase.from('rides').update({
    'available_seats': availableSeats - seatsRequested,
  }).eq('id', widget.rideId);
  
  // Auto-reject all pending if full
  if (availableSeats - seatsRequested == 0) {
    await _autoRejectPendingRequests('Ride is now full');
  }
}
```

---

### 4. **Real-Time Payment Updates**
**File:** `carpooling_driver/lib/pages/driver_ride_summary_page.dart`

**Key Code:**
```dart
void _setupRealtimeListener() {
  _realtimeChannel = _supabase
    .channel('ride_summary_${widget.rideId}')
    .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'bookings',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'ride_id',
        value: widget.rideId,
      ),
      callback: (payload) {
        final newRecord = payload.newRecord;
        
        // Check if payment status changed to paid
        if (newRecord['payment_status'] == 'paid_cash' || 
            newRecord['payment_status'] == 'paid_tng') {
          
          // Highlight the passenger who just paid
          setState(() {
            _justPaidPassengerId = newRecord['passenger_id'];
          });
          
          // Show notification
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Payment confirmed!'),
              backgroundColor: Colors.green,
            ),
          );
          
          // Reload earnings
          _loadData();
        }
      },
    ).subscribe();
}
```

---

### 5. **Scheduled Ride Time-Based Activation**
**File:** `carpooling_driver/lib/features/ride_management/driver_ride_details_page.dart`

**Key Code:**
```dart
Widget _buildBottomButtons(ThemeData theme, DateTime scheduledTime) {
  final now = TimezoneHelper.nowInMalaysia();
  final timeUntilDeparture = scheduledTime.difference(now);
  final hoursUntilDeparture = timeUntilDeparture.inMinutes / 60;
  
  // Can only start within 2 hours before scheduled time
  final canStartEarly = hoursUntilDeparture <= 2 && hoursUntilDeparture > -1;
  
  if (rideStatus == 'scheduled') {
    return Column(
      children: [
        // Info message
        Container(
          child: Text(
            canStartEarly
              ? '✅ Ready to start! You can start the ride now.'
              : '⏰ Scheduled Ride\nYou can start up to 2 hours before departure time.\n'
                'Time remaining: ${_formatTimeRemaining(timeUntilDeparture)}',
          ),
        ),
        
        // Start button (only if within 2 hours)
        if (canStartEarly)
          ElevatedButton(
            onPressed: () => _startRide(),
            child: Text('Start Ride'),
          ),
      ],
    );
  }
}
```

---

### 6. **Location Caching for Performance**
**File:** `carpooling_main/lib/find_carpool.dart`

**Key Code:**
```dart
class GeocodingService {
  // LRU Cache for geocoding results
  static final Map<String, String> _cache = LruMap(maximumSize: 100);
  
  static Future<String> getAddressFromCoordinates(
    LatLng coordinates
  ) async {
    // Check cache first
    final cacheKey = 'reverse_${coordinates.latitude}_${coordinates.longitude}';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }
    
    // Call API
    final response = await http.get(nominatimUrl);
    final address = _formatAddress(response.body);
    
    // Cache result
    _cache[cacheKey] = address;
    
    return address;
  }
}
```

---

### 7. **Push Notification System**
**File:** `carpooling_main/lib/services/push_notification_service.dart`

**Key Code:**
```dart
// Send notification via Supabase function
Future<void> sendNotification({
  required String userId,
  required String title,
  required String message,
}) async {
  // Get user's FCM token
  final profile = await _supabase
    .from('profiles')
    .select('fcm_token')
    .eq('id', userId)
    .single();
  
  final token = profile['fcm_token'];
  
  // Send via Firebase Cloud Messaging
  await _firebaseMessaging.send({
    'token': token,
    'notification': {
      'title': title,
      'body': message,
    },
    'data': {
      'type': 'ride_update',
      'timestamp': DateTime.now().toIso8601String(),
    },
  });
  
  // Log to database
  await _supabase.from('notifications').insert({
    'user_id': userId,
    'title': title,
    'message': message,
    'created_at': DateTime.now().toUtc().toIso8601String(),
  });
}
```

---

### 8. **Penalty System**
**File:** `carpooling_driver/lib/services/penalty_service.dart`

**Key Code:**
```dart
Future<void> applyPenalty({
  required String userId,
  required String penaltyType,
  required String reason,
  Duration? customDuration,
}) async {
  final duration = customDuration ?? Duration(minutes: 20);
  final expiresAt = DateTime.now().add(duration);
  
  await _supabase.from('penalties').insert({
    'user_id': userId,
    'penalty_type': penaltyType,
    'reason': reason,
    'expires_at': expiresAt.toUtc().toIso8601String(),
  });
  
  developer.log(
    '🚫 Penalty applied: $penaltyType for $duration',
    name: 'PenaltyService',
  );
}

Future<bool> hasActivePenalty(String userId) async {
  final result = await _supabase
    .from('penalties')
    .select()
    .eq('user_id', userId)
    .gt('expires_at', DateTime.now().toUtc().toIso8601String())
    .limit(1);
  
  return result.isNotEmpty;
}
```

---

## 📊 IMPORTANT ALGORITHMS

### 1. **Distance Calculation (Haversine Formula)**
```dart
double calculateDistance({
  required double lat1,
  required double lon1,
  required double lat2,
  required double lon2,
}) {
  const earthRadius = 6371.0; // km
  
  final dLat = _toRadians(lat2 - lat1);
  final dLon = _toRadians(lon2 - lon1);
  
  final a = sin(dLat / 2) * sin(dLat / 2) +
           cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
           sin(dLon / 2) * sin(dLon / 2);
  
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  
  return earthRadius * c;
}
```

### 2. **Smart Matching Algorithm**
```dart
// Match passengers with nearby rides
List<Ride> findMatchingRides({
  required LatLng passengerOrigin,
  required LatLng passengerDestination,
  required DateTime departureTime,
}) {
  final rides = await _supabase.from('rides')
    .select()
    .eq('ride_status', 'scheduled')
    .gte('scheduled_time', departureTime.toUtc().toIso8601String());
  
  return rides.where((ride) {
    // Check origin proximity (within 2km)
    final originDistance = calculateDistance(
      passengerOrigin.latitude,
      passengerOrigin.longitude,
      ride['from_lat'],
      ride['from_lng'],
    );
    
    // Check destination proximity (within 2km)
    final destDistance = calculateDistance(
      passengerDestination.latitude,
      passengerDestination.longitude,
      ride['to_lat'],
      ride['to_lng'],
    );
    
    // Match if both within acceptable range
    return originDistance <= 2.0 && destDistance <= 2.0;
  }).toList();
}
```

---

## 📦 FLUTTER PACKAGES USED

### Core Packages:
1. **supabase_flutter** (^2.10.1) - Backend connectivity
2. **hooks_riverpod** (^2.5.1) - State management
3. **flutter_hooks** (^0.20.5) - React-style hooks

### Maps & Location:
4. **flutter_map** (^6.1.0) - Map rendering
5. **google_maps_flutter** (^2.14.0) - Google Maps SDK
6. **geolocator** (^14.0.2) - GPS location
7. **geocoding** (^3.0.0) - Address conversion
8. **latlong2** (^0.9.0) - Coordinate calculations

### Notifications:
9. **firebase_core** (^3.6.0) - Firebase initialization
10. **firebase_messaging** (^15.1.3) - Push notifications
11. **flutter_local_notifications** (^18.0.1) - Local notifications

### UI & Utilities:
12. **http** (^1.2.0) - HTTP requests
13. **intl** (^0.19.0) - Date/time formatting
14. **image_picker** (^1.0.7) - Photo selection
15. **url_launcher** (^6.2.5) - External app launching
16. **permission_handler** (^12.0.1) - Device permissions
17. **qr_flutter** (^4.1.0) - QR code generation

### Reports:
18. **pdf** (^3.11.1) - PDF generation
19. **printing** (^5.13.4) - PDF printing
20. **fl_chart** (^0.69.0) - Charts & graphs

---

## 🎯 KEY PRESENTATION POINTS

### Technical Highlights:
1. ✅ **Real-time GPS tracking** with 100m accuracy verification
2. ✅ **Live payment updates** using Supabase real-time subscriptions
3. ✅ **Smart fare calculation** with peak hour pricing
4. ✅ **Automated seat management** with auto-reject when full
5. ✅ **Push notifications** via Firebase Cloud Messaging
6. ✅ **Location caching** for performance optimization
7. ✅ **Penalty system** for driver accountability
8. ✅ **Time-based ride activation** (2-hour window before departure)

### Security Features:
1. ✅ **Row Level Security (RLS)** on all database tables
2. ✅ **Foreign key constraints** with CASCADE DELETE
3. ✅ **GPS verification** before allowing ride actions
4. ✅ **Penalty enforcement** for policy violations

### User Experience:
1. ✅ **Real-time updates** - No manual refresh needed
2. ✅ **Offline-first caching** - Reduced API calls
3. ✅ **Error handling** - User-friendly error messages
4. ✅ **Loading indicators** - Clear feedback on actions

---

## 📈 SYSTEM ARCHITECTURE

```
┌─────────────────┐
│  Flutter Apps   │
│ (Driver/Student)│
└────────┬────────┘
         │
         ├──────────┐
         │          │
         ▼          ▼
┌─────────────┐  ┌──────────────┐
│  Supabase   │  │   Firebase   │
│  (Backend)  │  │     (FCM)    │
└──────┬──────┘  └──────┬───────┘
       │                │
       ▼                ▼
┌──────────────────────────┐
│    PostgreSQL Database    │
└──────────────────────────┘

External APIs:
├─ Google Maps Directions API
├─ OpenStreetMap Nominatim
└─ Device GPS (Geolocator)
```

---

## 💡 INNOVATION POINTS

1. **Hybrid Geocoding Strategy**
   - Primary: Free OpenStreetMap Nominatim
   - Fallback: Geocoding package
   - Caching: LRU cache for performance

2. **Smart Route Matching**
   - Proximity-based matching (2km radius)
   - Time-window filtering
   - Distance optimization

3. **Real-Time Everything**
   - Live GPS tracking
   - Instant payment confirmation
   - Auto-updating ride status
   - Push notifications

4. **Cost Optimization**
   - Caching to reduce API calls
   - Free OpenStreetMap for geocoding
   - Firebase free tier for notifications
   - Supabase free tier for backend

---

## 📝 TESTING CREDENTIALS

**Driver Account:**
- Email: driver@test.com
- Role: Driver

**Student Account:**
- Email: student@test.com
- Role: Student

**Supabase Dashboard:**
- URL: https://app.supabase.com/project/nldxaxthaqefugkokwhh

---

## 🎓 ACADEMIC RELEVANCE

**Subject Areas Covered:**
1. Mobile App Development (Flutter/Dart)
2. Database Design (PostgreSQL)
3. Real-time Systems (WebSockets)
4. Geospatial Computing (GPS, Maps)
5. API Integration (REST APIs)
6. Cloud Services (Supabase, Firebase)
7. Software Architecture (Clean Architecture)
8. Security (RLS, Authentication)

---

**Last Updated:** December 2, 2025  
**Project Status:** Production-Ready  
**Total Lines of Code:** ~50,000+  
**Development Time:** 6 months

---

*This document contains all essential APIs, code snippets, and technical details for the FYP presentation.*

