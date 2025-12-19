import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:carpooling_driver/core/utils/timezone_helper.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:fl_chart/fl_chart.dart';

/// Driver Reports Page - Daily, Weekly, Monthly reports with PDF export
class DriverReportsPage extends HookConsumerWidget {
  const DriverReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tabController = useTabController(initialLength: 3);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        backgroundColor: Colors.purple,
        bottom: TabBar(
          controller: tabController,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Daily'),
            Tab(text: 'Weekly'),
            Tab(text: 'Monthly'),
          ],
        ),
      ),
      body: TabBarView(
        controller: tabController,
        children: const [
          _DailyReportTab(),
          _WeeklyReportTab(),
          _MonthlyReportTab(),
        ],
      ),
    );
  }
}

/// Daily Report Tab
class _DailyReportTab extends HookConsumerWidget {
  const _DailyReportTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    final selectedDate = useState(TimezoneHelper.nowInMalaysia());

    if (userId == null) {
      return const Center(child: Text('Please log in'));
    }

    final reportFuture = useMemoized(
      () => _fetchDailyReport(supabase, userId, selectedDate.value),
      [userId, selectedDate.value],
    );
    final reportSnapshot = useFuture(reportFuture);

    return Column(
      children: [
        // Date Picker
        _DateSelector(
          selectedDate: selectedDate.value,
          onDateSelected: (date) => selectedDate.value = date,
          mode: 'daily',
        ),
        
        // Report Content
        Expanded(
          child: _buildReportContent(
            context,
            reportSnapshot,
            'No rides on this day',
            () => _generateDailyPDF(reportSnapshot.data!, selectedDate.value),
          ),
        ),
      ],
    );
  }

  Future<ReportData> _fetchDailyReport(
    SupabaseClient supabase,
    String userId,
    DateTime date,
  ) async {
    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // Get completed rides for the day
      final rides = await supabase
          .from('rides')
          .select('id, from_location, to_location, scheduled_time')
          .eq('driver_id', userId)
          .eq('ride_status', 'completed')
          .gte('scheduled_time', startOfDay.toUtc().toIso8601String())
          .lt('scheduled_time', endOfDay.toUtc().toIso8601String());

      double totalEarnings = 0.0;
      int totalPassengers = 0;
      final List<RideEarning> rideEarnings = [];

      for (final ride in rides) {
        final rideId = ride['id'] as String;
        final bookings = await supabase
            .from('bookings')
            .select('passenger_id, fare_per_seat, seats_requested, payment_status')
            .eq('ride_id', rideId)
            .or('request_status.eq.accepted,request_status.eq.completed');

        double rideFare = 0.0;
        final List<PassengerEarning> passengers = [];

        for (final booking in bookings) {
          final passengerId = booking['passenger_id'] as String;
          final profile = await supabase
              .from('profiles')
              .select('full_name')
              .eq('id', passengerId)
              .maybeSingle();

          final farePerSeat = (booking['fare_per_seat'] as num?)?.toDouble() ?? 0.0;
          final seats = (booking['seats_requested'] as int?) ?? 1;
          final fare = farePerSeat * seats;
          
          rideFare += fare;
          totalPassengers += 1;

          passengers.add(PassengerEarning(
            name: profile?['full_name'] ?? 'Passenger',
            fare: fare,
            isPaid: booking['payment_status'] == 'paid_cash' || booking['payment_status'] == 'paid_tng',
          ));
        }

        totalEarnings += rideFare;

        rideEarnings.add(RideEarning(
          from: ride['from_location'],
          to: ride['to_location'],
          time: TimezoneHelper.utcToMalaysia(DateTime.parse(ride['scheduled_time'] as String).toUtc()),
          passengers: passengers,
          totalFare: rideFare,
        ));
      }

      return ReportData(
        totalEarnings: totalEarnings,
        totalRides: rides.length,
        totalPassengers: totalPassengers,
        rideEarnings: rideEarnings,
      );
    } catch (e) {
      print('Error fetching daily report: $e');
      return ReportData(
        totalEarnings: 0.0,
        totalRides: 0,
        totalPassengers: 0,
        rideEarnings: [],
      );
    }
  }

  Future<void> _generateDailyPDF(ReportData data, DateTime date) async {
    final pdf = pw.Document();
    
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Daily Report - ${TimezoneHelper.formatMalaysiaDate(date)}',
                style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 20),
              pw.Text('Total Earnings: RM ${data.totalEarnings.toStringAsFixed(2)}'),
              pw.Text('Total Rides: ${data.totalRides}'),
              pw.Text('Total Passengers: ${data.totalPassengers}'),
              pw.SizedBox(height: 20),
              pw.Text('Ride Details:', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              ...data.rideEarnings.map((ride) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('${TimezoneHelper.formatMalaysiaTime(ride.time)} - ${ride.from} → ${ride.to}'),
                  pw.Text('Fare: RM ${ride.totalFare.toStringAsFixed(2)}'),
                  pw.Text('Passengers:'),
                  ...ride.passengers.map((p) => pw.Text('  • ${p.name}: RM ${p.fare.toStringAsFixed(2)}')),
                  pw.SizedBox(height: 10),
                ],
              )),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }
}

/// Weekly Report Tab
class _WeeklyReportTab extends HookConsumerWidget {
  const _WeeklyReportTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    final now = TimezoneHelper.nowInMalaysia();
    final selectedWeekStart = useState(now.subtract(Duration(days: now.weekday - 1)));

    if (userId == null) {
      return const Center(child: Text('Please log in'));
    }

    final reportFuture = useMemoized(
      () => _fetchWeeklyReport(supabase, userId, selectedWeekStart.value),
      [userId, selectedWeekStart.value],
    );
    final reportSnapshot = useFuture(reportFuture);

    return Column(
      children: [
        // Week Picker
        _WeekSelector(
          selectedWeekStart: selectedWeekStart.value,
          onWeekSelected: (date) => selectedWeekStart.value = date,
        ),
        
        // Report Content with Chart
        Expanded(
          child: _buildReportContentWithChart(
            context,
            reportSnapshot,
            'No rides this week',
            () => _generateWeeklyPDF(reportSnapshot.data!, selectedWeekStart.value),
          ),
        ),
      ],
    );
  }

  Future<ReportData> _fetchWeeklyReport(
    SupabaseClient supabase,
    String userId,
    DateTime weekStart,
  ) async {
    try {
      final weekEnd = weekStart.add(const Duration(days: 7));

      final rides = await supabase
          .from('rides')
          .select('id, from_location, to_location, scheduled_time')
          .eq('driver_id', userId)
          .eq('ride_status', 'completed')
          .gte('scheduled_time', weekStart.toUtc().toIso8601String())
          .lt('scheduled_time', weekEnd.toUtc().toIso8601String());

      double totalEarnings = 0.0;
      int totalPassengers = 0;
      final List<RideEarning> rideEarnings = [];
      final Map<int, double> dailyEarnings = {0: 0, 1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0};

      for (final ride in rides) {
        final rideId = ride['id'] as String;
        final rideTime = TimezoneHelper.utcToMalaysia(DateTime.parse(ride['scheduled_time'] as String).toUtc());
        final dayOfWeek = rideTime.weekday - 1; // 0 = Monday, 6 = Sunday
        
        final bookings = await supabase
            .from('bookings')
            .select('passenger_id, fare_per_seat, seats_requested, payment_status')
            .eq('ride_id', rideId)
            .or('request_status.eq.accepted,request_status.eq.completed');

        double rideFare = 0.0;
        final List<PassengerEarning> passengers = [];

        for (final booking in bookings) {
          final passengerId = booking['passenger_id'] as String;
          final profile = await supabase
              .from('profiles')
              .select('full_name')
              .eq('id', passengerId)
              .maybeSingle();

          final farePerSeat = (booking['fare_per_seat'] as num?)?.toDouble() ?? 0.0;
          final seats = (booking['seats_requested'] as int?) ?? 1;
          final fare = farePerSeat * seats;
          
          rideFare += fare;
          totalPassengers += 1;

          passengers.add(PassengerEarning(
            name: profile?['full_name'] ?? 'Passenger',
            fare: fare,
            isPaid: booking['payment_status'] == 'paid_cash' || booking['payment_status'] == 'paid_tng',
          ));
        }

        totalEarnings += rideFare;
        dailyEarnings[dayOfWeek] = (dailyEarnings[dayOfWeek] ?? 0) + rideFare;

        rideEarnings.add(RideEarning(
          from: ride['from_location'],
          to: ride['to_location'],
          time: rideTime,
          passengers: passengers,
          totalFare: rideFare,
        ));
      }

      return ReportData(
        totalEarnings: totalEarnings,
        totalRides: rides.length,
        totalPassengers: totalPassengers,
        rideEarnings: rideEarnings,
        dailyEarnings: dailyEarnings,
      );
    } catch (e) {
      print('Error fetching weekly report: $e');
      return ReportData(
        totalEarnings: 0.0,
        totalRides: 0,
        totalPassengers: 0,
        rideEarnings: [],
      );
    }
  }

  Future<void> _generateWeeklyPDF(ReportData data, DateTime weekStart) async {
    final weekEnd = weekStart.add(const Duration(days: 6));
    final pdf = pw.Document();
    
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Weekly Report',
                style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text('${TimezoneHelper.formatMalaysiaDate(weekStart)} - ${TimezoneHelper.formatMalaysiaDate(weekEnd)}'),
              pw.SizedBox(height: 20),
              pw.Text('Total Earnings: RM ${data.totalEarnings.toStringAsFixed(2)}'),
              pw.Text('Total Rides: ${data.totalRides}'),
              pw.Text('Total Passengers: ${data.totalPassengers}'),
              pw.SizedBox(height: 20),
              pw.Text('Daily Breakdown:', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              ...['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].asMap().entries.map((entry) {
                final earnings = data.dailyEarnings?[entry.key] ?? 0.0;
                return pw.Text('${entry.value}: RM ${earnings.toStringAsFixed(2)}');
              }),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }
}

/// Monthly Report Tab  
class _MonthlyReportTab extends HookConsumerWidget {
  const _MonthlyReportTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    final now = TimezoneHelper.nowInMalaysia();
    final selectedMonth = useState(DateTime(now.year, now.month, 1));

    if (userId == null) {
      return const Center(child: Text('Please log in'));
    }

    final reportFuture = useMemoized(
      () => _fetchMonthlyReport(supabase, userId, selectedMonth.value),
      [userId, selectedMonth.value],
    );
    final reportSnapshot = useFuture(reportFuture);

    return Column(
      children: [
        // Month Picker
        _MonthSelector(
          selectedMonth: selectedMonth.value,
          onMonthSelected: (date) => selectedMonth.value = date,
        ),
        
        // Report Content
        Expanded(
          child: _buildReportContent(
            context,
            reportSnapshot,
            'No rides this month',
            () => _generateMonthlyPDF(reportSnapshot.data!, selectedMonth.value),
          ),
        ),
      ],
    );
  }

  Future<ReportData> _fetchMonthlyReport(
    SupabaseClient supabase,
    String userId,
    DateTime month,
  ) async {
    try {
      final monthStart = DateTime(month.year, month.month, 1);
      final monthEnd = DateTime(month.year, month.month + 1, 1);

      final rides = await supabase
          .from('rides')
          .select('id, from_location, to_location, scheduled_time')
          .eq('driver_id', userId)
          .eq('ride_status', 'completed')
          .gte('scheduled_time', monthStart.toUtc().toIso8601String())
          .lt('scheduled_time', monthEnd.toUtc().toIso8601String());

      double totalEarnings = 0.0;
      int totalPassengers = 0;
      final List<RideEarning> rideEarnings = [];

      for (final ride in rides) {
        final rideId = ride['id'] as String;
        final bookings = await supabase
            .from('bookings')
            .select('passenger_id, fare_per_seat, seats_requested, payment_status')
            .eq('ride_id', rideId)
            .or('request_status.eq.accepted,request_status.eq.completed');

        double rideFare = 0.0;
        final List<PassengerEarning> passengers = [];

        for (final booking in bookings) {
          final passengerId = booking['passenger_id'] as String;
          final profile = await supabase
              .from('profiles')
              .select('full_name')
              .eq('id', passengerId)
              .maybeSingle();

          final farePerSeat = (booking['fare_per_seat'] as num?)?.toDouble() ?? 0.0;
          final seats = (booking['seats_requested'] as int?) ?? 1;
          final fare = farePerSeat * seats;
          
          rideFare += fare;
          totalPassengers += 1;

          passengers.add(PassengerEarning(
            name: profile?['full_name'] ?? 'Passenger',
            fare: fare,
            isPaid: booking['payment_status'] == 'paid_cash' || booking['payment_status'] == 'paid_tng',
          ));
        }

        totalEarnings += rideFare;

        rideEarnings.add(RideEarning(
          from: ride['from_location'],
          to: ride['to_location'],
          time: TimezoneHelper.utcToMalaysia(DateTime.parse(ride['scheduled_time'] as String).toUtc()),
          passengers: passengers,
          totalFare: rideFare,
        ));
      }

      return ReportData(
        totalEarnings: totalEarnings,
        totalRides: rides.length,
        totalPassengers: totalPassengers,
        rideEarnings: rideEarnings,
      );
    } catch (e) {
      print('Error fetching monthly report: $e');
      return ReportData(
        totalEarnings: 0.0,
        totalRides: 0,
        totalPassengers: 0,
        rideEarnings: [],
      );
    }
  }

  Future<void> _generateMonthlyPDF(ReportData data, DateTime month) async {
    final pdf = pw.Document();
    final monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Monthly Report - ${monthNames[month.month - 1]} ${month.year}',
                style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 20),
              pw.Text('Total Earnings: RM ${data.totalEarnings.toStringAsFixed(2)}'),
              pw.Text('Total Rides: ${data.totalRides}'),
              pw.Text('Total Passengers: ${data.totalPassengers}'),
              pw.SizedBox(height: 20),
              pw.Text('Ride Summary:', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.Text('${data.rideEarnings.length} completed rides'),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }
}

// Shared widget to build report content
Widget _buildReportContent(
  BuildContext context,
  AsyncSnapshot<ReportData> snapshot,
  String emptyMessage,
  Future<void> Function() onGeneratePDF,
) {
  if (snapshot.connectionState == ConnectionState.waiting) {
    return const Center(child: CircularProgressIndicator());
  }

  if (snapshot.hasError) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text('Error: ${snapshot.error}'),
        ],
      ),
    );
  }

  final data = snapshot.data!;

  if (data.totalRides == 0) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bar_chart, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(emptyMessage),
        ],
      ),
    );
  }

  return SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Summary Cards
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                title: 'Total Earnings',
                value: 'RM ${data.totalEarnings.toStringAsFixed(2)}',
                icon: Icons.monetization_on,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                title: 'Total Rides',
                value: '${data.totalRides}',
                icon: Icons.directions_car,
                color: Colors.blue,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SummaryCard(
          title: 'Total Passengers',
          value: '${data.totalPassengers}',
          icon: Icons.people,
          color: Colors.orange,
        ),
        
        const SizedBox(height: 24),

        // Export PDF Button
        ElevatedButton.icon(
          onPressed: onGeneratePDF,
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text('Export PDF'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.all(16),
          ),
        ),

        const SizedBox(height: 24),

        // Rides List
        Text(
          'Ride Details',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        
        ...data.rideEarnings.map((ride) => _RideEarningCard(ride: ride)),
      ],
    ),
  );
}

// Shared widget to build report content with chart (for weekly)
Widget _buildReportContentWithChart(
  BuildContext context,
  AsyncSnapshot<ReportData> snapshot,
  String emptyMessage,
  Future<void> Function() onGeneratePDF,
) {
  if (snapshot.connectionState == ConnectionState.waiting) {
    return const Center(child: CircularProgressIndicator());
  }

  if (snapshot.hasError) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text('Error: ${snapshot.error}'),
        ],
      ),
    );
  }

  final data = snapshot.data!;

  if (data.totalRides == 0) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bar_chart, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(emptyMessage),
        ],
      ),
    );
  }

  return SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Summary Cards
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                title: 'Total Earnings',
                value: 'RM ${data.totalEarnings.toStringAsFixed(2)}',
                icon: Icons.monetization_on,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                title: 'Total Rides',
                value: '${data.totalRides}',
                icon: Icons.directions_car,
                color: Colors.blue,
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Chart
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Weekly Earnings',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 200,
                  child: BarChart(
                    BarChartData(
                      barGroups: [
                        for (int i = 0; i < 7; i++)
                          BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: data.dailyEarnings?[i] ?? 0.0,
                                color: Colors.green,
                                width: 20,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                              ),
                            ],
                          ),
                      ],
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                              return Text(days[value.toInt()]);
                            },
                          ),
                        ),
                        leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      gridData: const FlGridData(show: false),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 24),

        // Export PDF Button
        ElevatedButton.icon(
          onPressed: onGeneratePDF,
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text('Export PDF'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.all(16),
          ),
        ),

        const SizedBox(height: 24),

        // Rides List
        Text(
          'Ride Details (${data.rideEarnings.length})',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        
        ...data.rideEarnings.map((ride) => _RideEarningCard(ride: ride)),
      ],
    ),
  );
}

// Date Selector Widget
class _DateSelector extends StatelessWidget {
  final DateTime selectedDate;
  final Function(DateTime) onDateSelected;
  final String mode;

  const _DateSelector({
    required this.selectedDate,
    required this.onDateSelected,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () {
                final newDate = selectedDate.subtract(const Duration(days: 1));
                onDateSelected(newDate);
              },
            ),
            Expanded(
              child: Center(
                child: Text(
                  TimezoneHelper.formatMalaysiaDate(selectedDate),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () {
                final newDate = selectedDate.add(const Duration(days: 1));
                final now = TimezoneHelper.nowInMalaysia();
                if (newDate.isBefore(now) || newDate.day == now.day) {
                  onDateSelected(newDate);
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.calendar_today),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: TimezoneHelper.nowInMalaysia(),
                );
                if (picked != null) {
                  onDateSelected(picked);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

// Week Selector Widget
class _WeekSelector extends StatelessWidget {
  final DateTime selectedWeekStart;
  final Function(DateTime) onWeekSelected;

  const _WeekSelector({
    required this.selectedWeekStart,
    required this.onWeekSelected,
  });

  @override
  Widget build(BuildContext context) {
    final weekEnd = selectedWeekStart.add(const Duration(days: 6));
    
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () {
                final newDate = selectedWeekStart.subtract(const Duration(days: 7));
                onWeekSelected(newDate);
              },
            ),
            Expanded(
              child: Center(
                child: Text(
                  '${TimezoneHelper.formatMalaysiaDate(selectedWeekStart)} - ${TimezoneHelper.formatMalaysiaDate(weekEnd)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () {
                final newDate = selectedWeekStart.add(const Duration(days: 7));
                final now = TimezoneHelper.nowInMalaysia();
                if (newDate.isBefore(now) || newDate.day == now.day) {
                  onWeekSelected(newDate);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

// Month Selector Widget
class _MonthSelector extends StatelessWidget {
  final DateTime selectedMonth;
  final Function(DateTime) onMonthSelected;

  const _MonthSelector({
    required this.selectedMonth,
    required this.onMonthSelected,
  });

  @override
  Widget build(BuildContext context) {
    final monthNames = ['January', 'February', 'March', 'April', 'May', 'June',
                        'July', 'August', 'September', 'October', 'November', 'December'];
    
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () {
                final newDate = DateTime(selectedMonth.year, selectedMonth.month - 1, 1);
                onMonthSelected(newDate);
              },
            ),
            Expanded(
              child: Center(
                child: Text(
                  '${monthNames[selectedMonth.month - 1]} ${selectedMonth.year}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () {
                final newDate = DateTime(selectedMonth.year, selectedMonth.month + 1, 1);
                final now = TimezoneHelper.nowInMalaysia();
                if (newDate.isBefore(now) || (newDate.year == now.year && newDate.month == now.month)) {
                  onMonthSelected(newDate);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

// Summary Card Widget
class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Ride Earning Card Widget
class _RideEarningCard extends StatelessWidget {
  final RideEarning ride;

  const _RideEarningCard({required this.ride});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  TimezoneHelper.formatMalaysiaTime(ride.time),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
                Text(
                  'RM ${ride.totalFare.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${ride.from} → ${ride.to}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            ...ride.passengers.map((passenger) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      passenger.isPaid ? Icons.check_circle : Icons.pending,
                      size: 16,
                      color: passenger.isPaid ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(passenger.name)),
                    Text(
                      'RM ${passenger.fare.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: passenger.isPaid ? Colors.green : Colors.orange,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// Data models
class ReportData {
  final double totalEarnings;
  final int totalRides;
  final int totalPassengers;
  final List<RideEarning> rideEarnings;
  final Map<int, double>? dailyEarnings;

  ReportData({
    required this.totalEarnings,
    required this.totalRides,
    required this.totalPassengers,
    required this.rideEarnings,
    this.dailyEarnings,
  });
}

class RideEarning {
  final String from;
  final String to;
  final DateTime time;
  final List<PassengerEarning> passengers;
  final double totalFare;

  RideEarning({
    required this.from,
    required this.to,
    required this.time,
    required this.passengers,
    required this.totalFare,
  });
}

class PassengerEarning {
  final String name;
  final double fare;
  final bool isPaid;

  PassengerEarning({
    required this.name,
    required this.fare,
    required this.isPaid,
  });
}

