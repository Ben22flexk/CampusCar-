# CampusCar — Passenger App (carpooling_main)

A passenger-facing Flutter app for CampusCar — a carpooling app for TARUMT students.

This README documents:
- project structure and quick-start
- environment variables and setup
- how the app uses the REST API, MQTT, and Supabase
- database & message schemas
- important functions that need to be implemented (with sample Dart implementations)
- testing, deployment and troubleshooting notes

---

## Table of Contents
- [Overview](#overview)
- [Quick start](#quick-start)
- [Environment variables](#environment-variables)
- [Services & integrations](#services--integrations)
  - [REST API](#rest-api)
  - [MQTT](#mqtt)
  - [Supabase](#supabase)
- [Database / Supabase schema (recommended)](#database--supabase-schema-recommended)
- [MQTT topics & message formats](#mqtt-topics--message-formats)
- [Important functions to implement](#important-functions-to-implement)
  - [Authentication & user management](#authentication--user-management)
  - [Ride search & booking (passenger)](#ride-search--booking-passenger)
  - [Realtime location & tracking](#realtime-location--tracking)
  - [Helpers & utilities](#helpers--utilities)
- [Sample code (Dart/Flutter)](#sample-code-dartflutter)
  - [Supabase init & auth example](#supabase-init--auth-example)
  - [REST API example (Dio)](#rest-api-example-dio)
  - [MQTT example (mqtt_client)](#mqtt-example-mqtt_client)
  - [Subscribe to driver location example](#subscribe-to-driver-location-example)
  - [Request to join a ride example](#request-to-join-a-ride-example)
- [Background tracking & notifications](#background-tracking--notifications)
- [Testing & CI](#testing--ci)
- [Deployment](#deployment)
- [Troubleshooting & Tips](#troubleshooting--tips)
- [Contributing](#contributing)
- [License](#license)

---

## Overview
The Passenger app allows students to:
- sign up/log in
- search for published rides
- request to join a ride
- track the driver's live location via MQTT
- receive notifications about ride status and accepts/rejections

The app uses:
- Supabase for authentication and primary DB
- REST API for search, booking, and server-side validation
- MQTT for realtime location, ride updates and chat

---

## Quick start (development)
Prerequisites:
- Flutter SDK (>= 3.x)
- Supabase project and credentials
- MQTT broker
- Running backend or configured remote API

Steps:
1. Clone repo and go to `carpooling_main`
2. Create `.env` (see below)
3. flutter pub get
4. flutter run

---

## Environment variables
Example `.env`:
```
API_BASE=https://api.campuscar.example.com
SUPABASE_URL=https://xyz.supabase.co
SUPABASE_ANON_KEY=public-anon-key
MQTT_BROKER=broker.example.com
MQTT_PORT=8883
MQTT_USERNAME=
MQTT_PASSWORD=
MQTT_TLS=true
GOOGLE_MAPS_API_KEY=...
```

---

## Services & integrations

### REST API
Passenger responsibilities:
- search rides (GET /rides?near=lat,long)
- request join (POST /rides/:id/requests)
- fetch ride details (GET /rides/:id)
- fetch history (GET /users/:id/rides)

Use JWT from Supabase auth to call protected endpoints.

### MQTT
- subscribe to location/{rideId}/{driverId} or location/{rideId}/+ to get live positions
- subscribe to ride/{rideId}/status for ride lifecycle updates
- receive personal notifications on notifications/{userId}

### Supabase
- auth: user signup/signin
- DB reads for user profile, ride history
- RLS to protect passenger data

---

## MQTT topics & message formats
(See driver README — important topics used by passengers)

Subscribe example topics:
- ride/{rideId}/status
- location/{rideId}/{driverId}
- notifications/{userId}

Payloads are JSON (see driver README for exact examples).

---

## Important functions to implement

Authentication & user management
- Future<User> signIn(String email, String password)
- Future<User> signUp(String email, String password, Map profile)
- Future<void> signOut()

Ride search & booking
- Future<List<Ride>> searchRides(double lat, double lon, {double radiusMeters = 5000})
- Future<Ride> getRide(String rideId)
- Future<void> requestToJoin(String rideId, String userId, {int seats = 1})
- Future<void> cancelRequest(String rideId, String userId)
- Future<List<Ride>> getUserHistory(String userId)

Realtime location & tracking
- Stream<Location> subscribeDriverLocation(String rideId, String driverId)
- Stream<RideStatus> subscribeRideStatus(String rideId)
- void showDriverOnMap(Location loc)

Helpers & utilities
- bool isWithinPickupRadius(Location userLocation, Ride ride)
- Rating and feedback functions after ride end

---

## Sample code (Dart/Flutter)

Supabase init & auth example
```
```dart
import 'package:supabase_flutter/supabase_flutter.dart';

await Supabase.initialize(
  url: dotenv.env['SUPABASE_URL']!,
  anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
);
final supabase = Supabase.instance.client;

// sign up
Future<User?> signUp(String email, String password) async {
  final res = await supabase.auth.signUp(email: email, password: password);
  return res.user;
}
```
```

REST API (search) example
```
```dart
import 'package:dio/dio.dart';
final dio = Dio(BaseOptions(baseUrl: dotenv.env['API_BASE']!));

Future<List> searchRides(double lat, double lon, {int radius = 5000}) async {
  final res = await dio.get('/rides', queryParameters: {
    'lat': lat,
    'lon': lon,
    'radius': radius
  });
  return res.data as List;
}
```
```

MQTT subscribe driver example
```
```dart
void subscribeDriverLocation(MqttService mqtt, String rideId, String driverId) {
  final topic = 'location/$rideId/$driverId';
  mqtt.subscribe(topic);
  mqtt.client.updates?.listen((updates) {
    for (final rec in updates!) {
      final payload = (rec.payload as MqttPublishMessage).payload.message;
      final json = jsonDecode(MqttPublishPayload.bytesToStringAsString(payload));
      // convert to Location and update map/UI
    }
  });
}
```
```

Request to join a ride example
```
```dart
Future<void> requestToJoin(String rideId, String token, int seats) async {
  final res = await dio.post('/rides/$rideId/requests', data: {'seats': seats},
      options: Options(headers: {'Authorization': 'Bearer $token'}));
}
```
```

---

## Background tracking & notifications
- Passengers usually don't need background location; only drivers do.
- Use firebase_messaging for push notifications (accepts, ride cancellations).
- When a driver accepts a passenger, server should publish to notifications/{userId} topic and also send push via FCM/APNs.

---

## Testing & CI
- Unit tests: search, booking flows, location parsing
- UI tests: map interactions and ride request flows
- CI steps similar to driver app (analyze, test, build)

---

## Deployment
- Configure MQTT broker to allow subscribing to topics used by passenger app.
- Use separate Supabase keys for production vs staging.
- Ensure backend publishes ride status (retained) when ride is created/updated so passengers get current state on subscribe.

---

## Troubleshooting & Tips
- If no location appears, ensure passenger subscribed to correct driver topic (topic segments order matters).
- Use retained messages for ride/status so passengers joining late still get status.
- Use small payloads for frequent location messages to reduce bandwidth.

---

## Contributing
- Follow project guidelines, add tests for new features, and keep credentials out of code.

---

## License
Specify project license (MIT / Apache 2.0 / etc).
