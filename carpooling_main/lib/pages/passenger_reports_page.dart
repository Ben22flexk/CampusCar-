import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:carpooling_main/core/utils/timezone_helper.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:fl_chart/fl_chart.dart';

/// Passenger Reports Page - Daily, Weekly, Monthly Reports
class PassengerReportsPage extends HookWidget {
  const PassengerReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Reports'),
          backgroundColor: Colors.blue,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Daily'),
              Tab(text: 'Weekly'),
              Tab(text: 'Monthly'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _DailyReportTab(),
            _WeeklyReportTab(),
            _MonthlyReportTab(),
          ],
        ),
      ),
    );
  }
}

// Data Models
class ReportData {
  final double totalSpent;
  final int totalRides;
  final List<RideExpense> rideExpenses;

  ReportData({
    required this.totalSpent,
    required this.totalRides,
    required this.rideExpenses,
  });
}

class RideExpense {
  final String from;
  final String to;
  final DateTime time;
  final double fare;
  final String driverName;
  final bool isPaid;

  RideExpense({
    required this.from,
    required this.to,
    required this.time,
    required this.fare,
    required this.driverName,
    required this.isPaid,
  });
}

/// Daily Report Tab
class _DailyReportTab extends HookConsumerWidget {
  const _DailyReportTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    final now = TimezoneHelper.nowInMalaysia();
    final selectedDate = useState(now);

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
        ),

        // Report Content
        Expanded(
          child: reportSnapshot.hasData
              ? _buildReportContent(context, reportSnapshot.data!)
              : const Center(child: CircularProgressIndicator()),
        ),
      ],
    );
  }

  static Future<ReportData> _fetchDailyReport(
    SupabaseClient supabase,
    String userId,
    DateTime date,
  ) async {
    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // Get completed rides for the day from ride_history
      final rideHistory = await supabase
          .from('ride_history')
          .select('*')
          .eq('passenger_id', userId)
          .gte('completed_at', startOfDay.toUtc().toIso8601String())
          .lt('completed_at', endOfDay.toUtc().toIso8601String());

      double totalSpent = 0.0;
      final List<RideExpense> rideExpenses = [];

      for (final history in rideHistory) {
        final driverName = history['driver_name'] as String? ?? 'Driver';
        
        final fare = (history['fare_amount'] as num?)?.toDouble() ?? 
                     (history['total_price'] as num?)?.toDouble() ?? 0.0;
        totalSpent += fare;

        final isPaid = history['payment_status'] == 'paid_cash' || 
                      history['payment_status'] == 'paid_tng';

        rideExpenses.add(RideExpense(
          from: history['from_location'] ?? 'Unknown',
          to: history['to_location'] ?? 'Unknown',
          time: DateTime.parse(history['completed_at'] as String),
          fare: fare,
          driverName: driverName,
          isPaid: isPaid,
        ));
      }

      return ReportData(
        totalSpent: totalSpent,
        totalRides: rideHistory.length,
        rideExpenses: rideExpenses,
      );
    } catch (e) {
      print('Error fetching daily report: $e');
      return ReportData(
        totalSpent: 0.0,
        totalRides: 0,
        rideExpenses: [],
      );
    }
  }

  Widget _buildReportContent(BuildContext context, ReportData data) {
    final theme = Theme.of(context);

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
                  icon: Icons.attach_money,
                  title: 'Total Spent',
                  value: 'RM ${data.totalSpent.toStringAsFixed(2)}',
                  color: Colors.red,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryCard(
                  icon: Icons.directions_car,
                  title: 'Total Rides',
                  value: '${data.totalRides}',
                  color: Colors.blue,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Export PDF Button
          ElevatedButton.icon(
            onPressed: () => _generateDailyPDF(data, context),
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Export PDF'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.all(16),
            ),
          ),

          const SizedBox(height: 24),

          // Ride Details
          Text(
            'Ride Details',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          if (data.rideExpenses.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'No rides for this day',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            )
          else
            ...data.rideExpenses.map((expense) => _RideExpenseCard(expense: expense)),
        ],
      ),
    );
  }

  Future<void> _generateDailyPDF(ReportData data, BuildContext context) async {
    final pdf = pw.Document();
    final date = DateTime.now();

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
              pw.Text('Total Spent: RM ${data.totalSpent.toStringAsFixed(2)}'),
              pw.Text('Total Rides: ${data.totalRides}'),
              pw.SizedBox(height: 20),
              pw.Text('Ride Details:', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              ...data.rideExpenses.map((expense) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('${TimezoneHelper.formatMalaysiaTime(expense.time)} - ${expense.from} → ${expense.to}'),
                  pw.Text('Driver: ${expense.driverName}'),
                  pw.Text('Fare: RM ${expense.fare.toStringAsFixed(2)} (${expense.isPaid ? "Paid" : "Pending"})'),
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

        // Report Content
        Expanded(
          child: reportSnapshot.hasData
              ? _buildWeeklyContent(context, reportSnapshot.data!, selectedWeekStart.value)
              : const Center(child: CircularProgressIndicator()),
        ),
      ],
    );
  }

  static Future<Map<int, double>> _fetchWeeklyReport(
    SupabaseClient supabase,
    String userId,
    DateTime weekStart,
  ) async {
    try {
      final weekEnd = weekStart.add(const Duration(days: 7));

      final rideHistory = await supabase
          .from('ride_history')
          .select('*')
          .eq('passenger_id', userId)
          .gte('completed_at', weekStart.toUtc().toIso8601String())
          .lt('completed_at', weekEnd.toUtc().toIso8601String());

      final Map<int, double> dailySpending = {
        1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0
      };

      for (final history in rideHistory) {
        final completedAt = DateTime.parse(history['completed_at'] as String);
        final dayOfWeek = completedAt.weekday;
        // Try fare_amount first, fallback to total_price for backwards compatibility
        final fare = (history['fare_amount'] as num?)?.toDouble() ?? 
                     (history['total_price'] as num?)?.toDouble() ?? 0.0;
        dailySpending[dayOfWeek] = (dailySpending[dayOfWeek] ?? 0) + fare;
      }

      return dailySpending;
    } catch (e) {
      print('Error fetching weekly report: $e');
      return {1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0};
    }
  }

  Widget _buildWeeklyContent(BuildContext context, Map<int, double> dailySpending, DateTime weekStart) {
    final theme = Theme.of(context);
    final totalSpent = dailySpending.values.reduce((a, b) => a + b);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Summary Card
          Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.attach_money, size: 48, color: Colors.red.shade700),
                  const SizedBox(height: 12),
                  Text('Total Spent This Week', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    'RM ${totalSpent.toStringAsFixed(2)}',
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Bar Chart
          Text(
            'Daily Spending',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          Container(
            height: 300,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.shade200,
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: (dailySpending.values.reduce((a, b) => a > b ? a : b) * 1.2).ceilToDouble(),
                barGroups: [
                  for (int i = 1; i <= 7; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: dailySpending[i] ?? 0,
                          color: Colors.blue,
                          width: 20,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ],
                    ),
                ],
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) => Text(
                        'RM${value.toInt()}',
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        const days = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                        return Text(
                          value.toInt() <= 7 ? days[value.toInt()] : '',
                          style: const TextStyle(fontSize: 12),
                        );
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 10,
                ),
                borderData: FlBorderData(show: false),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Export PDF Button
          ElevatedButton.icon(
            onPressed: () => _generateWeeklyPDF(dailySpending, totalSpent, weekStart),
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Export PDF'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.all(16),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generateWeeklyPDF(
    Map<int, double> dailySpending,
    double totalSpent,
    DateTime weekStart,
  ) async {
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
              pw.Text(
                '${TimezoneHelper.formatMalaysiaDate(weekStart)} - ${TimezoneHelper.formatMalaysiaDate(weekStart.add(const Duration(days: 6)))}',
              ),
              pw.SizedBox(height: 20),
              pw.Text('Total Spent: RM ${totalSpent.toStringAsFixed(2)}'),
              pw.SizedBox(height: 20),
              pw.Text('Daily Breakdown:', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              for (var entry in dailySpending.entries)
                pw.Text('Day ${entry.key}: RM ${entry.value.toStringAsFixed(2)}'),
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
    final selectedMonth = useState(DateTime(now.year, now.month));

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
          child: reportSnapshot.hasData
              ? _buildMonthlyContent(context, reportSnapshot.data!)
              : const Center(child: CircularProgressIndicator()),
        ),
      ],
    );
  }

  static Future<ReportData> _fetchMonthlyReport(
    SupabaseClient supabase,
    String userId,
    DateTime month,
  ) async {
    try {
      final monthStart = DateTime(month.year, month.month, 1);
      final monthEnd = DateTime(month.year, month.month + 1, 1);

      final rideHistory = await supabase
          .from('ride_history')
          .select('*')
          .eq('passenger_id', userId)
          .gte('completed_at', monthStart.toUtc().toIso8601String())
          .lt('completed_at', monthEnd.toUtc().toIso8601String());

      double totalSpent = 0.0;
      final List<RideExpense> rideExpenses = [];

      for (final history in rideHistory) {
        final driverName = history['driver_name'] as String? ?? 'Driver';
        
        final fare = (history['fare_amount'] as num?)?.toDouble() ?? 
                     (history['total_price'] as num?)?.toDouble() ?? 0.0;
        totalSpent += fare;

        final isPaid = history['payment_status'] == 'paid_cash' || 
                      history['payment_status'] == 'paid_tng';

        rideExpenses.add(RideExpense(
          from: history['from_location'] ?? 'Unknown',
          to: history['to_location'] ?? 'Unknown',
          time: DateTime.parse(history['completed_at'] as String),
          fare: fare,
          driverName: driverName,
          isPaid: isPaid,
        ));
      }

      return ReportData(
        totalSpent: totalSpent,
        totalRides: rideHistory.length,
        rideExpenses: rideExpenses,
      );
    } catch (e) {
      print('Error fetching monthly report: $e');
      return ReportData(
        totalSpent: 0.0,
        totalRides: 0,
        rideExpenses: [],
      );
    }
  }

  Widget _buildMonthlyContent(BuildContext context, ReportData data) {
    final theme = Theme.of(context);

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
                  icon: Icons.attach_money,
                  title: 'Total Spent',
                  value: 'RM ${data.totalSpent.toStringAsFixed(2)}',
                  color: Colors.red,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryCard(
                  icon: Icons.directions_car,
                  title: 'Total Rides',
                  value: '${data.totalRides}',
                  color: Colors.blue,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Export PDF Button
          ElevatedButton.icon(
            onPressed: () => _generateMonthlyPDF(data, context),
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Export PDF'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.all(16),
            ),
          ),

          const SizedBox(height: 24),

          // Ride Details
          Text(
            'Ride Details',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          if (data.rideExpenses.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'No rides for this month',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            )
          else
            ...data.rideExpenses.map((expense) => _RideExpenseCard(expense: expense)),
        ],
      ),
    );
  }

  Future<void> _generateMonthlyPDF(ReportData data, BuildContext context) async {
    final pdf = pw.Document();
    final date = DateTime.now();

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Monthly Report - ${date.year}-${date.month.toString().padLeft(2, '0')}',
                style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 20),
              pw.Text('Total Spent: RM ${data.totalSpent.toStringAsFixed(2)}'),
              pw.Text('Total Rides: ${data.totalRides}'),
              pw.SizedBox(height: 20),
              pw.Text('Ride Details:', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              ...data.rideExpenses.map((expense) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('${TimezoneHelper.formatMalaysiaTime(expense.time)} - ${expense.from} → ${expense.to}'),
                  pw.Text('Driver: ${expense.driverName}'),
                  pw.Text('Fare: RM ${expense.fare.toStringAsFixed(2)} (${expense.isPaid ? "Paid" : "Pending"})'),
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

// Helper Widgets

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;

  const _SummaryCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 36, color: color),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RideExpenseCard extends StatelessWidget {
  final RideExpense expense;

  const _RideExpenseCard({required this.expense});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                  TimezoneHelper.formatMalaysiaDateTime(TimezoneHelper.utcToMalaysia(expense.time.toUtc())),
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: expense.isPaid ? Colors.green.shade100 : Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    expense.isPaid ? 'PAID' : 'PENDING',
                    style: TextStyle(
                      color: expense.isPaid ? Colors.green.shade700 : Colors.orange.shade700,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.location_on, size: 16, color: Colors.blue),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${expense.from} → ${expense.to}',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.person, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(expense.driverName),
                  ],
                ),
                Text(
                  'RM ${expense.fare.toStringAsFixed(2)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DateSelector extends StatelessWidget {
  final DateTime selectedDate;
  final Function(DateTime) onDateSelected;

  const _DateSelector({
    required this.selectedDate,
    required this.onDateSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () {
                onDateSelected(selectedDate.subtract(const Duration(days: 1)));
              },
            ),
            Text(
              TimezoneHelper.formatMalaysiaDate(selectedDate),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () {
                onDateSelected(selectedDate.add(const Duration(days: 1)));
              },
            ),
            IconButton(
              icon: const Icon(Icons.calendar_today),
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (date != null) {
                  onDateSelected(date);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

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
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () {
                onWeekSelected(selectedWeekStart.subtract(const Duration(days: 7)));
              },
            ),
            Expanded(
              child: Text(
                '${TimezoneHelper.formatMalaysiaDate(selectedWeekStart)} - ${TimezoneHelper.formatMalaysiaDate(weekEnd)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () {
                onWeekSelected(selectedWeekStart.add(const Duration(days: 7)));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthSelector extends StatelessWidget {
  final DateTime selectedMonth;
  final Function(DateTime) onMonthSelected;

  const _MonthSelector({
    required this.selectedMonth,
    required this.onMonthSelected,
  });

  @override
  Widget build(BuildContext context) {
    final monthNames = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () {
                final newMonth = DateTime(
                  selectedMonth.year,
                  selectedMonth.month - 1,
                );
                onMonthSelected(newMonth);
              },
            ),
            Text(
              '${monthNames[selectedMonth.month - 1]} ${selectedMonth.year}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () {
                final newMonth = DateTime(
                  selectedMonth.year,
                  selectedMonth.month + 1,
                );
                onMonthSelected(newMonth);
              },
            ),
          ],
        ),
      ),
    );
  }
}

