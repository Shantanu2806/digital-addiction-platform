import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:app_usage/app_usage.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _usageGranted = false;
  bool _notificationsGranted = false;
  bool _checkingPermissions = true;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    setState(() => _checkingPermissions = true);

    // Check notification permission
    var notifStatus = await Permission.notification.status;
    bool notifGranted = notifStatus.isGranted;

    // Check usage stats permission by doing a test read
    bool usageOk = false;
    try {
      DateTime end = DateTime.now();
      DateTime start = end.subtract(const Duration(minutes: 1));
      await AppUsage().getAppUsage(start, end);
      usageOk = true;
    } catch (_) {
      usageOk = false;
    }

    if (mounted) {
      setState(() {
        _notificationsGranted = notifGranted;
        _usageGranted = usageOk;
        _checkingPermissions = false;
      });
    }

    // If both already granted, auto-proceed
    if (usageOk && notifGranted) {
      await Future.delayed(const Duration(milliseconds: 500));
      widget.onComplete();
    }
  }

  Future<void> _requestUsagePermission() async {
    // Open Android's Usage Access Settings directly
    await openAppSettings();

    // Wait a moment for user to return, then re-check
    await Future.delayed(const Duration(seconds: 2));
    await _recheckUsage();
  }

  Future<void> _recheckUsage() async {
    try {
      DateTime end = DateTime.now();
      DateTime start = end.subtract(const Duration(minutes: 1));
      await AppUsage().getAppUsage(start, end);
      setState(() => _usageGranted = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Usage Access granted!'), backgroundColor: Colors.green),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Usage Access not granted. Please enable it in Settings → Apps → Usage Access.'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _requestNotificationPermission() async {
    var status = await Permission.notification.request();
    setState(() => _notificationsGranted = status.isGranted);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(status.isGranted ? '✅ Notifications enabled!' : '❌ Notifications denied'),
          backgroundColor: status.isGranted ? Colors.green : Colors.red,
        ),
      );
    }
  }

  void _finishOnboarding() {
    if (!_usageGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Usage Access permission is required to track screen time.'), backgroundColor: Colors.orange),
      );
      return;
    }
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A237E), Color(0xFF0D47A1)],
          ),
        ),
        child: SafeArea(
          child: _checkingPermissions
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      const Spacer(flex: 1),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.security, size: 60, color: Colors.white),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Setup Permissions',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'We need a few permissions to track and predict your digital habits accurately.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15, color: Colors.white.withOpacity(0.8)),
                      ),
                      const Spacer(flex: 1),

                      // Usage Access Permission Card
                      _buildPermissionCard(
                        title: 'App Usage Access',
                        description: 'Required to read your screen time data.\nTap Grant → find this app → toggle ON.',
                        icon: Icons.data_usage,
                        isGranted: _usageGranted,
                        onRequest: _requestUsagePermission,
                      ),
                      const SizedBox(height: 16),

                      // Notification Permission Card
                      _buildPermissionCard(
                        title: 'Notifications',
                        description: 'Receive alerts when usage is high and get daily wellbeing tips.',
                        icon: Icons.notifications_active,
                        isGranted: _notificationsGranted,
                        onRequest: _requestNotificationPermission,
                      ),

                      const SizedBox(height: 8),
                      // Re-check button for usage
                      if (!_usageGranted)
                        TextButton.icon(
                          onPressed: _recheckUsage,
                          icon: const Icon(Icons.refresh, color: Colors.white70, size: 18),
                          label: const Text('Already enabled? Tap to re-check', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        ),

                      const Spacer(flex: 1),

                      // Continue Button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _finishOnboarding,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF1A237E),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 4,
                          ),
                          child: const Text('Continue to Dashboard', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildPermissionCard({
    required String title,
    required String description,
    required IconData icon,
    required bool isGranted,
    required VoidCallback onRequest,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isGranted ? Colors.green.shade50 : const Color(0xFF1A237E).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: isGranted ? Colors.green : const Color(0xFF1A237E), size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text(description, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (isGranted)
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
              child: const Icon(Icons.check_circle, color: Colors.green, size: 28),
            )
          else
            ElevatedButton(
              onPressed: onRequest,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A237E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              child: const Text('Grant'),
            ),
        ],
      ),
    );
  }
}
