// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:carpooling_driver/core/network/mqtt_service.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'dart:developer' as developer;

/// Service for publishing driver location updates via MQTT
class DriverLocationPublisher {
  final MqttService _mqttService;
  StreamSubscription<Position>? _positionSubscription;
  bool _isPublishing = false;
  String? _driverId;
  Timer? _publishTimer;

  DriverLocationPublisher(this._mqttService);

  /// Check if currently publishing location
  bool get isPublishing => _isPublishing;

  /// Start publishing driver location
  /// 
  /// [driverId] - Driver's unique identifier
  /// [mqttUsername] - MQTT username from HiveMQ
  /// [mqttPassword] - MQTT password from HiveMQ
  Future<bool> start({
    required String driverId,
    required String mqttUsername,
    required String mqttPassword,
  }) async {
    if (_isPublishing) {
      developer.log(
        '⚠️ Already publishing location',
        name: 'DriverLocationPublisher',
      );
      return true;
    }

    _driverId = driverId;

    // Request location permission
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      developer.log(
        '❌ Location services are disabled',
        name: 'DriverLocationPublisher',
      );
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        developer.log(
          '❌ Location permission denied',
          name: 'DriverLocationPublisher',
        );
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      developer.log(
        '❌ Location permission denied forever',
        name: 'DriverLocationPublisher',
      );
      return false;
    }

    // Connect to MQTT if not connected
    if (!_mqttService.isConnected) {
      final connected = await _mqttService.connect(
        clientId: 'driver_$driverId',
        username: mqttUsername,
        password: mqttPassword,
      );

      if (!connected) {
        final errorMsg = _mqttService.lastError ?? 'Unknown error';
        developer.log(
          '❌ [TRACK_DRIVER_ERROR] Failed to connect to MQTT: $errorMsg',
          name: 'DriverLocationPublisher',
        );
        return false;
      }
    }

    // Get initial location immediately and publish it
    try {
      final initialPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _publishLocation(initialPosition);
      developer.log(
        '📍 Published initial location: ${initialPosition.latitude.toStringAsFixed(6)}, ${initialPosition.longitude.toStringAsFixed(6)}',
        name: 'DriverLocationPublisher',
      );
    } catch (e) {
      developer.log(
        '⚠️ Could not get initial location: $e',
        name: 'DriverLocationPublisher',
      );
      // Continue anyway - stream will provide location
    }

    // Start location stream with more frequent updates
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // Update every 5 meters (more frequent)
        timeLimit: Duration(seconds: 3), // Update at least every 3 seconds
      ),
    ).listen(
      (Position position) {
        _publishLocation(position);
      },
      onError: (error) {
        developer.log(
          '❌ Location stream error: $error',
          name: 'DriverLocationPublisher',
        );
      },
    );
    
    // Also set up a periodic timer to ensure location is published regularly
    // This ensures messages are sent even if GPS updates are slow
    _publishTimer = Timer.periodic(
      const Duration(seconds: 5),
      (timer) async {
        if (!_isPublishing || _driverId == null) {
          timer.cancel();
          return;
        }
        
        try {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
            ),
          );
          _publishLocation(position);
        } catch (e) {
          developer.log(
            '⚠️ Could not get periodic location: $e',
            name: 'DriverLocationPublisher',
          );
        }
      },
    );

    _isPublishing = true;
    developer.log(
      '✅ Started publishing driver location',
      name: 'DriverLocationPublisher',
    );

    return true;
  }

  /// Stop publishing location
  Future<void> stop() async {
    if (!_isPublishing) {
      return;
    }

    _positionSubscription?.cancel();
    _positionSubscription = null;
    _publishTimer?.cancel();
    _publishTimer = null;
    _isPublishing = false;
    _driverId = null;

    developer.log(
      '🛑 Stopped publishing driver location',
      name: 'DriverLocationPublisher',
    );
  }

  /// Publish location update to MQTT
  void _publishLocation(Position position) {
    if (_driverId == null) {
      developer.log(
        '⚠️ Cannot publish: driverId is null',
        name: 'DriverLocationPublisher',
      );
      return;
    }

    if (!_mqttService.isConnected) {
      developer.log(
        '⚠️ Cannot publish: MQTT not connected',
        name: 'DriverLocationPublisher',
      );
      return;
    }

    // Ensure speed is valid (can be negative or invalid)
    final speedMps = position.speed.isFinite && position.speed >= 0
        ? position.speed
        : 0.0;

    final payload = {
      'driverId': _driverId,
      'lat': position.latitude,
      'lng': position.longitude,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'speedMps': speedMps,
      'bearing': position.heading.isFinite ? position.heading : 0.0,
    };

    final topic = 'carpool/drivers/$_driverId/location';
    final jsonPayload = jsonEncode(payload);

    developer.log(
      '📤 Publishing to topic: $topic',
      name: 'DriverLocationPublisher',
    );
    developer.log(
      '📤 Payload: lat=${position.latitude.toStringAsFixed(6)}, lng=${position.longitude.toStringAsFixed(6)}, speedMps=$speedMps',
      name: 'DriverLocationPublisher',
    );

    // Publish is async but we don't await it to avoid blocking
    _mqttService.publish(
      topic: topic,
      payload: jsonPayload,
      qos: MqttQos.atLeastOnce,
    ).then((published) {
      if (published) {
        developer.log(
          '✅ Published location: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)} (speed: ${(speedMps * 3.6).toStringAsFixed(1)} km/h) to $topic',
          name: 'DriverLocationPublisher',
        );
      } else {
        developer.log(
          '❌ Failed to publish location to $topic',
          name: 'DriverLocationPublisher',
        );
      }
    }).catchError((error) {
      developer.log(
        '❌ Error publishing location: $error',
        name: 'DriverLocationPublisher',
        error: error,
      );
    });
  }

  /// Dispose resources
  void dispose() {
    stop();
  }
}

