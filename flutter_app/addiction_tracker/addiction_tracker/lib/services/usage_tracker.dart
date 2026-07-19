import 'package:app_usage/app_usage.dart' as au;
import 'package:usage_stats/usage_stats.dart';
class AppUsageInfo {
  final String packageName;
  final String appName;
  final Duration usage;
  final int sessionCount;

  AppUsageInfo({
    required this.packageName,
    required this.appName,
    required this.usage,
    this.sessionCount = 1,
  });
}

class UsageTracker {
  Future<List<AppUsageInfo>> getTodayUsage() async {
    return getUsageForDate(DateTime.now());
  }

  Future<List<AppUsageInfo>> getUsageForDate(DateTime date) async {
    DateTime startDate = DateTime(date.year, date.month, date.day);
    DateTime now = DateTime.now();
    DateTime endDate = DateTime(date.year, date.month, date.day, 23, 59, 59);
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      endDate = now;
    }

    try {
      List<au.AppUsageInfo> infoList = await au.AppUsage().getAppUsage(startDate, endDate);
      List<AppUsageInfo> resultList = [];
      
      for (var info in infoList) {
        String pkg = info.packageName;
        String pkgLower = pkg.toLowerCase();
        
        bool isSystemApp = pkgLower == 'android' ||
            pkgLower.contains('launcher') || 
            pkgLower.contains('nexuslauncher') ||
            pkgLower.contains('trebuchet') ||
            pkgLower.contains('miui') ||
            pkgLower.contains('digitalwellbeing') ||
            pkgLower.contains('gms') || // Google Play Services
            pkgLower.contains('vending') || // Play Store
            pkgLower.contains('settings') || // Android Settings
            pkgLower.contains('permission') || // Permission Controllers
            pkgLower.contains('systemui') ||
            pkgLower.contains('providers') ||
            pkgLower.contains('server') ||
            pkgLower.contains('xiaomi.discover') ||
            pkgLower.contains('xiaomi.mipicks') ||
            pkgLower.contains('com.google.android.ext.services') ||
            pkgLower.contains('installer') ||
            pkgLower.contains('com.example.addiction_tracker') || // Exclude our own background tracker!
            pkgLower.contains('spotify') || // Exclude music background services
            pkgLower.contains('music');

        if (isSystemApp) continue;
        if (info.usage.inMinutes == 0) continue;

        Map<String, String> commonApps = {
          'com.whatsapp': 'WhatsApp',
          'com.instagram.android': 'Instagram',
          'com.google.android.youtube': 'YouTube',
          'com.zhiliaoapp.musically': 'TikTok',
          'com.facebook.katana': 'Facebook',
          'com.snapchat.android': 'Snapchat',
          'com.twitter.android': 'X (Twitter)',
          'org.telegram.messenger': 'Telegram',
          'com.netflix.mediaclient': 'Netflix',
          'com.google.android.apps.maps': 'Maps',
          'com.android.chrome': 'Chrome',
          'com.spotify.music': 'Spotify',
        };

        String appName = commonApps[pkg] ?? info.appName;
        if (appName.isEmpty || appName == pkg) {
          List<String> parts = pkg.split('.');
          String fallback = parts.last;
          if (fallback.toLowerCase() == 'android' && parts.length > 1) {
            fallback = parts[parts.length - 2];
          }
          appName = fallback[0].toUpperCase() + fallback.substring(1);
        }

        resultList.add(AppUsageInfo(
          packageName: pkg,
          appName: appName,
          usage: info.usage,
          sessionCount: 1, // AppUsage doesn't natively expose sessions, default to 1
        ));
      }
      return resultList;
    } catch (e) {
      print('Error getting usage stats: $e');
      return [];
    }
  }

  Future<int> getTotalScreenTime() async {
    return getTotalScreenTimeForDate(DateTime.now());
  }

  Future<int> getTotalScreenTimeForDate(DateTime date) async {
    // Rely entirely on the natively aggregated AppUsage stats, which perfectly match Digital Wellbeing.
    List<AppUsageInfo> usage = await getUsageForDate(date);
    int totalMinutes = 0;
    
    for (var app in usage) {
      totalMinutes += app.usage.inMinutes;
    }
    
    // Cap at 24 hours to absolutely prevent any layout breakage from OS bugs
    if (totalMinutes > 1440) totalMinutes = 1440;
    
    return totalMinutes;
  }
}
