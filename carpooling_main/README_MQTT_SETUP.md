# MQTT Real-Time Driver Tracking Setup

This document explains how to set up and use the MQTT-based real-time driver tracking feature.

## Prerequisites

1. **HiveMQ Cloud Account**: You need a HiveMQ Cloud cluster with credentials
2. **MQTT Credentials**: Username and password from HiveMQ Access Management

## Configuration

### 1. Update HiveMQ Connection Details

Edit the following files and update the HiveMQ connection details:

**Passenger App** (`carpooling_main/lib/core/network/mqtt_service.dart`):
```dart
static const String _host = 'YOUR_CLUSTER_URL.s1.eu.hivemq.cloud';
static const int _port = 8883;
```

**Driver App** (`carpooling_driver/lib/core/network/mqtt_service.dart`):
```dart
static const String _host = 'YOUR_CLUSTER_URL.s1.eu.hivemq.cloud';
static const int _port = 8883;
```

### 2. Get MQTT Credentials

1. Log in to HiveMQ Cloud Console
2. Navigate to **Access Management** → **Credentials**
3. Create a new credential set (username/password)
4. Note down the username and password

### 3. Install Dependencies

Run in both apps:
```bash
flutter pub get
```

## Usage

### Driver App: Start Location Publishing

In your driver app, when starting a ride:

```dart
import 'package:carpooling_driver/core/network/mqtt_service.dart';
import 'package:carpooling_driver/services/driver_location_publisher.dart';

// Initialize services
final mqttService = MqttService();
final locationPublisher = DriverLocationPublisher(mqttService);

// Start publishing location
await locationPublisher.start(
  driverId: driverId, // Driver's user ID
  mqttUsername: 'your_mqtt_username',
  mqttPassword: 'your_mqtt_password',
);

// Stop publishing when ride ends
await locationPublisher.stop();
```

### Passenger App: Track Driver

Use the new MQTT-based tracking page:

```dart
import 'package:carpooling_main/pages/track_driver_page_mqtt.dart';

Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => TrackDriverPageMqtt(
      driverId: driverId,
      pickupLat: pickupLatitude,
      pickupLng: pickupLongitude,
      mqttUsername: 'your_mqtt_username',
      mqttPassword: 'your_mqtt_password',
    ),
  ),
);
```

## MQTT Topic Structure

- **Driver Location Topic**: `carpool/drivers/{driverId}/location`
- **QoS Level**: 1 (At least once delivery)

## Message Format

Location messages are published as JSON:

```json
{
  "driverId": "driver-uuid",
  "lat": 3.123456,
  "lng": 101.654321,
  "timestamp": 1234567890123,
  "speedMps": 12.5,
  "bearing": 45.0
}
```

## Features

- ✅ Real-time location updates via MQTT
- ✅ OpenStreetMap integration
- ✅ Smooth marker updates
- ✅ Speed display
- ✅ No database writes (pure MQTT streaming)

## Troubleshooting

### Connection Issues

1. Verify HiveMQ cluster URL is correct
2. Check MQTT credentials are valid
3. Ensure port 8883 is accessible (TLS required)
4. Check network connectivity

### Location Not Updating

1. Verify location permissions are granted
2. Check driver app is publishing location
3. Verify passenger app is subscribed to correct topic
4. Check MQTT connection status in logs

## Notes

- MQTT is used **only** for real-time tracking
- No database modifications are made by MQTT services
- Location updates are streamed in-memory only
- Driver location is published every 10 meters or 5 seconds (whichever comes first)

