// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:carpooling_main/core/network/mqtt_service.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'dart:developer' as developer;

/// Controller for tracking driver location via MQTT
/// Manages subscription to driver location topic and updates state
class DriverTrackingController extends ChangeNotifier {
  static const String _errorTag = '[TRACK_DRIVER_ERROR]';

  final MqttService _mqttService;
  StreamSubscription<MqttReceivedMessage<MqttMessage>>? _messageSubscription;

  String? _trackedDriverId;
  LatLng? _driverLatLng;
  double? _currentSpeedKmh;
  DateTime? _lastUpdateTime;
  String? _lastErrorMessage;

  DriverTrackingController(this._mqttService);

  /// Currently tracked driver ID
  String? get trackedDriverId => _trackedDriverId;

  /// Latest driver location
  LatLng? get driverLatLng => _driverLatLng;

  /// Current speed in km/h
  double? get currentSpeedKmh => _currentSpeedKmh;

  /// Last update timestamp
  DateTime? get lastUpdateTime => _lastUpdateTime;

  /// Last error message (useful for UI/debugging)
  String? get lastErrorMessage => _lastErrorMessage;

  /// Check if currently tracking
  bool get isTracking => _trackedDriverId != null;

  /// Start tracking a driver
  /// 
  /// [driverId] - Driver's unique identifier to track
  /// [mqttUsername] - MQTT username from HiveMQ
  /// [mqttPassword] - MQTT password from HiveMQ
  Future<bool> startTracking({
    required String driverId,
    required String mqttUsername,
    required String mqttPassword,
  }) async {
    _lastErrorMessage = null;

    if (_trackedDriverId == driverId && isTracking) {
      developer.log(
        '⚠️ Already tracking driver: $driverId',
        name: 'DriverTrackingController',
      );
      return true;
    }

    // Stop previous tracking if any
    await stopTracking();

    _trackedDriverId = driverId;

    // Connect to MQTT if not connected
    if (!_mqttService.isConnected) {
      developer.log(
        '🔌 Connecting to MQTT for tracking driver: $driverId',
        name: 'DriverTrackingController',
      );
      
      final connected = await _mqttService.connect(
        clientId: 'passenger_${DateTime.now().millisecondsSinceEpoch}',
        username: mqttUsername,
        password: mqttPassword,
      );

      if (!connected) {
        _lastErrorMessage =
            _mqttService.lastError ?? 'MQTT connect failed (unknown error)';
        developer.log(
          '❌ $_errorTag Failed to connect to MQTT. $_lastErrorMessage',
          name: 'DriverTrackingController',
        );
        _trackedDriverId = null;
        return false;
      }
      
      developer.log(
        '✅ MQTT connected, waiting for connection to stabilize...',
        name: 'DriverTrackingController',
      );
      
      // Wait longer for connection to stabilize
      await Future.delayed(const Duration(milliseconds: 1000));
    }

    // Subscribe to driver location topic
    final topic = 'carpool/drivers/$driverId/location';
    developer.log(
      '📡 Subscribing to topic: $topic',
      name: 'DriverTrackingController',
    );
    developer.log(
      '📡 Driver ID being tracked: $driverId',
      name: 'DriverTrackingController',
    );
    
    final subscribed = await _mqttService.subscribe(topic);

    if (!subscribed) {
      _lastErrorMessage =
          _mqttService.lastError ?? 'MQTT subscribe failed (unknown error)';
      developer.log(
        '❌ $_errorTag Failed to subscribe to $topic. $_lastErrorMessage',
        name: 'DriverTrackingController',
      );
      _trackedDriverId = null;
      return false;
    }

    // Listen to MQTT messages
    developer.log(
      '👂 Setting up message listener for topic: $topic',
      name: 'DriverTrackingController',
    );
    developer.log(
      '👂 Waiting for messages on: $topic',
      name: 'DriverTrackingController',
    );
    developer.log(
      '👂 MQTT service connected: ${_mqttService.isConnected}',
      name: 'DriverTrackingController',
    );
    developer.log(
      '👂 Subscribed topics: ${_mqttService.subscribedTopics}',
      name: 'DriverTrackingController',
    );
    
    _messageSubscription = _mqttService.messageStream.listen(
      (message) {
        developer.log(
          '📨 [RAW] Message received on topic: ${message.topic}',
          name: 'DriverTrackingController',
        );
        developer.log(
          '📨 [RAW] Expected topic: $topic',
          name: 'DriverTrackingController',
        );
        developer.log(
          '📨 [RAW] Topic match: ${message.topic == topic}',
          name: 'DriverTrackingController',
        );
        _handleMessage(message);
      },
      onError: (error) {
        developer.log(
          '❌ $_errorTag MQTT message stream error: $error',
          name: 'DriverTrackingController',
          error: error,
        );
      },
      onDone: () {
        developer.log(
          '⚠️ $_errorTag MQTT message stream closed',
          name: 'DriverTrackingController',
        );
      },
    );
    
    developer.log(
      '✅ Message listener set up and waiting for messages...',
      name: 'DriverTrackingController',
    );

    developer.log(
      '✅ Started tracking driver: $driverId, subscribed to: $topic',
      name: 'DriverTrackingController',
    );

    notifyListeners();
    return true;
  }

  /// Stop tracking
  Future<void> stopTracking() async {
    if (_trackedDriverId == null) {
      return;
    }

    final driverId = _trackedDriverId!;
    _trackedDriverId = null;

    // Unsubscribe from topic
    final topic = 'carpool/drivers/$driverId/location';
    await _mqttService.unsubscribe(topic);

    // Cancel message subscription
    await _messageSubscription?.cancel();
    _messageSubscription = null;

    // Clear state
    _driverLatLng = null;
    _currentSpeedKmh = null;
    _lastUpdateTime = null;

    developer.log(
      '🛑 Stopped tracking driver: $driverId',
      name: 'DriverTrackingController',
    );

    // Only notify if not disposed
    if (!hasListeners) return;
    try {
      notifyListeners();
    } catch (e) {
      // Ignore if already disposed
      developer.log(
        '⚠️ Could not notify listeners (controller may be disposed): $e',
        name: 'DriverTrackingController',
      );
    }
  }

  /// Handle incoming MQTT message
  void _handleMessage(MqttReceivedMessage<MqttMessage> message) {
    final topic = message.topic;
    final payload = message.payload;

    developer.log(
      '🔍 Processing message from topic: $topic',
      name: 'DriverTrackingController',
    );

    // Check if this is a location update for the tracked driver
    if (!topic.contains('carpool/drivers/') || !topic.contains('/location')) {
      developer.log(
        '⚠️ Ignoring message from non-location topic: $topic',
        name: 'DriverTrackingController',
      );
      return;
    }

    // Extract driver ID from topic
    final parts = topic.split('/');
    if (parts.length < 4) {
      developer.log(
        '⚠️ Invalid topic format: $topic',
        name: 'DriverTrackingController',
      );
      return;
    }

    final driverId = parts[2];
    if (driverId != _trackedDriverId) {
      developer.log(
        '⚠️ Message from different driver: $driverId (tracking: $_trackedDriverId)',
        name: 'DriverTrackingController',
      );
      return; // Not the driver we're tracking
    }

    developer.log(
      '✅ Message matches tracked driver: $driverId',
      name: 'DriverTrackingController',
    );

    // Parse payload
    try {
      if (payload is MqttPublishMessage) {
        final bytes = payload.payload.message;
        final jsonString = utf8.decode(bytes);
        developer.log(
          '📦 [PARSE] Raw payload (${bytes.length} bytes): $jsonString',
          name: 'DriverTrackingController',
        );
        
        final decoded = jsonDecode(jsonString);
        if (decoded is! Map<String, dynamic>) {
          developer.log(
            '⚠️ $_errorTag Ignoring non-object payload: $jsonString',
            name: 'DriverTrackingController',
          );
          return;
        }
        developer.log(
          '📦 [PARSE] Decoded payload: $decoded',
          name: 'DriverTrackingController',
        );

        final latRaw = decoded['lat'];
        final lngRaw = decoded['lng'];
        // Support both 'speedMps' (m/s) and 'speed' (km/h) for flexibility
        final speedMpsRaw = decoded['speedMps'];
        final speedKmhRaw = decoded['speed'];
        final tsRaw = decoded['timestamp'];

        final lat = (latRaw is num) ? latRaw.toDouble() : null;
        final lng = (lngRaw is num) ? lngRaw.toDouble() : null;
        if (lat == null || lng == null) {
          developer.log(
            '⚠️ $_errorTag Ignoring payload missing lat/lng: $jsonString',
            name: 'DriverTrackingController',
          );
          return;
        }

        // Convert speed: prefer speedMps (m/s), fallback to speed (km/h) converted to m/s
        double speedMps = 0.0;
        if (speedMpsRaw is num) {
          speedMps = speedMpsRaw.toDouble();
        } else if (speedKmhRaw is num) {
          // Convert km/h to m/s
          speedMps = (speedKmhRaw.toDouble() / 3.6);
          developer.log(
            '⚠️ Received speed in km/h, converting to m/s: ${speedKmhRaw.toDouble()} km/h = $speedMps m/s',
            name: 'DriverTrackingController',
          );
        }
        
        final timestampMs = (tsRaw is int)
            ? tsRaw
            : (tsRaw is num)
                ? tsRaw.toInt()
                : DateTime.now().millisecondsSinceEpoch;

        _driverLatLng = LatLng(lat, lng);
        _currentSpeedKmh = speedMps * 3.6; // Convert m/s to km/h
        _lastUpdateTime = DateTime.fromMillisecondsSinceEpoch(timestampMs);

        developer.log(
          '📍 Driver location updated: $lat, $lng (${_currentSpeedKmh?.toStringAsFixed(1)} km/h)',
          name: 'DriverTrackingController',
        );

        notifyListeners();
      }
    } catch (e, stackTrace) {
      developer.log(
        '❌ $_errorTag Error parsing location message: $e',
        name: 'DriverTrackingController',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  void dispose() {
    stopTracking();
    super.dispose();
  }
}

