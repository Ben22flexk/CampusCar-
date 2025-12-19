# CampusCar — Driver App (carpooling_driver)

A driver-facing Flutter app for CampusCar — a carpooling app for TARUMT students.

This README documents:
- project structure and quick-start
- environment variables and setup
- how the app uses the REST API, MQTT, and Supabase
- database & message schemas
- important functions to implement (with sample Dart implementations)
- background/location & push-notification considerations
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
  - [Ride lifecycle functions (driver)](#ride-lifecycle-functions-driver)
  - [Realtime location & updates](#realtime-location--updates)
  - [Helpers & utilities](#helpers--utilities)
- [Sample code (Dart/Flutter)](#sample-code-dartflutter)
  - [Supabase init & auth example](#supabase-init--auth-example)
  - [REST API example (Dio)](#rest-api-example-dio)
  - [MQTT example (mqtt_client)](#mqtt-example-mqtt_client)
  - [Publish location example](#publish-location-example)
  - [Subscribe ride updates example](#subscribe-ride-updates-example)
- [Background location & notifications](#background-location--notifications)
- [Testing & CI](#testing--ci)
- [Deployment](#deployment)
- [Troubleshooting & Tips](#troubleshooting--tips)
- [Contributing](#contributing)
- [License](#license)

---

## Overview
The Driver app allows registered drivers to:
- create and publish rides
- broadcast live location
- accept/reject join requests
- start/stop trips and update ride status
- communicate with passengers (in-app chat via MQTT or Supabase realtime)

The app uses:
- Supabase for authentication, the main Postgres database, and optionally realtime (Postgres WAL)
- REST API (Node / Go / Dart backend) for business logic & server-side checks
- MQTT broker for lightweight, low-latency realtime location & ride updates

---

## Quick start (development)
Prerequisites:
- Flutter (>= 3.x)
- Dart SDK (matching Flutter)
- Android Studio / Xcode (for device/emulator)
- A Supabase project and credentials
- An MQTT broker (e.g., Mosquitto, EMQX, HiveMQ Cloud) accessible from devices
- The backend REST API (can run locally or remote)

Steps:
1. Clone repo:
   - carpooling_driver folder is the driver app
2. Create a `.env` file in the app root (see [Environment variables](#environment-variables))
3. Install dependencies:
   - flutter pub get
4. Run:
   - flutter run

---

## Environment variables
Create a `.env` (or use flutter_dotenv) with the following keys. Keep secrets secure (don't commit).

Example `.env`:
```
API_BASE=https://api.campuscar.example.com
SUPABASE_URL=https://xyz.supabase.co
SUPABASE_ANON_KEY=public-anon-key-or-service-role (use anon in client)
MQTT_BROKER=broker.example.com
MQTT_PORT=8883
MQTT_USERNAME=
MQTT_PASSWORD=
MQTT_TLS=true
GOOGLE_MAPS_API_KEY=...
```

- API_BASE: base URL for REST API
- SUPABASE_*: Supabase project URL and anon key
- MQTT_*: broker host, port and credentials

---

## Services & integrations

### REST API
Purpose:
- business logic that must be validated server-side (creating rides, joining rides, payments, history)
- stores canonical ride state in DB (used by Supabase backup / queries)

Typical endpoints (implement on server):
- POST /auth/login
- POST /auth/register
- GET /users/:id
- POST /rides             — create ride (driver)
- PATCH /rides/:id/status — update ride state (PUBLISHED, STARTED, ENDED, CANCELLED)
- POST /rides/:id/accept  — accept passenger
- POST /rides/:id/location — optional server-side location ingestion
- GET /rides?near=lat,long — search rides (passengers)

All endpoints should return JSON and use JWT (from Supabase or app own auth).

### MQTT
Used for:
- high-frequency location updates from driver to passengers
- immediate ride state updates (driver starts trip, arrives)
- chat / notifications (optional)

Broker configuration:
- TLS recommended (port 8883)
- Use per-user client IDs (e.g., campuscar-driver-{userId}-{random})
- Authenticate with broker credentials, optionally map JWT to broker permissions

MQTT topics (see below for full list)

### Supabase
Used for:
- Authentication (supabase.auth)
- Main Postgres DB (users, rides, ride_members, ratings)
- Realtime (optional) for subscribing to DB changes (also works for serverless)
- Storage for user images

Supabase usage pattern:
- Use Supabase for auth in the app (supabase_flutter)
- Use Supabase DB as source-of-truth along with REST API
- Use RLS policies to secure access

---

## Database / Supabase schema (recommended)
Tables (columns abbreviated):

- users
  - id (uuid) PK
  - email, full_name, phone, avatar_url
  - role (driver/passenger)
  - rating, created_at

- rides
  - id (uuid) PK
  - driver_id (fk users.id)
  - origin {lat, lon, address}
  - destination {lat, lon, address}
  - scheduled_at (timestamp)
  - seats_total (int)
  - seats_remaining (int)
  - price (numeric)
  - status (enum: DRAFT, PUBLISHED, STARTED, ENDED, CANCELLED)
  - metadata (jsonb)
  - created_at, updated_at

- ride_members
  - id (uuid)
  - ride_id (fk rides.id)
  - user_id (fk users.id)
  - status (REQUESTED, APPROVED, REJECTED, LEFT)
  - created_at

- locations (optional)
  - id
  - user_id
  - ride_id (nullable)
  - lat, lon, bearing, speed, accuracy
  - recorded_at

- messages (optional chat storage)
  - id
  - ride_id
  - from_user
  - content
  - created_at

Create RLS policies so drivers can edit their rides but not others' rides.

---

## MQTT topics & message formats

Topic naming suggestions:
- location/{rideId}/{userId} — retained = false
  - payload:
    {
      "userId": "uuid",
      "lat": 12.345,
      "lon": 67.890,
      "speed": 12.3,
      "bearing": 180,
      "ts": "2025-12-19T12:34:56Z"
    }

- ride/{rideId}/status — retained = true (current status)
  - payload:
    {
      "rideId":"uuid",
      "status":"STARTED",
      "driverId":"uuid",
      "ts":"2025-12-19T12:34:56Z",
      "meta": {...}
    }

- ride/{rideId}/chat — retained = false
  - payload:
    {
      "from":"userId",
      "text":"I'm 5 minutes away",
      "ts":"..."
    }

- notifications/{userId} — personal notifications
  - payload:
    {
      "type":"JOIN_REQUEST",
      "rideId":"uuid",
      "message":"You have a new join request",
      "data": {...}
    }

- admin/# or app-wide topics if needed.

QoS:
- location: QoS 0 or 1 depending on reliability needs
- status: QoS 1
- notifications: QoS 1

Security:
- Restrict publish/subscribe rights on broker if supported (e.g., only driver publishes location to their location topic and passengers subscribe).

---

## Important functions to implement

Below are the high-level functions and recommended signatures. Implement these in the driver app codebase.

Authentication & user management
- Future<User> signIn(String email, String password)
- Future<User> signUp(String email, String password, Map profile)
- Future<void> signOut()
- User? currentUser()

Ride lifecycle (driver)
- Future<Ride> createRide(CreateRideParams params)
- Future<Ride> updateRide(String rideId, Map fields)
- Future<void> publishRide(String rideId) — set status=PUBLISHED and publish MQTT ride/{rideId}/status
- Future<void> startRide(String rideId) — sets status=STARTED and publish mqtt
- Future<void> endRide(String rideId, EndRideSummary summary)
- Future<void> cancelRide(String rideId, reason)

Membership & requests
- Future<void> acceptPassenger(String rideId, String userId)
- Future<void> rejectPassenger(String rideId, String userId)
- Future<List<Request>> fetchJoinRequests(String rideId)

Realtime location & updates
- Future<void> startPublishingLocation(String rideId)
- Future<void> stopPublishingLocation()
- Stream<Location> subscribeToPassengerLocations(String rideId)
- Stream<RideStatus> subscribeRideStatus(String rideId)

Helpers & utilities
- String buildClientId(String userId)
- Map<String,dynamic> standardLocationPayload(Position p, String userId, String rideId)
- void handleMQTTMessage(String topic, String payload)

---

## Sample code (Dart/Flutter)

Note: these are examples — adapt to your app structure (providers/bloc/riverpod).

Supabase init & auth example
```
```dart
// inside a Flutter init method
import 'package:supabase_flutter/supabase_flutter.dart';

await Supabase.initialize(
  url: dotenv.env['SUPABASE_URL']!,
  anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
);

final supabase = Supabase.instance.client;

// sign in
Future<User?> signIn(String email, String password) async {
  final res = await supabase.auth.signInWithPassword(email: email, password: password);
  return res.user;
}
```
```

REST API example (Dio)
```
```dart
import 'package:dio/dio.dart';

final dio = Dio(BaseOptions(baseUrl: dotenv.env['API_BASE']!));

Future<Response> createRide(Map data, String token) {
  return dio.post('/rides', data: data, options: Options(headers: {
    'Authorization': 'Bearer $token'
  }));
}
```
```

MQTT example (mqtt_client)
```
```dart
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {
  final client = MqttServerClient(dotenv.env['MQTT_BROKER']!, '');

  Future<void> connect(String clientId, {String? username, String? password, bool useTls = true}) async {
    client.logging(on: false);
    client.clientIdentifier = clientId;
    client.keepAlivePeriod = 20;
    client.onDisconnected = onDisconnected;
    client.onConnected = onConnected;
    client.onSubscribed = onSubscribed;
    final connMess = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean()
        .keepAliveFor(20)
        .withWillQos(MqttQos.atLeastOnce);
    client.connectionMessage = connMess;

    try {
      await client.connect(username, password);
    } catch (e) {
      client.disconnect();
      rethrow;
    }
  }

  void publish(String topic, String payload, {MqttQos qos = MqttQos.atLeastOnce}) {
    final builder = MqttClientPayloadBuilder();
    builder.addUTF8String(payload);
    client.publishMessage(topic, qos, builder.payload!);
  }

  void subscribe(String topic, {MqttQos qos = MqttQos.atLeastOnce}) {
    client.subscribe(topic, qos);
  }

  void onConnected() { /* handle */ }
  void onDisconnected() { /* handle */ }
  void onSubscribed(String topic) { /* handle */ }
}
```
```

Publish location example
```
```dart
void publishLocation(MqttService mqtt, String rideId, String userId, double lat, double lon, double speed, double bearing) {
  final topic = 'location/$rideId/$userId';
  final payload = jsonEncode({
    'userId': userId,
    'lat': lat,
    'lon': lon,
    'speed': speed,
    'bearing': bearing,
    'ts': DateTime.now().toUtc().toIso8601String()
  });
  mqtt.publish(topic, payload, qos: MqttQos.atMostOnce);
}
```
```

Subscribe to ride updates example
```
```dart
void subscribeToRide(MqttService mqtt, String rideId) {
  mqtt.subscribe('ride/$rideId/status');
  mqtt.subscribe('location/$rideId/+'); // wildcard for every user
  mqtt.client.updates?.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
    final rec = c![0];
    final topic = rec.topic;
    final payload = (rec.payload as MqttPublishMessage).payload.message;
    final message = MqttPublishPayload.bytesToStringAsString(payload);
    // parse message & update UI
  });
}
```
```

---

## Background location & notifications
- Use appropriate plugins:
  - background location: background_locator_2 or geolocator + background_fetch / flutter_background_geolocation (commercial)
  - push notifications: firebase_messaging (for APNs / FCM)
- On Android, request foreground + background location permissions and show a persistent notification while publishing.
- Ensure you only publish high-frequency location when ride status == STARTED or when driver opts-in to share live location.

---

## Testing & CI
- Unit tests for data mappers, API wrappers, and MQTT payload builders.
- Integration tests to simulate ride creation and location publishing (mock the broker with a local Mosquitto instance).
- CI: use GitHub Actions to:
  - run flutter analyze
  - run flutter test
  - build apk/ipa for release branches

---

## Deployment
- Build driver app for Play Store / TestFlight.
- Use separate Supabase keys for production vs staging.
- Deploy backend with secure env vars and configure the MQTT broker access control lists (ACLs) so users can only publish/subscribe to permitted topics.

---

## Troubleshooting & Tips
- If locations are not reaching passengers, confirm MQTT topic structure and broker ACL.
- Validate JWTs on server endpoints and map broker auth to app user IDs.
- Use retained messages on ride/{rideId}/status so late-joining clients get current ride status.

---

## Contributing
- Follow the coding style used in the repo.
- Add tests for new features.
- Open issues and PRs against `carpooling_driver` folder.

---

## License
Specify project license (MIT / Apache 2.0 / etc).
