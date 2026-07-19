import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/firestore_service.dart';
import 'services/usage_tracker.dart';
import 'services/ai_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class InsightsTab extends StatefulWidget {
  const InsightsTab({super.key});

  @override
  State<InsightsTab> createState() => _InsightsTabState();
}

class _InsightsTabState extends State<InsightsTab> {
  final FirestoreService _firestoreService = FirestoreService();
  final UsageTracker _tracker = UsageTracker();
  final AiService _aiService = AiService();
  int _todayMinutes = 0;
  int _riskScore = 0;
  String _topApp = 'Unknown';
  int _topAppMinutes = 0;
  int _sessionCount = 0;
  bool _isLoading = true;
  List<Map<String, dynamic>> _weeklyData = [];
  List<Map<String, dynamic>> _aiRecommendations = [];

  String get _userId => FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    _loadInsights();
  }

  Future<void> _loadInsights() async {
    setState(() => _isLoading = true);
    try {
      int savedMins = await _firestoreService.getTodayScreenTime(_userId);
      final weekly = await _firestoreService.getWeeklyData(_userId);
      final usage = await _tracker.getTodayUsage();
      usage.sort((a, b) => b.usage.inMinutes.compareTo(a.usage.inMinutes));

      String topName = 'None';
      int topMins = 0;
      if (usage.isNotEmpty) {
        topName = usage.first.appName.isNotEmpty ? usage.first.appName : usage.first.packageName.split('.').last;
        topMins = usage.first.usage.inMinutes;
      }

      // Always fetch precise live screen time natively
      int displayMins = await _tracker.getTotalScreenTimeForDate(DateTime.now());

      int sessionCount = usage.length;

      final prefs = await SharedPreferences.getInstance();
      int limitHours = prefs.getInt('daily_limit_hours') ?? 3;
      int limitMinutes = limitHours * 60;

      // Fetch dynamic AI Recommendations
      final aiResult = await _aiService.predictRisk(
        userId: _userId,
        dailyTotalMinutes: displayMins,
        mostUsedApp: topName,
        sessionCount: sessionCount,
        dailyLimitMinutes: limitMinutes,
      );

      int score = 10;
      if (aiResult != null) {
        score = aiResult['risk_score'] ?? 10;
      } else {
        // Fallback if backend is down: Calculate risk based on the user's custom limit!
        double usagePercentage = displayMins / limitMinutes;
        if (usagePercentage >= 1.0) score = 90;
        else if (usagePercentage >= 0.8) score = 70;
        else if (usagePercentage >= 0.5) score = 50;
        else if (usagePercentage >= 0.25) score = 30;
        else score = 10;
      }
      List<dynamic> backendRecs = aiResult?['recommendations'] ?? [];

      setState(() {
        _todayMinutes = displayMins;
        _riskScore = score;
        _topApp = topName;
        _topAppMinutes = topMins;
        _sessionCount = sessionCount;
        _weeklyData = weekly;
        _aiRecommendations = List<Map<String, dynamic>>.from(backendRecs);
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

  List<Map<String, dynamic>> _getRecommendations() {
    // If backend provided recommendations, map them to UI elements
    if (_aiRecommendations.isNotEmpty) {
      return _aiRecommendations.map((rec) {
        String title = rec['title'] ?? 'Recommendation';
        IconData icon = Icons.lightbulb_outline;
        Color color = Colors.blue;

        if (title.contains('Risk Alert') || title.contains('Detox')) {
          icon = Icons.warning_amber; color = Colors.red;
        } else if (title.contains('Moderate') || title.contains('Limits')) {
          icon = Icons.schedule; color = Colors.orange;
        } else if (title.contains('Healthy') || title.contains('Keep It Up')) {
          icon = Icons.check_circle; color = Colors.green;
        } else if (title.contains('Reduce')) {
          icon = Icons.app_blocking; color = Colors.purple;
        } else if (title.contains('Checking')) {
          icon = Icons.touch_app; color = Colors.amber.shade700;
        } else if (title.contains('Night Mode')) {
          icon = Icons.nightlight; color = Colors.indigo;
        }

        return {
          'icon': icon,
          'color': color,
          'title': title,
          'desc': rec['desc'] ?? '',
        };
      }).toList();
    }

    // Offline Fallback
    List<Map<String, dynamic>> recs = [];
    if (_riskScore >= 70) {
      recs.add({'icon': Icons.warning_amber, 'color': Colors.red, 'title': 'High Risk Alert', 'desc': 'Your screen time is critically high. Consider setting app timers.'});
    } else {
      recs.add({'icon': Icons.check_circle, 'color': Colors.green, 'title': 'Healthy Usage!', 'desc': 'Great job! Your screen time is within healthy limits.'});
    }
    return recs;
  }

  List<Map<String, dynamic>> _getPatternInsights() {
    List<Map<String, dynamic>> patterns = [];

    if (_weeklyData.length >= 2) {
      int lastMins = ((_weeklyData.last['total_minutes'] ?? 0) as num).toInt();
      int prevMins = ((_weeklyData[_weeklyData.length - 2]['total_minutes'] ?? 0) as num).toInt();
      int diff = lastMins - prevMins;

      if (diff > 30) {
        patterns.add({'icon': Icons.trending_up, 'color': Colors.red, 'text': 'Usage increased by ${_formatTime(diff.abs())} compared to yesterday'});
      } else if (diff < -30) {
        patterns.add({'icon': Icons.trending_down, 'color': Colors.green, 'text': 'Usage decreased by ${_formatTime(diff.abs())} compared to yesterday. Well done!'});
      } else {
        patterns.add({'icon': Icons.trending_flat, 'color': Colors.blue, 'text': 'Usage is stable compared to yesterday'});
      }
    }

    if (_todayMinutes > 0) {
      patterns.add({'icon': Icons.access_time, 'color': Colors.deepPurple, 'text': 'Total screen time today: ${_formatTime(_todayMinutes)}'});
    }
    if (_topApp != 'None') {
      patterns.add({'icon': Icons.star, 'color': Colors.orange, 'text': 'Most used app: $_topApp (${_formatTime(_topAppMinutes)})'});
    }

    return patterns;
  }

  @override
  Widget build(BuildContext context) {
    final recs = _getRecommendations();
    final patterns = _getPatternInsights();

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Insights', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A237E),
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadInsights),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadInsights,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Risk Summary Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          _riskScore >= 70 ? Colors.red.shade700 : _riskScore >= 40 ? Colors.orange.shade700 : Colors.green.shade700,
                          _riskScore >= 70 ? Colors.red.shade400 : _riskScore >= 40 ? Colors.orange.shade400 : Colors.green.shade400,
                        ]),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: (_riskScore >= 70 ? Colors.red : _riskScore >= 40 ? Colors.orange : Colors.green).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))],
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(14)),
                                child: Icon(_riskScore >= 70 ? Icons.warning : _riskScore >= 40 ? Icons.info : Icons.check_circle, color: Colors.white, size: 28),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('AI Risk Assessment', style: TextStyle(color: Colors.white70, fontSize: 13)),
                                    const SizedBox(height: 4),
                                    Text(
                                      _riskScore >= 70 ? 'High Risk - Action Required' : _riskScore >= 40 ? 'Moderate Risk - Monitor' : 'Low Risk - Healthy',
                                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                              Text('$_riskScore', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: _riskScore / 100,
                              backgroundColor: Colors.white.withOpacity(0.2),
                              valueColor: const AlwaysStoppedAnimation(Colors.white),
                              minHeight: 8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Pattern Insights
                    if (patterns.isNotEmpty) ...[
                      _buildSectionTitle('Usage Patterns', Icons.insights),
                      const SizedBox(height: 12),
                      ...patterns.map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: (p['color'] as Color).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                                child: Icon(p['icon'] as IconData, color: p['color'] as Color, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Text(p['text'] as String, style: const TextStyle(fontSize: 14))),
                            ],
                          ),
                        ),
                      )),
                      const SizedBox(height: 20),
                    ],

                    // AI Recommendations
                    _buildSectionTitle('AI Recommendations', Icons.auto_awesome),
                    const SizedBox(height: 12),
                    ...recs.map((rec) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: (rec['color'] as Color).withOpacity(0.2)),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: (rec['color'] as Color).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                              child: Icon(rec['icon'] as IconData, color: rec['color'] as Color, size: 24),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(rec['title'] as String, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: rec['color'] as Color)),
                                  const SizedBox(height: 4),
                                  Text(rec['desc'] as String, style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )),
                    const SizedBox(height: 20),

                    // Wellbeing Tips
                    _buildSectionTitle('Digital Wellbeing Tips', Icons.spa),
                    const SizedBox(height: 12),
                    _buildTipCard('🧘', 'Mindful Usage', 'Before opening any app, ask yourself: "Do I need this right now?" This simple pause can reduce unnecessary screen time by 40%.'),
                    _buildTipCard('📵', 'Phone-Free Zones', 'Designate your bedroom and dining table as phone-free zones. This improves sleep quality and family relationships.'),
                    _buildTipCard('🔔', 'Notification Diet', 'Turn off non-essential notifications. Each notification interrupts focus for an average of 23 minutes.'),
                    _buildTipCard('📚', 'Replace & Reward', 'Replace 30 minutes of social media with reading or exercise. Reward yourself weekly for meeting goals.'),
                    const SizedBox(height: 20),
                  ],
                ),
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

  Widget _buildTipCard(String emoji, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(desc, style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
