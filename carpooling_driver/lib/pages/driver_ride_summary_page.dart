import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:carpooling_driver/core/utils/timezone_helper.dart';
import 'dart:developer' as developer;

/// Driver Ride Summary Page
/// Shown after completing a ride
class DriverRideSummaryPage extends StatefulWidget {
  final String rideId;

  const DriverRideSummaryPage({
    super.key,
    required this.rideId,
  });

  @override
  State<DriverRideSummaryPage> createState() => _DriverRideSummaryPageState();
}

class _DriverRideSummaryPageState extends State<DriverRideSummaryPage> {
  final _supabase = Supabase.instance.client;
  
  Map<String, dynamic>? _rideData;
  List<Map<String, dynamic>> _passengers = [];
  bool _isLoading = true;
  String? _errorMessage;
  
  double _totalExpectedEarnings = 0.0; // Total from all accepted passengers
  double _totalPaidEarnings = 0.0;     // Only from paid passengers
  int _paidPassengers = 0;
  
  String? _driverTngQrCode; // Driver's TNG QR code URL
  String? _driverTngPhone; // Driver's TNG phone number
  
  // Real-time subscription
  RealtimeChannel? _realtimeChannel;
  
  // Track which passenger just paid for animation
  String? _justPaidPassengerId;

  @override
  void initState() {
    super.initState();
    _loadData();
    _setupRealtimeListener();
  }
  
  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }
  
  void _setupRealtimeListener() {
    developer.log('🔄 Setting up real-time payment updates for ride: ${widget.rideId}', name: 'DriverSummary');
    
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
            developer.log('💰 Payment status updated: ${payload.newRecord}', name: 'DriverSummary');
            
            // Reload data when payment status changes
            if (mounted) {
              final newRecord = payload.newRecord;
              final passengerId = newRecord['passenger_id'] as String?;
              
              // Track which passenger just paid for highlight animation
              if (passengerId != null && 
                  (newRecord['payment_status'] == 'paid_cash' || 
                   newRecord['payment_status'] == 'paid_tng')) {
                setState(() {
                  _justPaidPassengerId = passengerId;
                });
                
                // Remove highlight after 3 seconds
                Future.delayed(const Duration(seconds: 3), () {
                  if (mounted) {
                    setState(() {
                      _justPaidPassengerId = null;
                    });
                  }
                });
              }
              
              _loadData();
              
              // Show notification if payment was made
              if (newRecord['payment_status'] == 'paid_cash' || 
                  newRecord['payment_status'] == 'paid_tng') {
                final paymentMethod = newRecord['payment_status'] == 'paid_cash' ? 'Cash' : 'Touch \'n Go';
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.white),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('Payment confirmed via $paymentMethod!'),
                        ),
                      ],
                    ),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 3),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            }
          },
        )
        .subscribe();
  }

  Future<void> _loadData() async {
    try {
      developer.log('🔄 Loading ride summary for ride: ${widget.rideId}', name: 'DriverSummary');
      
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      // Get ride details
      final rideResponse = await _supabase
          .from('rides')
          .select('*')
          .eq('id', widget.rideId)
          .single();
      
      developer.log('✅ Ride data loaded: ${rideResponse['from_location']} → ${rideResponse['to_location']}', name: 'DriverSummary');

      // Get all bookings for this ride (accepted or completed)
      final bookingsResponse = await _supabase
          .from('bookings')
          .select('*')
          .eq('ride_id', widget.rideId)
          .or('request_status.eq.accepted,request_status.eq.completed');
      
      developer.log('✅ Found ${bookingsResponse.length} accepted bookings', name: 'DriverSummary');
      
      // Get passenger profiles separately
      final List<Map<String, dynamic>> bookingsWithProfiles = [];
      for (final booking in bookingsResponse) {
        final passengerId = booking['passenger_id'];
        final profileResponse = await _supabase
            .from('profiles')
            .select('full_name, email, avatar_url')
            .eq('id', passengerId)
            .maybeSingle();
        
        bookingsWithProfiles.add({
          ...booking,
          'profiles': profileResponse ?? {'full_name': 'Passenger', 'email': ''},
        });
      }

      // Calculate earnings from passenger fares
      double totalExpected = 0.0;
      double totalPaid = 0.0;
      int paidCount = 0;
      
      for (final booking in bookingsWithProfiles) {
        final paymentStatus = booking['payment_status'] ?? 'pending';
        final farePerSeat = (booking['fare_per_seat'] as num?)?.toDouble() ?? 0.0;
        final seatsRequested = (booking['seats_requested'] as int?) ?? 1;
        final totalFare = farePerSeat * seatsRequested;
        
        developer.log('  - Passenger: ${booking['profiles']?['full_name'] ?? 'Unknown'}, Status: $paymentStatus, Fare: RM $farePerSeat x $seatsRequested = RM $totalFare', name: 'DriverSummary');
        
        // Count ALL accepted bookings for expected earnings
        totalExpected += totalFare;
        
        // Count only paid bookings for paid earnings
        if (paymentStatus == 'paid_cash' || paymentStatus == 'paid_tng') {
          totalPaid += totalFare;
          paidCount++;
        }
      }
      
      developer.log('💰 Expected earnings: RM $totalExpected | Paid: RM $totalPaid ($paidCount of ${bookingsWithProfiles.length} paid)', name: 'DriverSummary');

      // Get driver's TNG QR code from profile
      final currentUserId = _supabase.auth.currentUser?.id;
      String? tngQrCode;
      String? tngPhone;
      
      if (currentUserId != null) {
        try {
          final driverProfile = await _supabase
              .from('profiles')
              .select('tng_qr_code, tng_phone_number')
              .eq('id', currentUserId)
              .maybeSingle();
          
          if (driverProfile != null) {
            tngQrCode = driverProfile['tng_qr_code'] as String?;
            tngPhone = driverProfile['tng_phone_number'] as String?;
            developer.log('✅ Driver TNG info loaded: QR=${tngQrCode != null ? "Available" : "Not set"}, Phone=$tngPhone', name: 'DriverSummary');
          }
        } catch (e) {
          developer.log('⚠️ Could not fetch driver TNG info: $e', name: 'DriverSummary');
        }
      }

      setState(() {
        _rideData = rideResponse;
        _passengers = bookingsWithProfiles;
        _totalExpectedEarnings = totalExpected;
        _totalPaidEarnings = totalPaid;
        _paidPassengers = paidCount;
        _driverTngQrCode = tngQrCode;
        _driverTngPhone = tngPhone;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      developer.log('❌ Error loading ride summary: $e', name: 'DriverSummary', error: e, stackTrace: stackTrace);
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
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
        appBar: AppBar(title: const Text('Ride Summary')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text('Error: $_errorMessage'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadData,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final theme = Theme.of(context);

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
              // Earnings Summary Card
              Card(
                elevation: 4,
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            Icons.monetization_on,
                            size: 64,
                            color: Colors.green.shade700,
                          ),
                          if (_justPaidPassengerId != null)
                            Positioned(
                              top: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.update,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Total Earnings',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.refresh, size: 12, color: Colors.blue.shade700),
                                const SizedBox(width: 4),
                                Text(
                                  'LIVE',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'RM ${_totalExpectedEarnings.toStringAsFixed(2)}',
                        style: theme.textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_totalPaidEarnings < _totalExpectedEarnings)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'RM ${_totalPaidEarnings.toStringAsFixed(2)} paid, RM ${(_totalExpectedEarnings - _totalPaidEarnings).toStringAsFixed(2)} pending',
                            style: TextStyle(
                              color: Colors.orange.shade900,
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Text(
                        '$_paidPassengers of ${_passengers.length} passengers paid',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Ride Details
              _buildSection(
                'Ride Details',
                Icons.directions_car,
                [
                  _buildDetailRow('From', _rideData!['from_location']),
                  _buildDetailRow('To', _rideData!['to_location']),
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

              // Passengers
              _buildSection(
                'Passengers (${_passengers.length})',
                Icons.people,
                _passengers.map((passenger) {
                  final profile = passenger['profiles'] as Map<String, dynamic>?;
                  final name = profile?['full_name'] ?? profile?['email'] ?? 'Passenger';
                  final passengerId = passenger['passenger_id'] as String;
                  final paymentStatus = passenger['payment_status'] ?? 'pending';
                  final farePerSeat = (passenger['fare_per_seat'] as num?)?.toDouble() ?? 0.0;
                  final seatsRequested = (passenger['seats_requested'] as int?) ?? 1;
                  final totalFare = farePerSeat * seatsRequested;
                  final isPaid = paymentStatus == 'paid_cash' || paymentStatus == 'paid_tng';
                  final justPaid = _justPaidPassengerId == passengerId;
                  
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    decoration: BoxDecoration(
                      color: justPaid ? Colors.green.shade100 : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: Stack(
                        children: [
                          CircleAvatar(
                            backgroundImage: profile?['avatar_url'] != null
                                ? NetworkImage(profile!['avatar_url'])
                                : null,
                            child: profile?['avatar_url'] == null
                                ? const Icon(Icons.person)
                                : null,
                          ),
                          if (justPaid)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check,
                                  size: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Row(
                        children: [
                          Expanded(child: Text(name)),
                          if (justPaid)
                            const Icon(
                              Icons.celebration,
                              size: 16,
                              color: Colors.green,
                            ),
                        ],
                      ),
                      subtitle: Text('RM ${totalFare.toStringAsFixed(2)} ($seatsRequested seat${seatsRequested > 1 ? 's' : ''})'),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isPaid
                              ? Colors.green.shade100
                              : Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: justPaid ? Border.all(color: Colors.green, width: 2) : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isPaid)
                              Icon(
                                Icons.check_circle,
                                size: 14,
                                color: Colors.green.shade700,
                              ),
                            if (isPaid) const SizedBox(width: 4),
                            Text(
                              isPaid ? 'PAID' : 'PENDING',
                              style: TextStyle(
                                color: isPaid
                                    ? Colors.green.shade700
                                    : Colors.orange.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 24),

              // Touch 'n Go Payment Details (only show if QR code is uploaded)
              if (_driverTngQrCode != null && _driverTngQrCode!.isNotEmpty)
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.green.shade50, Colors.blue.shade50],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        // Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.qr_code_scanner,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Touch \'n Go Payment',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Scan QR Code to Pay',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        // QR Code Display
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.green.shade300, width: 3),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green.shade200,
                                blurRadius: 15,
                                spreadRadius: 3,
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(20),
                          child: Image.network(
                            _driverTngQrCode!,
                            width: 260,
                            height: 260,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: 260,
                                height: 260,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.error_outline, size: 60, color: Colors.red.shade300),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Failed to load QR code',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                width: 260,
                                height: 260,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      CircularProgressIndicator(
                                        value: loadingProgress.expectedTotalBytes != null
                                            ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                            : null,
                                        color: Colors.green,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Loading QR code...',
                                        style: TextStyle(color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        
                        if (_driverTngPhone != null && _driverTngPhone!.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          Divider(color: Colors.grey.shade300, thickness: 1),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.phone_android, color: Colors.green.shade700, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Or transfer to:',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.green.shade300, width: 2),
                            ),
                            child: SelectableText(
                              '+60 ${_driverTngPhone!}',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade800,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ],
                        
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, size: 22, color: Colors.blue.shade700),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'After completing payment in TNG app, inform the driver',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.blue.shade800,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 24),

              // Back to Home Button
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                icon: const Icon(Icons.home),
                label: const Text('Back to Home'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
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

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
            label,
            style: const TextStyle(color: Colors.grey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
            value,
              textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.bold),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

