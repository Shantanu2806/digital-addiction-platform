import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/firestore_service.dart';
import 'services/usage_tracker.dart';
import 'package:fl_chart/fl_chart.dart';

class AnalyticsTab extends StatefulWidget {
  const AnalyticsTab({super.key});

  @override
  State<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<AnalyticsTab> {
  final FirestoreService _firestoreService = FirestoreService();
  final UsageTracker _tracker = UsageTracker();
  List<Map<String, dynamic>> _weeklyData = [];
  List<Map<String, dynamic>> _topApps = [];
  bool _isLoading = true;
  int _totalWeeklyMinutes = 0;
  double _dailyAverage = 0;

  String get _userId => FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    setState(() => _isLoading = true);
    try {
      // Load weekly Firestore data
      final weekly = await _firestoreService.getWeeklyData(_userId);

      // Load real app usage breakdown
      final usage = await _tracker.getTodayUsage();
      usage.sort((a, b) => b.usage.inMinutes.compareTo(a.usage.inMinutes));
      final topApps = usage.take(10).map((app) => {
        'name': app.appName.isNotEmpty ? app.appName : app.packageName.split('.').last,
        'package': app.packageName,
        'minutes': app.usage.inMinutes,
        'seconds': app.usage.inSeconds,
      }).toList();

      int totalWeekly = 0;
      for (var d in weekly) {
        totalWeekly += ((d['total_minutes'] ?? 0) as num).toInt();
      }

      // If no weekly Firestore data, compute today's total from live tracker
      int liveTodayMinutes = await _tracker.getTotalScreenTimeForDate(DateTime.now());
      if (totalWeekly == 0 && liveTodayMinutes > 0) {
        totalWeekly = liveTodayMinutes;
      }

      setState(() {
        _weeklyData = weekly;
        _topApps = topApps;
        _totalWeeklyMinutes = totalWeekly;
        _dailyAverage = weekly.isNotEmpty ? totalWeekly / weekly.length : 0;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  String _formatTime(int minutes) {
    int h = minutes ~/ 60;
    int m = minutes % 60;
    return '${h}h ${m}m';
  }

  Color _getUsageColor(int minutes) {
    if (minutes > 120) return Colors.red;
    if (minutes > 60) return Colors.orange;
    if (minutes > 30) return Colors.amber;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Analytics', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A237E),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAnalytics,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAnalytics,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Summary Cards Row
                    Row(
                      children: [
                        _buildSummaryCard('Weekly Total', _formatTime(_totalWeeklyMinutes), Icons.calendar_today, const Color(0xFF1A237E)),
                        const SizedBox(width: 12),
                        _buildSummaryCard('Daily Avg', _formatTime(_dailyAverage.round()), Icons.trending_up, Colors.teal),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildSummaryCard('Apps Used', '${_topApps.length}', Icons.apps, Colors.purple),
                        const SizedBox(width: 12),
                        _buildSummaryCard('Days Tracked', '${_weeklyData.length}', Icons.date_range, Colors.orange),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Weekly Bar Chart
                    _buildSectionTitle('Weekly Usage Trend', Icons.bar_chart),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: _cardDecoration(),
                      child: _weeklyData.isEmpty
                          ? const SizedBox(height: 200, child: Center(child: Text('No weekly data yet. Track your usage from the Home tab!', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))))
                          : SizedBox(
                              height: 220,
                              child: BarChart(
                                BarChartData(
                                  alignment: BarChartAlignment.spaceAround,
                                  maxY: _weeklyData.fold<double>(0, (prev, d) => ((d['total_minutes'] ?? 0) / 60.0) > prev ? (d['total_minutes'] ?? 0) / 60.0 : prev) + 2,
                                  barTouchData: BarTouchData(
                                    touchTooltipData: BarTouchTooltipData(
                                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                        return BarTooltipItem('${rod.toY.toStringAsFixed(1)}h', const TextStyle(color: Colors.white, fontWeight: FontWeight.bold));
                                      },
                                    ),
                                  ),
                                  titlesData: FlTitlesData(
                                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32, getTitlesWidget: (v, m) => Text('${v.toInt()}h', style: const TextStyle(fontSize: 11, color: Colors.grey)))),
                                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (value, meta) {
                                      int i = value.toInt();
                                      if (i < _weeklyData.length) {
                                        final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                                        return Text(days[i % 7], style: const TextStyle(fontSize: 11));
                                      }
                                      return const Text('');
                                    })),
                                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  ),
                                  borderData: FlBorderData(show: false),
                                  gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 2),
                                  barGroups: _weeklyData.asMap().entries.map((entry) {
                                    double hours = (entry.value['total_minutes'] ?? 0) / 60.0;
                                    return BarChartGroupData(x: entry.key, barRods: [
                                      BarChartRodData(
                                        toY: hours,
                                        gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [
                                          hours > 6 ? Colors.red.shade300 : hours > 4 ? Colors.orange.shade300 : const Color(0xFF1A237E).withOpacity(0.6),
                                          hours > 6 ? Colors.red : hours > 4 ? Colors.orange : const Color(0xFF1A237E),
                                        ]),
                                        width: 24,
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                                      ),
                                    ]);
                                  }).toList(),
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(height: 20),

                    // App Breakdown
                    _buildSectionTitle('Today\'s App Breakdown', Icons.pie_chart),
                    const SizedBox(height: 12),
                    Container(
                      decoration: _cardDecoration(),
                      child: _topApps.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: Text('No app usage data. Tap refresh to load.', style: TextStyle(color: Colors.grey))),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _topApps.length,
                              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                              itemBuilder: (context, index) {
                                final app = _topApps[index];
                                final mins = (app['minutes'] as num).toInt();
                                final maxMins = (_topApps.first['minutes'] as num).toInt();
                                final progress = maxMins > 0 ? mins / maxMins : 0.0;

                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: _getUsageColor(mins).withOpacity(0.15),
                                    child: Text('${index + 1}', style: TextStyle(fontWeight: FontWeight.bold, color: _getUsageColor(mins))),
                                  ),
                                  title: Text(app['name'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: progress,
                                          backgroundColor: Colors.grey.shade200,
                                          valueColor: AlwaysStoppedAnimation(_getUsageColor(mins)),
                                          minHeight: 6,
                                        ),
                                      ),
                                    ],
                                  ),
                                  trailing: Text(_formatTime(mins), style: TextStyle(fontWeight: FontWeight.bold, color: _getUsageColor(mins), fontSize: 14)),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  const SizedBox(height: 2),
                  Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF1A237E), size: 22),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
      ],
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
    );
  }
}
