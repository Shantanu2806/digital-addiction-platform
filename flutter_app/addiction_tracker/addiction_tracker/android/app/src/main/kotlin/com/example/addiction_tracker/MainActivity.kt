package com.example.addiction_tracker

import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.addiction_tracker/usage"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getUsageStats") {
                val start = call.argument<Long>("start") ?: 0L
                val end = call.argument<Long>("end") ?: 0L
                
                try {
                    val stats = getUsageStats(start, end)
                    result.success(stats)
                } catch (e: Exception) {
                    result.error("ERROR", "Failed to get usage stats", e.message)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun getUsageStats(startTime: Long, endTime: Long): List<Map<String, Any>> {
        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val pm = packageManager
        
        // 1. Get all user-facing apps (apps with a launcher icon)
        val intent = Intent(Intent.ACTION_MAIN, null)
        intent.addCategory(Intent.CATEGORY_LAUNCHER)
        val launcherApps = pm.queryIntentActivities(intent, 0).map { it.activityInfo.packageName }.toSet()

        // 2. Query aggregated UsageStats. Digital Wellbeing uses this natively.
        // INTERVAL_DAILY aligns with the day boundaries perfectly.
        val usageStatsList = usageStatsManager.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, startTime, endTime)
        
        val resultList = mutableListOf<Map<String, Any>>()
        
        if (usageStatsList != null) {
            for (usageStats in usageStatsList) {
                val pkg = usageStats.packageName
                val totalTimeMs = usageStats.totalTimeInForeground
                val totalMinutes = (totalTimeMs / 60000).toInt()
                
                // Ignore apps with 0 minutes or < 10 seconds (10000 ms)
                if (totalTimeMs < 10000 || totalMinutes <= 0) continue
                
                try {
                    // 3. Strict filter: Must have a launcher icon!
                    if (!launcherApps.contains(pkg)) {
                        continue
                    }

                    // 4. Exclude Launchers themselves and specific background Google apps
                    val isExcluded = pkg == "android" || 
                                     pkg.contains("launcher") || 
                                     pkg.contains("systemui") || 
                                     pkg.contains("settings") || 
                                     pkg.contains("vending") || 
                                     pkg.contains("setupwizard") ||
                                     pkg == "com.google.android.gms" ||
                                     pkg.contains("digitalwellbeing")
                    
                    if (!isExcluded) {
                        val appInfo = pm.getApplicationInfo(pkg, 0)
                        val appName = pm.getApplicationLabel(appInfo).toString()
                        
                        resultList.add(mapOf(
                            "packageName" to pkg,
                            "appName" to appName,
                            "totalMinutes" to totalMinutes,
                            "sessionCount" to 1 // queryUsageStats doesn't provide session counts directly, we fallback to 1
                        ))
                    }
                } catch (e: PackageManager.NameNotFoundException) {
                    // App uninstalled
                }
            }
        }
        
        // Merge duplicates if queryUsageStats returns multiple instances for the same package
        val mergedMap = mutableMapOf<String, MutableMap<String, Any>>()
        for (item in resultList) {
            val pkg = item["packageName"] as String
            if (mergedMap.containsKey(pkg)) {
                val existing = mergedMap[pkg]!!
                val existingMins = existing["totalMinutes"] as Int
                val newMins = item["totalMinutes"] as Int
                existing["totalMinutes"] = existingMins + newMins
            } else {
                mergedMap[pkg] = item.toMutableMap()
            }
        }
        
        return mergedMap.values.toList()
    }
}
