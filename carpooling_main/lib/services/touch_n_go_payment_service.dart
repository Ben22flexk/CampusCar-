import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:developer' as developer;

/// Touch 'n Go Payment Integration Service
class TouchNGoPaymentService {
  final _supabase = Supabase.instance.client;
  
  // TODO: Replace with actual Touch 'n Go API credentials
  static const String _tngApiUrl = 'https://api.touchngo.com.my/v1'; // Example
  static const String _merchantId = 'YOUR_MERCHANT_ID';
  static const String _apiKey = 'YOUR_API_KEY';
  
  /// Initiate payment for a ride
  Future<PaymentResult> initiatePayment({
    required String rideId,
    required String driverId,
    required double amount,
  }) async {
    try {
      final passengerId = _supabase.auth.currentUser?.id;
      if (passengerId == null) {
        return PaymentResult(
          success: false,
          message: 'User not authenticated',
        );
      }

      developer.log('💳 Initiating Touch n Go payment: RM${amount.toStringAsFixed(2)}', name: 'Payment');

      // Create payment transaction record
      final transactionData = {
        'ride_id': rideId,
        'passenger_id': passengerId,
        'driver_id': driverId,
        'amount': amount,
        'currency': 'MYR',
        'payment_method': 'touch_n_go',
        'tng_status': 'pending',
        'payment_status': 'pending',
        'payment_initiated_at': DateTime.now().toUtc().toIso8601String(),
      };

      final transaction = await _supabase
          .from('payment_transactions')
          .insert(transactionData)
          .select()
          .single();

      final transactionId = transaction['id'] as String;

      // TODO: Call actual Touch 'n Go API
      // For now, simulate payment URL
      final paymentUrl = await _createTouchNGoPaymentUrl(
        transactionId: transactionId,
        amount: amount,
        rideId: rideId,
      );

      developer.log('✅ Payment URL generated: $paymentUrl', name: 'Payment');

      return PaymentResult(
        success: true,
        transactionId: transactionId,
        paymentUrl: paymentUrl,
        message: 'Payment initiated successfully',
      );
    } catch (e) {
      developer.log('❌ Error initiating payment: $e', name: 'Payment');
      return PaymentResult(
        success: false,
        message: 'Failed to initiate payment: $e',
      );
    }
  }

  /// Create Touch 'n Go payment URL
  Future<String> _createTouchNGoPaymentUrl({
    required String transactionId,
    required double amount,
    required String rideId,
  }) async {
    // TODO: Implement actual Touch 'n Go API call
    // This is a placeholder implementation
    
    // Example: Generate payment URL with Touch 'n Go SDK
    /*
    final response = await http.post(
      Uri.parse('$_tngApiUrl/payment/create'),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'merchant_id': _merchantId,
        'transaction_id': transactionId,
        'amount': (amount * 100).toInt(), // Convert to cents
        'currency': 'MYR',
        'return_url': 'campuscar://payment/success',
        'cancel_url': 'campuscar://payment/cancel',
        'callback_url': 'YOUR_BACKEND_URL/payment/callback',
      }),
    );
    
    final data = jsonDecode(response.body);
    return data['payment_url'];
    */
    
    // For development/testing, return a mock URL
    return 'https://touchngo-mock-payment.com/pay?transaction=$transactionId&amount=$amount';
  }

  /// Open Touch 'n Go payment page
  Future<bool> openPaymentPage(String paymentUrl) async {
    try {
      final uri = Uri.parse(paymentUrl);
      if (await canLaunchUrl(uri)) {
        return await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      }
      return false;
    } catch (e) {
      developer.log('❌ Error opening payment page: $e', name: 'Payment');
      return false;
    }
  }

  /// Verify payment status (called after returning from Touch 'n Go)
  Future<PaymentStatus> verifyPaymentStatus(String transactionId) async {
    try {
      // TODO: Verify with Touch 'n Go API
      // For now, check database status
      
      final transaction = await _supabase
          .from('payment_transactions')
          .select()
          .eq('id', transactionId)
          .single();

      final status = transaction['payment_status'] as String;
      
      return PaymentStatus(
        transactionId: transactionId,
        status: status,
        amount: (transaction['amount'] as num).toDouble(),
      );
    } catch (e) {
      developer.log('❌ Error verifying payment: $e', name: 'Payment');
      return PaymentStatus(
        transactionId: transactionId,
        status: 'failed',
        amount: 0.0,
      );
    }
  }

  /// Complete payment (update status to completed)
  Future<bool> completePayment(String transactionId) async {
    try {
      await _supabase
          .from('payment_transactions')
          .update({
            'payment_status': 'completed',
            'tng_status': 'success',
            'payment_completed_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', transactionId);

      developer.log('✅ Payment completed: $transactionId', name: 'Payment');
      return true;
    } catch (e) {
      developer.log('❌ Error completing payment: $e', name: 'Payment');
      return false;
    }
  }

  /// Mock: Simulate successful payment (for testing)
  Future<bool> mockSuccessfulPayment(String transactionId) async {
    try {
      // Simulate Touch 'n Go callback
      await _supabase
          .from('payment_transactions')
          .update({
            'payment_status': 'completed',
            'tng_status': 'success',
            'tng_transaction_id': 'TNG${DateTime.now().millisecondsSinceEpoch}',
            'tng_reference_number': 'REF${DateTime.now().millisecondsSinceEpoch}',
            'payment_completed_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', transactionId);

      developer.log('✅ Mock payment successful: $transactionId', name: 'Payment');
      return true;
    } catch (e) {
      developer.log('❌ Error in mock payment: $e', name: 'Payment');
      return false;
    }
  }
}

/// Payment result
class PaymentResult {
  final bool success;
  final String? transactionId;
  final String? paymentUrl;
  final String message;

  PaymentResult({
    required this.success,
    this.transactionId,
    this.paymentUrl,
    required this.message,
  });
}

/// Payment status
class PaymentStatus {
  final String transactionId;
  final String status; // 'pending', 'completed', 'failed'
  final double amount;

  PaymentStatus({
    required this.transactionId,
    required this.status,
    required this.amount,
  });

  bool get isCompleted => status == 'completed';
  bool get isPending => status == 'pending';
  bool get isFailed => status == 'failed';
}

