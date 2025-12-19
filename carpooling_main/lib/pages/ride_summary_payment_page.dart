import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:carpooling_main/core/utils/timezone_helper.dart';
import 'dart:developer' as developer;

/// Ride Summary and Payment Page (Passenger Side)
/// Shown after driver completes the ride
class RideSummaryPaymentPage extends StatefulWidget {
  final String bookingId;

  const RideSummaryPaymentPage({
    super.key,
    required this.bookingId,
  });

  @override
  State<RideSummaryPaymentPage> createState() =>
      _RideSummaryPaymentPageState();
}

class _RideSummaryPaymentPageState extends State<RideSummaryPaymentPage> {
  final _supabase = Supabase.instance.client;
  
  Map<String, dynamic>? _bookingData;
  Map<String, dynamic>? _rideData;
  Map<String, dynamic>? _driverData;
  Map<String, dynamic>? _vehicleData;
  bool _isLoading = true;
  String? _errorMessage;
  
  String _paymentStatus = 'pending';
  bool _isProcessingPayment = false;
  
  // Rating
  double _rating = 0;
  final _reviewController = TextEditingController();
  bool _hasRated = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      developer.log('📥 Loading booking: ${widget.bookingId}', name: 'RideSummaryPayment');
      
      // Get booking first
      final bookingResponse = await _supabase
          .from('bookings')
          .select('*')
          .eq('id', widget.bookingId)
          .single();
      
      developer.log('✅ Booking loaded: ${bookingResponse['request_status']}', name: 'RideSummaryPayment');
      
      // Get ride info
      final rideId = bookingResponse['ride_id'];
      final rideResponse = await _supabase
          .from('rides')
          .select('*')
          .eq('id', rideId)
          .maybeSingle();
      
      // Determine driver ID
      String? driverId;
      if (rideResponse != null) {
        driverId = rideResponse['driver_id'] as String?;
      } else {
        // Try to get driver_id from booking (if added via SQL)
        driverId = bookingResponse['driver_id'] as String?;
        developer.log('⚠️ Ride not found, using booking.driver_id: $driverId', name: 'RideSummaryPayment');
      }
      
      // Get driver info
      Map<String, dynamic>? driverResponse;
      Map<String, dynamic>? vehicleData;
      
      if (driverId != null) {
        driverResponse = await _supabase
            .from('profiles')
            .select('full_name, email, avatar_url, phone_number, tng_qr_code, tng_phone_number')
            .eq('id', driverId)
            .maybeSingle();
        
        // Fetch vehicle information from driver_verifications
        try {
          final verificationResponse = await _supabase
              .from('driver_verifications')
              .select('vehicle_model, vehicle_color, vehicle_plate_number')
              .eq('user_id', driverId)
              .maybeSingle();
          
          if (verificationResponse != null) {
            vehicleData = {
              'vehicle_model': verificationResponse['vehicle_model'],
              'vehicle_color': verificationResponse['vehicle_color'],
              'vehicle_plate': verificationResponse['vehicle_plate_number'],
            };
            developer.log('✅ Vehicle data loaded: $vehicleData', name: 'RideSummaryPayment');
          }
        } catch (e) {
          developer.log('⚠️ Error fetching vehicle data: $e', name: 'RideSummaryPayment');
        }
      }
      
      // Build response object
      final response = {
        ...bookingResponse,
        'ride': {
          'id': rideId,
          'from_location': rideResponse?['from_location'] ?? bookingResponse['pickup_location'] ?? 'Pickup Location',
          'to_location': rideResponse?['to_location'] ?? bookingResponse['destination'] ?? 'Destination',
          'scheduled_time': rideResponse?['scheduled_time'] ?? bookingResponse['created_at'],
          'driver_id': driverId,
          'driver': driverResponse ?? {
            'full_name': 'Driver',
            'email': '',
            'avatar_url': null,
            'phone_number': null,
            'tng_qr_code': null,
            'tng_phone_number': null,
          },
          'vehicle': vehicleData ?? {
            'vehicle_model': 'Not specified',
            'vehicle_color': 'Not specified',
            'vehicle_plate': 'Not specified',
          },
        },
      };

      // Check if already rated
      final existingRating = await _supabase
          .from('driver_ratings')
          .select()
          .eq('booking_id', widget.bookingId)
          .maybeSingle();

      setState(() {
        _bookingData = response;
        _rideData = response['ride'] as Map<String, dynamic>;
        _driverData = _rideData!['driver'] as Map<String, dynamic>;
        _vehicleData = _rideData!['vehicle'] as Map<String, dynamic>?;
        _paymentStatus = _bookingData!['payment_status'] ?? 'pending';
        
        // Calculate total_price if not present (fare_per_seat * seats_requested)
        if (_bookingData!['total_price'] == null) {
          final farePerSeat = (_bookingData!['fare_per_seat'] as num?)?.toDouble() ?? 0.0;
          final seatsRequested = (_bookingData!['seats_requested'] as int?) ?? 1;
          _bookingData!['total_price'] = farePerSeat * seatsRequested;
        }
        
        _hasRated = existingRating != null;
        if (_hasRated && existingRating != null) {
          _rating = (existingRating['rating'] as num?)?.toDouble() ?? 0;
          _reviewController.text = (existingRating['review'] as String?) ?? '';
        }
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      developer.log('❌ Error loading ride summary: $e', name: 'RideSummaryPayment', error: e, stackTrace: stackTrace);
      developer.log('   BookingId: ${widget.bookingId}', name: 'RideSummaryPayment');
      
      // Print detailed error for debugging
      print('');
      print('═══════════════════════════════════════════════════════════');
      print('❌ PAYMENT PAGE ERROR');
      print('═══════════════════════════════════════════════════════════');
      print('Booking ID: ${widget.bookingId}');
      print('Error: $e');
      print('Stack trace:');
      print(stackTrace);
      print('═══════════════════════════════════════════════════════════');
      print('');
      
      setState(() {
        if (e.toString().contains('No rows')) {
          _errorMessage = 'Ride not found. It may have been deleted or completed.';
        } else if (e.toString().contains('ride_id')) {
          _errorMessage = 'Could not load ride information. The ride may have been deleted.';
        } else {
          _errorMessage = 'Failed to load ride details: ${e.toString()}';
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _confirmCashPayment() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Cash Payment'),
        content: Text(
          'I confirm that I have paid RM ${(_bookingData!['total_price'] as num).toStringAsFixed(2)} in cash to the driver.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      setState(() => _isProcessingPayment = true);
      
      // Update booking payment status directly
      await _supabase
          .from('bookings')
          .update({
            'payment_status': 'paid_cash',
            'payment_method': 'cash',
          })
          .eq('id', widget.bookingId);

      setState(() => _isProcessingPayment = false);
      
      await _loadData(); // Reload data to update payment status

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Cash payment confirmed!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isProcessingPayment = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _confirmTngPayment() async {
    try {
      setState(() => _isProcessingPayment = true);
      
      // Update booking payment status directly
      await _supabase
          .from('bookings')
          .update({
            'payment_status': 'paid_tng',
            'payment_method': 'tng',
          })
          .eq('id', widget.bookingId);

      if (mounted) {
        Navigator.pop(context); // Close TNG dialog first
        
        setState(() => _isProcessingPayment = false);
        
        await _loadData(); // Reload data to update payment status
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ TNG payment confirmed!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isProcessingPayment = false);
      if (mounted) {
        Navigator.pop(context); // Close dialog on error too
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showTngPayment() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Touch \'n Go Payment'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Amount: RM ${(_bookingData!['total_price'] as num).toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              if (_driverData!['tng_qr_code'] != null) ...[
                const Text('Scan driver\'s QR code:'),
                const SizedBox(height: 16),
                // Display QR code image from URL
                Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      _driverData!['tng_qr_code'],
                      width: 200,
                      height: 200,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.grey.shade200,
                          child: const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.error_outline, color: Colors.red),
                                SizedBox(height: 8),
                                Text(
                                  'Failed to load QR',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          color: Colors.grey.shade100,
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (_driverData!['tng_phone_number'] != null && _driverData!['tng_phone_number'].toString().isNotEmpty) ...[
                const Divider(height: 32),
                const Text('Or transfer to TNG number:'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.phone_android, color: Colors.green.shade700, size: 20),
                      const SizedBox(width: 8),
                      SelectableText(
                        '+60 ${_driverData!['tng_phone_number']}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const Text(
                'After completing payment in TNG app, tap confirm below.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _isProcessingPayment ? null : _confirmTngPayment,
            child: _isProcessingPayment
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('I\'ve Paid'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitRating() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a rating'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      setState(() => _isProcessingPayment = true);

      await _supabase.from('driver_ratings').insert({
        'driver_id': _rideData!['driver_id'],
        'passenger_id': _supabase.auth.currentUser!.id,
        'ride_id': _rideData!['id'],
        'booking_id': widget.bookingId,
        'rating': _rating,
        'review': _reviewController.text.trim(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      setState(() {
        _hasRated = true;
        _isProcessingPayment = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Thank you for your feedback!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isProcessingPayment = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _endRide() async {
    // Check if rated
    if (!_hasRated) {
      final rateNow = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Rate Your Driver'),
          content: const Text('Would you like to rate your driver before ending the ride?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Skip'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Rate Now'),
            ),
          ],
        ),
      );

      if (rateNow == true) {
        // Scroll to rating section
        return;
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End Ride'),
        content: const Text('Confirm that your ride is complete?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End Ride'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Save ride to history
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');

      // Check if record already exists
      final existingRecord = await _supabase
          .from('ride_history')
          .select('id')
          .eq('booking_id', widget.bookingId)
          .maybeSingle();

      final rideHistoryData = {
        'booking_id': widget.bookingId,
        'ride_id': _rideData!['id'],
        'passenger_id': userId,
        'driver_id': _rideData!['driver_id'],
        'from_location': _rideData!['from_location'],
        'to_location': _rideData!['to_location'],
        'fare_amount': _bookingData!['total_price'],
        'payment_status': _paymentStatus,
        'payment_method': _bookingData!['payment_method'],
        'driver_name': _driverData!['full_name'],
        'driver_avatar_url': _driverData!['avatar_url'],
        'vehicle_plate': _vehicleData?['vehicle_plate'],
        'vehicle_model': _vehicleData?['vehicle_model'],
        'completed_at': DateTime.now().toUtc().toIso8601String(),
      };

      if (existingRecord != null) {
        // Update existing record
        await _supabase
            .from('ride_history')
            .update(rideHistoryData)
            .eq('booking_id', widget.bookingId);
        developer.log('✅ Updated existing ride history', name: 'RideSummaryPayment');
      } else {
        // Insert new record
        await _supabase.from('ride_history').insert(rideHistoryData);
        developer.log('✅ Inserted new ride history', name: 'RideSummaryPayment');
      }
      
      if (mounted) {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Ride completed! Thank you for using CampusCar!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        
        // Wait a moment then redirect to dashboard
        await Future.delayed(const Duration(milliseconds: 500));
        
        if (mounted) {
          // Navigate to dashboard (pop all routes)
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }
    } catch (e) {
      developer.log('❌ Error ending ride: $e', name: 'RideSummaryPayment');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ride Summary')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Error'),
          backgroundColor: Colors.red,
          leading: IconButton(
            icon: const Icon(Icons.home),
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 80, color: Colors.red),
                const SizedBox(height: 24),
                const Text(
                  'Failed to load ride details',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _loadData,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      },
                      icon: const Icon(Icons.home),
                      label: const Text('Go Home'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final isPaid = _paymentStatus != 'pending';

    return WillPopScope(
      onWillPop: () async {
        // Go back to dashboard/home
        Navigator.of(context).popUntil((route) => route.isFirst);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ride Summary'),
          backgroundColor: Colors.green,
          leading: IconButton(
            icon: const Icon(Icons.home),
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
        ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isPaid ? Colors.green.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isPaid ? Colors.green : Colors.orange,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isPaid ? Icons.check_circle : Icons.payment,
                    color: isPaid ? Colors.green : Colors.orange,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isPaid ? 'Payment Complete' : 'Payment Pending',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isPaid ? Colors.green : Colors.orange,
                          ),
                        ),
                        Text(
                          isPaid
                              ? 'Thank you! You can now end the ride.'
                              : 'Please select payment method below.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Ride Details
            _buildSection(
              'Ride Details',
              Icons.directions_car,
              [
                _buildDetailRow(
                  'From',
                  _bookingData!['pickup_location'] as String? ?? _rideData!['from_location'],
                  maxLines: 2,
                ),
                _buildDetailRow(
                  'To',
                  _bookingData!['destination'] as String? ?? _rideData!['to_location'],
                  maxLines: 2,
                ),
                _buildDetailRow(
                  'Date',
                  TimezoneHelper.formatMalaysiaDateTime(
                    TimezoneHelper.utcToMalaysia(
                      DateTime.parse(_rideData!['scheduled_time'] as String).toUtc(),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Driver Info
            _buildSection(
              'Driver',
              Icons.person,
              [
                ListTile(
                  leading: CircleAvatar(
                    backgroundImage: _driverData!['avatar_url'] != null
                        ? NetworkImage(_driverData!['avatar_url'])
                        : null,
                    backgroundColor: Colors.grey.shade300,
                    child: _driverData!['avatar_url'] == null
                        ? const Icon(Icons.person)
                        : null,
                  ),
                  title: Text(
                    _driverData!['full_name'] ?? _driverData!['email'] ?? 'N/A',
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _driverData!['phone_number'] ?? 'N/A',
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_vehicleData != null && 
                          _vehicleData!['vehicle_plate'] != null && 
                          _vehicleData!['vehicle_plate'] != 'Not specified')
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Icon(Icons.directions_car, size: 14, color: Colors.grey[600]),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '${_vehicleData!['vehicle_model'] ?? 'N/A'} (${_vehicleData!['vehicle_plate']})',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Payment Info
            _buildSection(
              'Payment',
              Icons.payments,
              [
                _buildDetailRow(
                  'Amount',
                  'RM ${(_bookingData!['total_price'] as num).toStringAsFixed(2)}',
                ),
                _buildDetailRow('Status', _paymentStatus.toUpperCase()),
                if (_bookingData!['payment_method'] != null)
                  _buildDetailRow(
                    'Method',
                    _bookingData!['payment_method'].toString().toUpperCase(),
                  ),
              ],
            ),

            const SizedBox(height: 24),

            // Payment Buttons
            if (!isPaid) ...[
              ElevatedButton.icon(
                onPressed: _isProcessingPayment ? null : _confirmCashPayment,
                icon: const Icon(Icons.money),
                label: const Text('Pay by Cash'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _isProcessingPayment ? null : _showTngPayment,
                icon: const Icon(Icons.qr_code),
                label: const Text('Pay by Touch \'n Go'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ],

            // Rating Section
            if (isPaid) ...[
              const SizedBox(height: 24),
              _buildSection(
                'Rate Your Driver',
                Icons.star,
                [
                  if (_hasRated)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green.shade700),
                          const SizedBox(width: 8),
                          Text(
                            'You rated this driver ${_rating.toStringAsFixed(1)} stars',
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    const Text(
                      'How was your ride? Your feedback helps improve our service.',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(5, (index) {
                          return IconButton(
                            onPressed: () {
                              setState(() {
                                _rating = index + 1.0;
                              });
                            },
                            icon: Icon(
                              index < _rating ? Icons.star : Icons.star_border,
                              size: 40,
                              color: Colors.amber,
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _reviewController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Write a review (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _isProcessingPayment ? null : _submitRating,
                      icon: _isProcessingPayment
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      label: const Text('Submit Rating'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                      ),
                    ),
                  ],
                ],
              ),

              // End Ride Button (only show if payment is paid)
              if (isPaid) ...[
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _endRide,
                  icon: const Icon(Icons.check_circle),
                  label: const Text('End Ride'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ],
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildSection(String title, IconData icon, List<Widget> children) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {int? maxLines}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
              maxLines: maxLines ?? 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
