import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/firestore_service.dart';
import 'services/usage_tracker.dart';
import 'services/ai_service.dart';
import 'services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final UsageTracker _tracker = UsageTracker();
  final AiService _aiService = AiService();
  int _totalMinutes = 0;
  bool _isLoading = false;
  bool _dataSaved = false;
  String _riskLevel = 'Low';
  Color _riskColor = Colors.green;
  int _riskScore = 0;
  List<Map<String, dynamic>> _weeklyData = [];
  bool _initialRiskNotificationShown = false;

  // Real stats from usage tracker
  String _mostUsedApp = '—';
  int _mostUsedMinutes = 0;
  int _sessionCount = 0;
  int _longestSessionMinutes = 0;

  String get _userId => FirebaseAuth.instance.currentUser!.uid;

  Timer? _limitCheckTimer;
  DateTime? _lastNotificationTime;

  @override
  void initState() {
    super.initState();
    _loadData();
    _startLimitCheckTimer();
  }

  @override
  void dispose() {
    _limitCheckTimer?.cancel();
    super.dispose();
  }

  void _startLimitCheckTimer() {
    // Check every 30 seconds if the user is currently crossing limits
    _limitCheckTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      final prefs = await SharedPreferences.getInstance();
      bool notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
      if (!notificationsEnabled) return;

      int limitHours = prefs.getInt('daily_limit_hours') ?? 3;
      int limitMinutes = limitHours * 60;
      int intervalMins = prefs.getInt('notification_interval_mins') ?? 2;

      // Calculate highly-precise real-time screen time (do not rely on UI cache)
      int currentMinutes = await _tracker.getTotalScreenTimeForDate(DateTime.now());

      if (currentMinutes > limitMinutes) {
        // Limit crossed! Check if interval has passed since last notification
        bool shouldNotify = false;
        if (_lastNotificationTime == null) {
          shouldNotify = true;
        } else {
          int minsSinceLast = DateTime.now().difference(_lastNotificationTime!).inMinutes;
          if (minsSinceLast >= intervalMins) {
            shouldNotify = true;
          }
        }

        if (shouldNotify) {
          await NotificationService().showLimitExceededNotification(
            limitMinutes: limitMinutes,
            currentMinutes: currentMinutes,
          );
          _lastNotificationTime = DateTime.now();
        }
      }
    });
  }

  Future<void> _syncHistoricalData() async {
    final prefs = await SharedPreferences.getInstance();
    String todayStr = DateTime.now().toIso8601String().split('T')[0];
    
    // Force sync for this session to get the highly accurate boundary data
    // if (prefs.getString('last_history_sync') == todayStr) return; 

    DateTime now = DateTime.now();
    for (int i = 1; i <= 7; i++) {
      DateTime targetDate = now.subtract(Duration(days: i));
      int minutes = await _tracker.getTotalScreenTimeForDate(targetDate);
      if (minutes > 0) {
        await _firestoreService.saveScreenTime(userId: _userId, totalMinutes: minutes, date: targetDate);
      }
    }
    await prefs.setString('last_history_sync', todayStr);
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Instantly backfill past 7 days of precision data (if not done today)
      await _syncHistoricalData();

      // 2. Fetch data
      int savedMinutes = await _firestoreService.getTodayScreenTime(_userId);
      List<Map<String, dynamic>> weekly = await _firestoreService.getWeeklyData(_userId);

      // Get real usage data for stats
      final usage = await _tracker.getTodayUsage();
      usage.sort((a, b) => b.usage.inMinutes.compareTo(a.usage.inMinutes));

      String topApp = '—';
      int topMins = 0;
      int sessions = usage.length;
      int longest = 0;

      if (usage.isNotEmpty) {
        String pkgName = usage.first.packageName;
        List<String> parts = pkgName.split('.');
        String fallbackName = parts.length > 1 
            ? parts[parts.length - (parts.last == 'android' ? 2 : 1)] 
            : pkgName;
        
        topApp = usage.first.appName.isNotEmpty && usage.first.appName != pkgName
            ? usage.first.appName 
            : fallbackName;
            
        // Capitalize the first letter
        if (topApp.isNotEmpty) {
          topApp = topApp[0].toUpperCase() + topApp.substring(1);
        }

        topMins = usage.first.usage.inMinutes;
        for (var app in usage) {
          if (app.usage.inMinutes > longest) longest = app.usage.inMinutes;
        }
      }

      // Always compute real-time usage for the UI using the precision merged interval algorithm
      int displayMinutes = await _tracker.getTotalScreenTimeForDate(DateTime.now());

      setState(() {
        _totalMinutes = displayMinutes;
        _weeklyData = weekly;
        _dataSaved = savedMinutes > 0;
        _mostUsedApp = topApp;
        _mostUsedMinutes = topMins;
        _sessionCount = sessions;
        _longestSessionMinutes = longest;
        _isLoading = false;
      });
      
      _calculateRiskFromAI(displayMinutes, topApp, sessions, showNotification: !_initialRiskNotificationShown);
      _initialRiskNotificationShown = true;
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _calculateRiskFromAI(int totalMinutes, String mostUsedApp, int sessionCount, {bool showNotification = false}) async {
    // Always fetch the user's actual screen limit to calculate dynamic risk
    final prefs = await SharedPreferences.getInstance();
    int limitHours = prefs.getInt('daily_limit_hours') ?? 3;
    int limitMinutes = limitHours * 60;

    final result = await _aiService.predictRisk(
      userId: _userId,
      dailyTotalMinutes: totalMinutes,
      mostUsedApp: mostUsedApp,
      sessionCount: sessionCount,
      dailyLimitMinutes: limitMinutes,
    );

    int score = 10;
    String level = 'Low';
    Color color = Colors.green;

    if (result != null) {
      score = result['risk_score'] ?? 10;
      level = result['risk_level'] ?? 'Low';
    } else {
      // Fallback if backend is down: Calculate risk based on the user's custom limit!
      double usagePercentage = totalMinutes / limitMinutes;
      
      if (usagePercentage >= 1.0) {
        // Crossed the limit
        score = 90;
        level = 'High';
      } else if (usagePercentage >= 0.8) {
        // 80% to 100% of limit
        score = 70;
        level = 'High';
      } else if (usagePercentage >= 0.5) {
        // 50% to 80% of limit
        score = 50;
        level = 'Medium';
      } else if (usagePercentage >= 0.25) {
        // 25% to 50% of limit
        score = 30;
        level = 'Low';
      } else {
        // Under 25%
        score = 10;
        level = 'Low';
      }
    }

    if (level == 'High') color = Colors.red;
    else if (level == 'Medium') color = Colors.orange;
    else color = Colors.green;

    if (mounted) {
      setState(() { _riskScore = score; _riskLevel = level; _riskColor = color; });
    }

    if (showNotification) {
      String recText = 'Great job! Your screen time is within healthy limits.';
      if (level == 'High') {
        recText = 'Your screen time is critically high. Consider setting strict app timers.';
      } else if (level == 'Medium') {
        recText = 'Your usage is above average. Try to take some breaks.';
      }
      
      if (result != null && result['recommendations'] != null && (result['recommendations'] as List).isNotEmpty) {
        recText = result['recommendations'][0]['desc'] ?? recText;
      }
      
      await NotificationService().showRiskAssessmentNotification(
        riskLevel: level,
        recommendation: recText,
        riskScore: score,
      );
    }
  }

  Future<void> _trackAndSave() async {
    setState(() { _isLoading = true; _dataSaved = false; });
    int minutes = await _tracker.getTotalScreenTime();
    await _firestoreService.saveScreenTime(userId: _userId, totalMinutes: minutes, date: DateTime.now());
    List<Map<String, dynamic>> weekly = await _firestoreService.getWeeklyData(_userId);

    // Reload real stats
    final usage = await _tracker.getTodayUsage();
    usage.sort((a, b) => b.usage.inMinutes.compareTo(a.usage.inMinutes));

    String topApp = '—';
    int topMins = 0;
    int sessions = usage.length;
    int longest = 0;

    if (usage.isNotEmpty) {
      topApp = usage.first.appName.isNotEmpty ? usage.first.appName : usage.first.packageName.split('.').last;
      topMins = usage.first.usage.inMinutes;
      for (var app in usage) {
        if (app.usage.inMinutes > longest) longest = app.usage.inMinutes;
      }
    }

    setState(() {
      _totalMinutes = minutes;
      _isLoading = false;
      _dataSaved = true;
      _weeklyData = weekly;
      _mostUsedApp = topApp;
      _mostUsedMinutes = topMins;
      _sessionCount = sessions;
      _longestSessionMinutes = longest;
    });
    _calculateRiskFromAI(minutes, topApp, sessions, showNotification: true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Screen time saved to Firebase!'), backgroundColor: Colors.green),
      );
    }
  }

  String _formatTime(int minutes) {
    int h = minutes ~/ 60;
    int m = minutes % 60;
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Dashboard', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A237E),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Welcome Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF1A237E), Color(0xFF0D47A1)]),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: const Color(0xFF1A237E).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.waving_hand, color: Colors.amber, size: 22),
                              const SizedBox(width: 8),
                              Text('Welcome back!', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            FirebaseAuth.instance.currentUser?.displayName ?? 
                            FirebaseAuth.instance.currentUser?.email ?? 'User',
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                                child: Text('Risk: $_riskLevel', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                              ),
                              const SizedBox(width: 8),
                               if (_dataSaved)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(color: Colors.green.withOpacity(0.3), borderRadius: BorderRadius.circular(20)),
                                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(Icons.cloud_done, color: Colors.white, size: 14),
                                    SizedBox(width: 4),
                                    Text('Synced', style: TextStyle(color: Colors.white, fontSize: 12)),
                                  ]),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Screen Time + Risk Row
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard('Today\'s Usage', _formatTime(_totalMinutes), Icons.access_time, const Color(0xFF1A237E)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStatCard('Risk Score', '$_riskScore/100', Icons.shield, _riskColor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Risk Progress
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: _cardDecoration(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Addiction Risk Score', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: _riskScore / 100,
                              backgroundColor: Colors.grey.shade200,
                              valueColor: AlwaysStoppedAnimation<Color>(_riskColor),
                              minHeight: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: const [
                              Text('Low', style: TextStyle(color: Colors.green, fontSize: 12)),
                              Text('Medium', style: TextStyle(color: Colors.orange, fontSize: 12)),
                              Text('High', style: TextStyle(color: Colors.red, fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _riskLevel == 'High' ? '⚠️ Warning! Reduce screen time immediately!'
                                : _riskLevel == 'Medium' ? '⚡ Moderate usage. Try to take breaks.'
                                : '✅ Great! Your screen time is healthy.',
                            style: TextStyle(color: _riskColor, fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Quick Stats - REAL DATA
                    const Text('Quick Stats', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1A237E))),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildQuickStat('Most Used', _mostUsedApp, Icons.star, Colors.pink),
                        const SizedBox(width: 12),
                        _buildQuickStat('Apps Used', '$_sessionCount', Icons.apps, Colors.blue),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildQuickStat('Longest', _formatTime(_longestSessionMinutes), Icons.timer, Colors.orange),
                        const SizedBox(width: 12),
                        _buildQuickStat('Top App', _formatTime(_mostUsedMinutes), Icons.trending_up, Colors.teal),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Weekly Bar Chart
                    if (_weeklyData.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: _cardDecoration(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Weekly Usage (hours)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 16),
                              SizedBox(
                                height: 200,
                                child: Builder(builder: (context) {
                                  double maxData = 8.0; // Minimum 8 hours for scale
                                  for (var entry in _weeklyData) {
                                    double hours = (entry['total_minutes'] ?? 0) / 60.0;
                                    if (hours > maxData) maxData = hours;
                                  }
                                  // Add 10% padding to the top so bars don't hit the absolute ceiling
                                  double chartMaxY = maxData * 1.1;

                                  return BarChart(
                                    BarChartData(
                                      alignment: BarChartAlignment.spaceAround,
                                      maxY: chartMaxY,
                                  barTouchData: BarTouchData(
                                    touchTooltipData: BarTouchTooltipData(
                                      getTooltipItem: (g, gI, r, rI) =>
                                          BarTooltipItem('${r.toY.toStringAsFixed(1)}h', const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                  titlesData: FlTitlesData(
                                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30)),
                                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, m) {
                                      int i = v.toInt();
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
                                  barGroups: _weeklyData.asMap().entries.map((entry) {
                                    double hours = (entry.value['total_minutes'] ?? 0) / 60.0;
                                    return BarChartGroupData(x: entry.key, barRods: [
                                      BarChartRodData(
                                        toY: hours,
                                        gradient: LinearGradient(
                                          begin: Alignment.bottomCenter, end: Alignment.topCenter,
                                          colors: [
                                            hours > 6 ? Colors.red.shade300 : hours > 4 ? Colors.orange.shade300 : const Color(0xFF1A237E).withOpacity(0.6),
                                            hours > 6 ? Colors.red : hours > 4 ? Colors.orange : const Color(0xFF1A237E),
                                          ],
                                        ),
                                        width: 20,
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                      ),
                                    ]);
                                  }).toList(),
                                ),
                                );
                              }),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),

                    // 7-Day AI Prediction
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: _cardDecoration(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(children: [
                            Icon(Icons.show_chart, color: Colors.indigo),
                            SizedBox(width: 8),
                            Text('Weekly Usage Trend', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ]),
                          const SizedBox(height: 4),
                          Text('Your actual data over the last 7 days', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 200,
                            child: LineChart(
                              LineChartData(
                                gridData: FlGridData(show: true, drawVerticalLine: false),
                                titlesData: FlTitlesData(
                                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 22,
                                    getTitlesWidget: (v, m) {
                                      int i = v.toInt();
                                      if (i >= 0 && i < _weeklyData.length) {
                                        final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                                        return Text(days[i % 7], style: const TextStyle(fontSize: 10));
                                      }
                                      return const Text('');
                                    },
                                  )),
                                  leftTitles: AxisTitles(sideTitles: SideTitles(
                                    showTitles: true, 
                                    reservedSize: 32,
                                    getTitlesWidget: (v, m) => Text('${v.toStringAsFixed(1)}h', style: const TextStyle(fontSize: 10)),
                                  )),
                                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                ),
                                borderData: FlBorderData(show: false),
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: _generatePredictionSpots(),
                                    isCurved: true,
                                    color: Colors.indigo,
                                    barWidth: 3,
                                    dotData: FlDotData(show: true),
                                    belowBarData: BarAreaData(show: true, color: Colors.indigo.withOpacity(0.1)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Update Button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _trackAndSave,
                        icon: const Icon(Icons.sync),
                        label: const Text('Sync & Save Screen Time', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A237E),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    );
  }

  List<FlSpot> _generatePredictionSpots() {
    if (_weeklyData.isEmpty) {
      double todayHours = _totalMinutes > 0 ? _totalMinutes / 60.0 : 0.0;
      return [FlSpot(0, todayHours)];
    }
    
    List<FlSpot> spots = [];
    for (int i = 0; i < _weeklyData.length; i++) {
      double hours = ((_weeklyData[i]['total_minutes'] ?? 0) as num).toDouble() / 60.0;
      spots.add(FlSpot(i.toDouble(), hours));
    }
    return spots;
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 10),
          Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildQuickStat(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: _cardDecoration(),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  const SizedBox(height: 2),
                  Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
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
