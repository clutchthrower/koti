import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// GitHub repository ("owner/name") whose Releases feed drives the in-app
/// update flow. Leave empty to disable update checks entirely (e.g. while
/// developing, or for forks that sideload builds themselves).
///
/// To publish an update: tag a GitHub release like `v1.1.0` and attach the
/// built APK as a release asset. Tablets compare it against their own
/// version on launch and show a blocking update screen when it's newer.
// Renamed from 'clutchthrower/hemma-native' — GitHub redirects the old
// path, so tablets running pre-rename builds still find updates.
const String kUpdateRepo = 'clutchthrower/koti';

class AppUpdateInfo {
  final String version;
  final String apkUrl;
  final String notes;

  const AppUpdateInfo({
    required this.version,
    required this.apkUrl,
    required this.notes,
  });
}

/// Compares dotted version strings numerically ("1.10.0" > "1.9.2").
/// Returns >0 if [a] is newer than [b]. Non-numeric segments compare as 0.
int compareVersions(String a, String b) {
  List<int> parse(String v) => v
      .replaceFirst(RegExp(r'^[vV]'), '')
      .split('+')
      .first
      .split('.')
      .map((s) => int.tryParse(s) ?? 0)
      .toList();
  final pa = parse(a);
  final pb = parse(b);
  for (var i = 0; i < (pa.length > pb.length ? pa.length : pb.length); i++) {
    final va = i < pa.length ? pa[i] : 0;
    final vb = i < pb.length ? pb[i] : 0;
    if (va != vb) return va - vb;
  }
  return 0;
}

class AppUpdateChecker {
  final http.Client client;
  final String repo;

  AppUpdateChecker({http.Client? client, this.repo = kUpdateRepo})
      : client = client ?? http.Client();

  /// Returns update info when the repo's latest release is newer than the
  /// running app and ships an APK asset; null otherwise (including any
  /// network error — a wall tablet must never block on a failed check).
  Future<AppUpdateInfo?> check({String? currentVersion}) async {
    if (repo.isEmpty) return null;
    try {
      final current =
          currentVersion ?? (await PackageInfo.fromPlatform()).version;
      final resp = await client.get(
        Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
        headers: const {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;

      final release = jsonDecode(resp.body) as Map<String, dynamic>;
      final tag = release['tag_name'] as String? ?? '';
      if (tag.isEmpty || compareVersions(tag, current) <= 0) return null;

      final assets = (release['assets'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      final apk = assets.where((a) =>
          (a['name'] as String? ?? '').toLowerCase().endsWith('.apk'));
      if (apk.isEmpty) return null;

      return AppUpdateInfo(
        version: tag.replaceFirst(RegExp(r'^[vV]'), ''),
        apkUrl: apk.first['browser_download_url'] as String,
        notes: release['body'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}
