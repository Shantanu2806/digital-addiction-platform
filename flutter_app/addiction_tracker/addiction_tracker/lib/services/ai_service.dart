import 'dart:convert';
import 'package:http/http.dart' as http;

class AiService {
  // Replace with your computer's local IP address (e.g., 'http://192.168.1.5:8000') 
  // if you are testing on a physical device. 
  // '10.0.2.2' works automatically if testing on an Android Emulator.
  // '127.0.0.1' works on a physical device if you run `adb reverse tcp:8000 tcp:8000`
  static const String _baseUrl = 'http://127.0.0.1:8000';

  Future<Map<String, dynamic>?> predictRisk({
    required String userId,
    required int dailyTotalMinutes,
    required String mostUsedApp,
    required int sessionCount,
    required int dailyLimitMinutes,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/predict_risk'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'daily_total_minutes': dailyTotalMinutes,
          'most_used_app': mostUsedApp,
          'session_count': sessionCount,
          'daily_limit_minutes': dailyLimitMinutes,
        }),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('AI Service Error: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('AI Service Network Exception: $e');
      return null;
    }
  }
}
