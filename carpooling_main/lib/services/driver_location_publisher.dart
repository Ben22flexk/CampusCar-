// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:carpooling_main/core/network/mqtt_service.dart';
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
        developer.log(
          '❌ Failed to connect to MQTT',
          name: 'DriverLocationPublisher',
        );
        return false;
      }
    }

    // Start location stream
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
        timeLimit: Duration(seconds: 5), // Update at least every 5 seconds
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
    if (_driverId == null) return;

    final payload = {
      'driverId': _driverId,
      'lat': position.latitude,
      'lng': position.longitude,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'speedMps': position.speed,
      'bearing': position.heading,
    };

    final topic = 'carpool/drivers/$_driverId/location';
    final jsonPayload = jsonEncode(payload);

    _mqttService.publish(
      topic: topic,
      payload: jsonPayload,
      qos: MqttQos.atLeastOnce,
    );

    developer.log(
      '📍 Published location: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
      name: 'DriverLocationPublisher',
    );
  }

  /// Dispose resources
  void dispose() {
    stop();
  }
}

