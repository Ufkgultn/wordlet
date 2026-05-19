import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/user_progress.dart';

class ProgressRepository {
  static const _progressKey = 'user_progress_v1';

  Future<UserProgress> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_progressKey);
    if (raw == null) return UserProgress.initial();
    return UserProgress.fromRaw(raw);
  }

  Future<void> save(UserProgress progress) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_progressKey, progress.toRaw());
  }
}
