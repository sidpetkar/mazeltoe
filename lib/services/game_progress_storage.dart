import 'package:shared_preferences/shared_preferences.dart';

import '../models/maze_mode.dart';

class GameProgressStorage {
  String _levelKey(MazeMode mode) => 'current_level_${mode.storageKey}';
  String _highLevelKey(MazeMode mode) => 'high_level_${mode.storageKey}';

  Future<(int level, int highLevel)> load(MazeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    final level = prefs.getInt(_levelKey(mode)) ?? 1;
    final high = prefs.getInt(_highLevelKey(mode)) ?? 1;
    return (level < 1 ? 1 : level, high < 1 ? 1 : high);
  }

  Future<void> save({
    required MazeMode mode,
    required int level,
    required int highLevel,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_levelKey(mode), level);
    await prefs.setInt(_highLevelKey(mode), highLevel);
  }

  Future<void> resetToNewGame(MazeMode mode) async {
    await save(mode: mode, level: 1, highLevel: 1);
  }
}
