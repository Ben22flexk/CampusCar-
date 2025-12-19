// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io' show SecurityContext;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'dart:developer' as developer;

/// MQTT Service for connecting to HiveMQ Cloud
/// Handles connection, subscription, and message publishing
class MqttService {
  static const String _errorTag = '[TRACK_DRIVER_ERROR]';
  static const Duration _overallConnectTimeout = Duration(seconds: 15);

  MqttServerClient? _client;
  final StreamController<MqttReceivedMessage<MqttMessage>> _messageController =
      StreamController<MqttReceivedMessage<MqttMessage>>.broadcast();
  
  bool _isConnected = false;
  final Set<String> _subscribedTopics = <String>{};
  String? _lastError;

  /// HiveMQ Cloud connection details
  /// Update these with your HiveMQ cluster URL and credentials
  static const String _host = 'b659bb7b36154fcb8d4726cff0dd0665.s1.eu.hivemq.cloud';
  static const int _port = 8883;
  static const int _websocketPort443 = 443;
  static const int _websocketPort = 8884;
  static const String _websocketPath = '/mqtt';

  /// Stream of received MQTT messages
  Stream<MqttReceivedMessage<MqttMessage>> get messageStream =>
      _messageController.stream;

  /// Check if currently connected
  bool get isConnected => _isConnected;

  /// Get list of subscribed topics
  Set<String> get subscribedTopics => Set.unmodifiable(_subscribedTopics);

  /// Last connection/subscription error (for UI/debugging)
  String? get lastError => _lastError;

  /// Connect to HiveMQ Cloud
  /// 
  /// [clientId] - Unique client identifier
  /// [username] - MQTT username from HiveMQ Access Management
  /// [password] - MQTT password from HiveMQ Access Management
  Future<bool> connect({
    required String clientId,
    required String username,
    required String password,
  }) async {
    _lastError = null;

    if (_isConnected) {
      developer.log('⚠️ Already connected to MQTT', name: 'MqttService');
      return true;
    }

    final errors = <String>[];
    final deadline = DateTime.now().add(_overallConnectTimeout);

    Duration remaining() {
      final remaining = deadline.difference(DateTime.now());
      return remaining.isNegative ? Duration.zero : remaining;
    }

    // Helper to normalize and deduplicate error messages
    String? normalizeError(String? error) {
      if (error == null) return null;
      // Remove the error tag and attempt name to compare core error messages
      return error
          .replaceAll(RegExp(r'\[TRACK_DRIVER_ERROR\]\s*'), '')
          .replaceAll(RegExp(r'\([^)]+\):\s*'), '') // Remove attempt name like "(tcp_tls_8883):"
          .trim();
    }

    // 1) Try TCP/TLS on 8883 (preferred)
    final tcpOk = await _connectWith(
      clientId: clientId,
      username: username,
      password: password,
      port: _port,
      useWebSocket: false,
      attemptName: 'tcp_tls_8883',
      timeout: remaining(),
    );
    if (tcpOk) return true;
    if (_lastError != null) {
      final normalized = normalizeError(_lastError);
      if (normalized != null && !errors.any((e) => normalizeError(e) == normalized)) {
        errors.add(_lastError!);
      }
    }

    // 2) Fallback: WSS over 443 (most networks allow this; HiveMQ web client works reliably here)
    final remaining443 = remaining();
    if (remaining443 > Duration.zero) {
      final ws443Ok = await _connectWith(
        clientId: clientId,
        username: username,
        password: password,
        port: _websocketPort443,
        useWebSocket: true,
        attemptName: 'wss_443',
        timeout: remaining443,
      );
      if (ws443Ok) return true;
      if (_lastError != null) {
        final normalized = normalizeError(_lastError);
        if (normalized != null && !errors.any((e) => normalizeError(e) == normalized)) {
          errors.add(_lastError!);
        }
      }
    }

    // 3) Fallback: some networks allow WSS 8884
    final remaining8884 = remaining();
    if (remaining8884 > Duration.zero) {
      final wsOk = await _connectWith(
        clientId: clientId,
        username: username,
        password: password,
        port: _websocketPort,
        useWebSocket: true,
        attemptName: 'wss_8884',
        timeout: remaining8884,
      );
      if (wsOk) return true;
      if (_lastError != null) {
        final normalized = normalizeError(_lastError);
        if (normalized != null && !errors.any((e) => normalizeError(e) == normalized)) {
          errors.add(_lastError!);
        }
      }
    }

    // If all attempts failed, create a summary message
    if (errors.isNotEmpty) {
      // If all errors are timeouts, show a single concise message
      final allTimeouts = errors.every((e) => 
        e.toLowerCase().contains('timeout') || 
        e.toLowerCase().contains('connack')
      );
      
      if (allTimeouts && errors.length > 1) {
        _lastError = '$_errorTag Connection timeout: Unable to reach server. Please check your network connection.';
      } else {
        // Show first meaningful error only
        _lastError = errors.first;
      }
      developer.log('❌ $_errorTag Connection failed: $_lastError', name: 'MqttService');
    } else if (remaining() <= Duration.zero) {
      _lastError = '$_errorTag Connection timeout: No response from server within ${_overallConnectTimeout.inSeconds}s';
      developer.log('❌ $_lastError', name: 'MqttService');
    }
    return false;
  }

  Future<bool> _connectWith({
    required String clientId,
    required String username,
    required String password,
    required int port,
    required bool useWebSocket,
    required String attemptName,
    required Duration timeout,
  }) async {
    if (timeout <= Duration.zero) {
      _lastError = '$_errorTag Timeout: No time remaining for $attemptName';
      developer.log(_lastError!, name: 'MqttService');
      return false;
    }

    try {
      developer.log(
        '🔌 Connecting ($attemptName) to MQTT: $_host:$port',
        name: 'MqttService',
      );

      // For websockets mqtt_client expects a ws:// or wss:// server string.
      // Also: do NOT set the `secure` flag for WSS; that flag is for TCP sockets.
      final client = useWebSocket
          ? MqttServerClient.withPort(
              'wss://$_host$_websocketPath',
              clientId,
              port,
              maxConnectionAttempts: 2,
            )
          : MqttServerClient.withPort(
              _host,
              clientId,
              port,
              maxConnectionAttempts: 2,
            );
      client.logging(on: true); // Enable logging for debugging
      client.setProtocolV311();
      client.keepAlivePeriod = 20;
      // Bound the per-attempt timeout, but keep overall connect <= 15 seconds.
      client.connectTimeoutPeriod =
          timeout.inMilliseconds.clamp(3000, _overallConnectTimeout.inMilliseconds);
      client.onDisconnected = _onDisconnected;
      client.onConnected = _onConnected;
      client.onSubscribed = _onSubscribed;
      
      // Add error handler
      client.onAutoReconnect = () {
        developer.log('🔁 MQTT auto reconnecting...', name: 'MqttService');
      };
      client.onAutoReconnected = () {
        developer.log('✅ MQTT auto reconnected', name: 'MqttService');
      };

      // Reconnect support (helps with flaky mobile networks)
      client.autoReconnect = true;
      client.resubscribeOnAutoReconnect = true;
      client.onAutoReconnect = () => developer.log(
            '🔁 MQTT auto reconnecting...',
            name: 'MqttService',
          );
      client.onAutoReconnected = () => developer.log(
            '✅ MQTT auto reconnected',
            name: 'MqttService',
          );

      if (useWebSocket) {
        client.useWebSocket = true;
        client.port = port;
        client.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
        client.secure = false;
      } else {
        // TCP/TLS
        client.secure = true;
        client.securityContext = SecurityContext.defaultContext;
        client.onBadCertificate = (dynamic certificate) => true;
      }

      // Build connection message with credentials
      client.connectionMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean()
          .authenticateAs(username, password);

      MqttServerClient? previousClient;
      try {
        // Clean up previous client if exists
        if (_client != null && _client != client) {
          previousClient = _client;
          try {
            _client!.disconnect();
          } catch (_) {}
          _client = null;
        }

        developer.log(
          '🔌 Attempting connection ($attemptName) with timeout ${timeout.inSeconds}s...',
          name: 'MqttService',
        );

        // Connect without passing username/password again (already in connectionMessage)
        await client.connect().timeout(
          timeout,
          onTimeout: () {
            throw TimeoutException(
              'No CONNACK within ${timeout.inSeconds}s',
              timeout,
            );
          },
        );

        developer.log(
          '📡 Connect call completed, checking connection state...',
          name: 'MqttService',
        );
      } catch (e) {
        _lastError = '$_errorTag Connect exception ($attemptName): $e';
        developer.log(
          '❌ $_lastError',
          name: 'MqttService',
          error: e,
        );
        try {
          client.disconnect();
        } catch (_) {}
        return false;
      }

      // Check connection state immediately and wait if needed
      var state = client.connectionStatus?.state;
      var returnCode = client.connectionStatus?.returnCode;
      
      // Wait for connection to stabilize, checking state periodically
      int attempts = 0;
      while (state != MqttConnectionState.connected && attempts < 10) {
        await Future.delayed(const Duration(milliseconds: 200));
        state = client.connectionStatus?.state;
        returnCode = client.connectionStatus?.returnCode;
        attempts++;
        
        if (state == MqttConnectionState.disconnected || 
            state == MqttConnectionState.disconnecting) {
          break; // Connection failed, don't wait longer
        }
      }
      
      developer.log(
        '🔍 Connection state check: state=$state, returnCode=$returnCode (after ${attempts * 200}ms)',
        name: 'MqttService',
      );

      // Check return code for authentication/connection errors
      if (returnCode != null && returnCode != MqttConnectReturnCode.connectionAccepted) {
        String errorMsg = 'Connection rejected';
        // Check return code value (using toString for comparison)
        final codeStr = returnCode.toString();
        if (codeStr.contains('identifierRejected')) {
          errorMsg = 'Client identifier rejected';
        } else if (codeStr.contains('badUserNameOrPassword') || codeStr.contains('badUserNamePassword')) {
          errorMsg = 'Bad username or password';
        } else if (codeStr.contains('notAuthorized')) {
          errorMsg = 'Not authorized';
        } else if (codeStr.contains('serverUnavailable')) {
          errorMsg = 'Server unavailable';
        } else if (codeStr.contains('badProtocolVersion')) {
          errorMsg = 'Bad protocol version';
        } else {
          errorMsg = 'Connection rejected (code: $returnCode)';
        }
        _lastError = '$_errorTag $errorMsg ($attemptName)';
        developer.log('❌ $_lastError', name: 'MqttService');
        try {
          client.disconnect();
        } catch (_) {}
        return false;
      }

      if (state == MqttConnectionState.connected) {
        // Clean up previous client
        if (previousClient != null) {
          try {
            previousClient.disconnect();
          } catch (_) {}
        }
        
        _client = client;
        _isConnected = true;
        developer.log(
          '✅ MQTT connected successfully ($attemptName)',
          name: 'MqttService',
        );
        
        // Set up message listener
        _client!.updates?.listen(
          _onMessage,
          onError: (error) {
            developer.log(
              '❌ MQTT message stream error: $error',
              name: 'MqttService',
              error: error,
            );
          },
        );
        
        return true;
      }

      _lastError = '$_errorTag Connect failed ($attemptName). State: $state, Return code: $returnCode';
      developer.log('❌ $_lastError', name: 'MqttService');
      try {
        client.disconnect();
      } catch (_) {}
      return false;
    } catch (e, stackTrace) {
      _lastError = '$_errorTag Connect error ($attemptName): $e';
      developer.log(
        '❌ $_lastError',
        name: 'MqttService',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Disconnect from MQTT broker
  Future<void> disconnect() async {
    if (_client != null) {
      developer.log('🔌 Disconnecting from MQTT', name: 'MqttService');
      try {
        if (_isConnected) {
          _client!.disconnect();
        }
      } catch (e) {
        developer.log('⚠️ Error during disconnect: $e', name: 'MqttService');
      }
      _isConnected = false;
      _subscribedTopics.clear();
      _client = null;
    }
  }

  /// Subscribe to a topic
  /// 
  /// [topic] - Topic to subscribe to (e.g., 'carpool/drivers/123/location')
  /// [qos] - Quality of Service level (0, 1, or 2)
  Future<bool> subscribe(String topic, {MqttQos qos = MqttQos.atLeastOnce}) async {
    if (!_isConnected || _client == null) {
      _lastError =
          '$_errorTag Subscribe failed: not connected (state=${_client?.connectionStatus?.state})';
      developer.log(
        '❌ $_lastError',
        name: 'MqttService',
      );
      return false;
    }

    if (_subscribedTopics.contains(topic)) {
      developer.log(
        '⚠️ Already subscribed to: $topic',
        name: 'MqttService',
      );
      return true;
    }

    try {
      // Double-check connection state
      if (_client!.connectionStatus?.state != MqttConnectionState.connected) {
        _lastError =
            '$_errorTag Subscribe failed: state=${_client!.connectionStatus?.state}';
        developer.log(
          '❌ $_lastError',
          name: 'MqttService',
        );
        return false;
      }

      _client!.subscribe(topic, qos);
      
      // Wait a bit for subscription acknowledgment
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Verify subscription was successful
      final subscriptionStatus = _client!.getSubscriptionsStatus(topic);
      developer.log(
        '🔍 Subscription status for $topic: $subscriptionStatus',
        name: 'MqttService',
      );
      
      _subscribedTopics.add(topic);
      developer.log(
        '✅ Subscribed to: $topic (QoS: $qos)',
        name: 'MqttService',
      );
      developer.log(
        '✅ All subscribed topics: $_subscribedTopics',
        name: 'MqttService',
      );
      return true;
    } catch (e, stackTrace) {
      _lastError = '$_errorTag Error subscribing to $topic: $e';
      developer.log(
        '❌ $_lastError',
        name: 'MqttService',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Unsubscribe from a topic
  Future<bool> unsubscribe(String topic) async {
    if (!_isConnected || _client == null) {
      return false;
    }

    if (!_subscribedTopics.contains(topic)) {
      return true; // Already unsubscribed
    }

    try {
      _client!.unsubscribe(topic);
      _subscribedTopics.remove(topic);
      developer.log('✅ Unsubscribed from: $topic', name: 'MqttService');
      return true;
    } catch (e) {
      developer.log(
        '❌ Error unsubscribing from $topic: $e',
        name: 'MqttService',
      );
      return false;
    }
  }

  /// Publish a message to a topic
  /// 
  /// [topic] - Topic to publish to
  /// [payload] - Message payload (string)
  /// [qos] - Quality of Service level
  /// [retain] - Whether to retain the message
  Future<bool> publish({
    required String topic,
    required String payload,
    MqttQos qos = MqttQos.atLeastOnce,
    bool retain = false,
  }) async {
    if (!_isConnected || _client == null) {
      developer.log(
        '❌ Cannot publish: not connected',
        name: 'MqttService',
      );
      return false;
    }

    try {
      final builder = MqttClientPayloadBuilder();
      builder.addString(payload);

      _client!.publishMessage(
        topic,
        qos,
        builder.payload!,
        retain: retain,
      );

      developer.log(
        '📤 Published to $topic: ${payload.length} bytes',
        name: 'MqttService',
      );
      return true;
    } catch (e) {
      developer.log(
        '❌ Error publishing to $topic: $e',
        name: 'MqttService',
      );
      return false;
    }
  }

  /// Connection callback
  void _onConnected() {
    developer.log('✅ MQTT connection established', name: 'MqttService');
  }

  /// Disconnection callback
  void _onDisconnected() {
    developer.log('🔌 MQTT disconnected', name: 'MqttService');
    _isConnected = false;
    _subscribedTopics.clear();
  }

  /// Subscription callback
  void _onSubscribed(String topic) {
    developer.log('✅ Subscribed to: $topic', name: 'MqttService');
  }

  /// Message received callback
  void _onMessage(List<MqttReceivedMessage<MqttMessage>> messages) {
    developer.log(
      '📨 [MQTT_SERVICE] Received ${messages.length} message(s) from broker',
      name: 'MqttService',
    );
    
    for (final message in messages) {
      final topic = message.topic;
      final payload = message.payload;

      developer.log(
        '📨 [MQTT_SERVICE] Message on topic: $topic',
        name: 'MqttService',
      );
      developer.log(
        '📨 [MQTT_SERVICE] Payload type: ${payload.runtimeType}',
        name: 'MqttService',
      );
      developer.log(
        '📨 [MQTT_SERVICE] Subscribed topics: $_subscribedTopics',
        name: 'MqttService',
      );

      // Forward message to stream
      if (!_messageController.isClosed) {
        _messageController.add(message);
        developer.log(
          '✅ [MQTT_SERVICE] Forwarded message to stream: $topic',
          name: 'MqttService',
        );
      } else {
        developer.log(
          '⚠️ [MQTT_SERVICE] Message controller is closed, cannot forward: $topic',
          name: 'MqttService',
        );
      }
    }
  }

  /// Dispose resources
  void dispose() {
    developer.log('🗑️ Disposing MQTT service', name: 'MqttService');
    disconnect();
    if (!_messageController.isClosed) {
      _messageController.close();
    }
  }
}

