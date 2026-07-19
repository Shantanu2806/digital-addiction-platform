import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/firestore_service.dart';
import 'services/usage_tracker.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final FirestoreService _firestoreService = FirestoreService();
  bool _notificationsEnabled = true;
  int _dailyLimitHours = 3;
  int _notificationIntervalMins = 2;
  int _totalTrackedDays = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _dailyLimitHours = prefs.getInt('daily_limit_hours') ?? 3;
      _notificationIntervalMins = prefs.getInt('notification_interval_mins') ?? 2;
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;

      final uid = FirebaseAuth.instance.currentUser!.uid;
      final weekly = await _firestoreService.getWeeklyData(uid);
      setState(() {
        _totalTrackedDays = weekly.length;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.logout, color: Colors.red),
            SizedBox(width: 8),
            Text('Sign Out'),
          ],
        ),
        content: const Text('Are you sure you want to sign out? You will need to sign in again to access your data.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      // Clear onboarding flag so permissions are re-checked on next login
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_done', false);

      // Sign out from Google if applicable
      try {
        await GoogleSignIn().signOut();
      } catch (_) {}

      // Sign out from Firebase — AuthGate in main.dart will auto-redirect to LoginScreen
      await FirebaseAuth.instance.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Profile & Settings', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A237E),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Profile Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF1A237E), Color(0xFF0D47A1)]),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: const Color(0xFF1A237E).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))],
                    ),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: Colors.white.withOpacity(0.2),
                          child: Text(
                            (user?.displayName?.isNotEmpty == true ? user!.displayName!.substring(0, 1) : user?.email?.substring(0, 1) ?? 'U').toUpperCase(),
                            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(user?.displayName ?? 'User',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                        const SizedBox(height: 4),
                        Text(user?.email ?? '',
                          style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.7))),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                          child: Text('$_totalTrackedDays days tracked', style: const TextStyle(color: Colors.white, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  _buildSectionTitle('Preferences'),
                  const SizedBox(height: 8),
                  _buildSettingsCard([
                    _buildSwitchTile(Icons.notifications_active, 'Push Notifications', 'Get alerts for high usage', _notificationsEnabled, (v) async {
                      setState(() => _notificationsEnabled = v);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('notifications_enabled', v);
                    }),
                    _buildDivider(),
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.flag, color: Colors.blue, size: 22),
                      ),
                      title: const Text('Daily Screen Time Limit', style: TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: Text('$_dailyLimitHours hours per day'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, size: 22),
                            onPressed: _dailyLimitHours > 1 ? () async {
                              setState(() => _dailyLimitHours--);
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setInt('daily_limit_hours', _dailyLimitHours);
                            } : null,
                          ),
                          Text('$_dailyLimitHours', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, size: 22),
                            onPressed: _dailyLimitHours < 12 ? () async {
                              setState(() => _dailyLimitHours++);
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setInt('daily_limit_hours', _dailyLimitHours);
                            } : null,
                          ),
                        ],
                      ),
                    ),
                    _buildDivider(),
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.timer, color: Colors.red, size: 22),
                      ),
                      title: const Text('Alert Interval (Over Limit)', style: TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: Text('Notify every $_notificationIntervalMins minutes'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, size: 22),
                            onPressed: _notificationIntervalMins > 1 ? () async {
                              setState(() => _notificationIntervalMins--);
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setInt('notification_interval_mins', _notificationIntervalMins);
                            } : null,
                          ),
                          Text('$_notificationIntervalMins', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, size: 22),
                            onPressed: _notificationIntervalMins < 5 ? () async {
                              setState(() => _notificationIntervalMins++);
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setInt('notification_interval_mins', _notificationIntervalMins);
                            } : null,
                          ),
                        ],
                      ),
                    ),
                  ]),
                  const SizedBox(height: 20),

                  _buildSectionTitle('Support'),
                  const SizedBox(height: 8),
                  _buildSettingsCard([
                    _buildNavTile(Icons.contact_emergency, 'Emergency Contact', 'Set up a trusted contact', Colors.red, () {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Emergency contact feature coming soon')));
                    }),
                    _buildDivider(),
                    _buildNavTile(Icons.download, 'Export Data', 'Download your usage history', Colors.teal, () {
                      _exportData();
                    }),
                    _buildDivider(),
                    _buildNavTile(Icons.info_outline, 'About', 'Digital Wellness Platform v1.0', Colors.grey, () {
                      showAboutDialog(
                        context: context,
                        applicationName: 'Digital Wellness',
                        applicationVersion: '1.0.0',
                        applicationLegalese: '© 2026 EDI Semester Project',
                      );
                    }),
                  ]),
                  const SizedBox(height: 24),

                  // Logout Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _signOut,
                      icon: const Icon(Icons.logout),
                      label: const Text('Sign Out', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade50,
                        foregroundColor: Colors.red,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.red.shade200)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Future<void> _exportData() async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generating PDF Report...')));
    try {
      final String userId = FirebaseAuth.instance.currentUser!.uid;
      final weekly = await _firestoreService.getWeeklyData(userId);
      final usage = await UsageTracker().getTodayUsage();
      final todayMinutes = await UsageTracker().getTotalScreenTimeForDate(DateTime.now());

      final pdf = pw.Document();

      // Ensure 7 days of data
      List<double> barData = List.filled(7, 0.0);
      for (var entry in weekly) {
        var dateField = entry['date'];
        DateTime dt;
        if (dateField is Timestamp) {
          dt = dateField.toDate();
        } else {
          dt = DateTime.parse(dateField.toString());
        }
        int daysAgo = DateTime.now().difference(dt).inDays;
        if (daysAgo >= 0 && daysAgo < 7) {
          barData[6 - daysAgo] = (entry['total_minutes'] ?? 0) / 60.0;
        }
      }
      barData[6] = todayMinutes / 60.0; // Override today with live data

      double maxData = 8.0;
      for (double v in barData) {
        if (v > maxData) maxData = v;
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return [
              pw.Header(level: 0, child: pw.Text('Digital Wellness Report', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold))),
              pw.SizedBox(height: 20),
              
              pw.Text('Weekly Usage Overview (Hours)', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 20),
              
              // Custom Bar Graph
              pw.Container(
                height: 200,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10))
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                  children: List.generate(7, (i) {
                    double height = (barData[i] / maxData) * 150;
                    return pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.end,
                      children: [
                        pw.Text('${barData[i].toStringAsFixed(1)}h', style: const pw.TextStyle(fontSize: 10)),
                        pw.SizedBox(height: 5),
                        pw.Container(width: 20, height: height, color: PdfColors.blue400),
                        pw.SizedBox(height: 5),
                        pw.Text(['M','T','W','T','F','S','S'][i], style: const pw.TextStyle(fontSize: 12)),
                      ]
                    );
                  }),
                )
              ),
              pw.SizedBox(height: 30),
              
              pw.Text('Today\'s Detailed App Usage', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.TableHelper.fromTextArray(
                headers: ['App Name', 'Usage Time'],
                data: usage.map((u) {
                  String name = u.appName.isEmpty ? u.packageName : u.appName;
                  return [name, '${(u.usage.inMinutes / 60).floor()}h ${u.usage.inMinutes % 60}m'];
                }).toList(),
              ),
              
              pw.SizedBox(height: 30),
              pw.Text('7-Day History', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.TableHelper.fromTextArray(
                headers: ['Date', 'Screen Time'],
                data: weekly.map((w) {
                  var dateField = w['date'];
                  String dateStr = '';
                  if (dateField is Timestamp) {
                    dateStr = dateField.toDate().toIso8601String().split('T')[0];
                  } else {
                    dateStr = dateField.toString().split('T')[0];
                  }
                  return [dateStr, '${((w['total_minutes'] ?? 0) / 60).floor()}h ${(w['total_minutes'] ?? 0) % 60}m'];
                }).toList(),
              ),
            ];
          },
        ),
      );

      await Printing.sharePdf(bytes: await pdf.save(), filename: 'screen_time_report.pdf');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error generating PDF: $e')));
    }
  }

  Widget _buildSectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade600, letterSpacing: 0.5)),
    );
  }

  Widget _buildSettingsCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSwitchTile(IconData icon, String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.purple.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: Colors.purple, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      trailing: Switch.adaptive(value: value, onChanged: onChanged, activeColor: const Color(0xFF1A237E)),
    );
  }

  Widget _buildNavTile(IconData icon, String title, String subtitle, Color color, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }

  Widget _buildDivider() => Divider(height: 1, indent: 60, color: Colors.grey.shade200);
}
