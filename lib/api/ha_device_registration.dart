import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Registers this tablet with Home Assistant's `mobile_app` integration —
/// the same mechanism the official companion apps use. After this, the
/// tablet shows up in HA's Settings → Devices & services as a real device
/// (assignable to an Area, targetable by automations), and the returned
/// webhook is the channel future features (sensors, voice) will build on.
class HaDeviceRegistration {
  /// Returns the webhook id on success, null on failure (e.g. the
  /// mobile_app integration is disabled — non-fatal, dashboard still works).
  static Future<String?> register({
    required String baseUrl,
    required String accessToken,
    required String deviceId,
  }) async {
    final resp = await http
        .post(
          Uri.parse('$baseUrl/api/mobile_app/registrations'),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'device_id': deviceId,
            'app_id': 'com.hemma.hemma_native',
            'app_name': 'Koti',
            'app_version': '1.0.0',
            'device_name': 'Koti Tablet',
            'manufacturer': 'Koti',
            'model': 'Wall Dashboard',
            'os_name': Platform.operatingSystem,
            'os_version': Platform.operatingSystemVersion,
            'supports_encryption': false,
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode == 200 || resp.statusCode == 201) {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return body['webhook_id'] as String?;
    }
    return null;
  }
}
