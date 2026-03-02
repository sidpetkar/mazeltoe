import 'dart:math';

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/maze_mode.dart';
import '../services/game_progress_storage.dart';
import '../services/motion_permission.dart';
import '../services/settings_storage.dart';
import '../theme/app_colors.dart';
import 'circular_game_screen.dart';
import 'game_screen.dart';
import 'sliding_game_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GameProgressStorage _storage = GameProgressStorage();
  final SettingsStorage _settings = SettingsStorage();
  bool _loading = true;
  MazeMode _selectedMode = MazeMode.box;
  bool _vibrationEnabled = true;
  bool _timerEnabled = true;
  bool _darkMode = false;
  final Map<MazeMode, (int level, int highLevel)> _progress = {
    MazeMode.box: (1, 1),
    MazeMode.circular: (1, 1),
    MazeMode.circularRotating: (21, 21),
    MazeMode.slidingBox: (1, 1),
  };

  static const double _pagePadding = 28.0;
  static const double _bottomPadding = 40.0;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final box = await _storage.load(MazeMode.box);
    final circular = await _storage.load(MazeMode.circular);
    final rotating = await _storage.load(MazeMode.circularRotating);
    final sliding = await _storage.load(MazeMode.slidingBox);
    final vib = await _settings.loadVibration();
    final timer = await _settings.loadTimer();
    final dark = await _settings.loadDarkMode();
    if (!mounted) return;
    setState(() {
      _progress[MazeMode.box] = box;
      _progress[MazeMode.circular] = circular;
      _progress[MazeMode.circularRotating] = (
        max(rotating.$1, MazeMode.circularRotating.startLevel),
        max(rotating.$2, MazeMode.circularRotating.startLevel),
      );
      _progress[MazeMode.slidingBox] = sliding;
      _vibrationEnabled = vib;
      _timerEnabled = timer;
      _darkMode = dark;
      _loading = false;
    });
  }

  (int level, int highLevel) get _currentProgress => _progress[_selectedMode]!;

  static const _modes = MazeMode.values;

  void _goLeft() {
    setState(() {
      final idx = _modes.indexOf(_selectedMode);
      _selectedMode = _modes[(idx - 1 + _modes.length) % _modes.length];
    });
  }

  void _goRight() {
    setState(() {
      final idx = _modes.indexOf(_selectedMode);
      _selectedMode = _modes[(idx + 1) % _modes.length];
    });
  }

  Future<void> _openGame({required bool startNew}) async {
    await requestMotionPermission();
    final current = _currentProgress;
    final startLvl = _selectedMode.startLevel;
    var level = current.$1;
    var high = current.$2;

    if (startNew) {
      await _storage.save(
        mode: _selectedMode,
        level: startLvl,
        highLevel: startLvl,
      );
      level = startLvl;
      high = startLvl;
      _progress[_selectedMode] = (startLvl, startLvl);
    }

    if (!mounted) return;

    void onProgress(int lvl, int hi) async {
      await _storage.save(mode: _selectedMode, level: lvl, highLevel: hi);
      if (!mounted) return;
      setState(() {
        _progress[_selectedMode] = (lvl, hi);
      });
    }

    final Widget screen;
    switch (_selectedMode) {
      case MazeMode.box:
        screen = GameScreen(
          initialLevel: level,
          initialHighLevel: high,
          timerEnabled: _timerEnabled,
          vibrationEnabled: _vibrationEnabled,
          onProgressChanged: onProgress,
        );
      case MazeMode.slidingBox:
        screen = SlidingGameScreen(
          initialLevel: level,
          initialHighLevel: high,
          timerEnabled: _timerEnabled,
          vibrationEnabled: _vibrationEnabled,
          onProgressChanged: onProgress,
        );
      case MazeMode.circular:
      case MazeMode.circularRotating:
        screen = CircularGameScreen(
          initialLevel: level,
          initialHighLevel: high,
          timerEnabled: _timerEnabled,
          vibrationEnabled: _vibrationEnabled,
          onProgressChanged: onProgress,
        );
    }

    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    await _loadAll();
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.of(context).settingsSheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setModalState) {
          final c = AppColors.of(context);
          return Padding(
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Settings',
                  style: TextStyle(
                    fontFamily: 'SulphurPoint',
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: c.primaryText,
                  ),
                ),
                const SizedBox(height: 24),
                _settingsRow(
                  label: 'VIBRATION',
                  value: _vibrationEnabled,
                  colors: c,
                  onChanged: (v) {
                    setModalState(() => _vibrationEnabled = v);
                    setState(() {});
                    _settings.saveVibration(v);
                  },
                ),
                const SizedBox(height: 12),
                _settingsRow(
                  label: 'TIMER',
                  value: _timerEnabled,
                  colors: c,
                  onChanged: (v) {
                    setModalState(() => _timerEnabled = v);
                    setState(() {});
                    _settings.saveTimer(v);
                  },
                ),
                const SizedBox(height: 12),
                _settingsRow(
                  label: 'DARK MODE',
                  value: _darkMode,
                  colors: c,
                  onChanged: (v) {
                    _darkMode = v;
                    setModalState(() {});
                    setState(() {});
                    _settings.saveDarkMode(v);
                    ZenMazeApp.darkModeNotifier.value = v;
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _settingsRow({
    required String label,
    required bool value,
    required AppColors colors,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'SulphurPoint',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colors.primaryText,
          ),
        ),
        Switch.adaptive(
          value: value,
          activeColor: colors.switchActive,
          onChanged: onChanged,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: _pagePadding),
                child: Column(
                  children: [
                    _buildSettingsButton(c),
                    const Spacer(flex: 3),
                    _buildLogoAndTitle(c),
                    const Spacer(flex: 2),
                    _buildModeCarousel(c),
                    const Spacer(flex: 5),
                    _buildBottomBar(c),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildSettingsButton(AppColors c) {
    return Padding(
      padding: const EdgeInsets.only(top: _bottomPadding),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: _showSettings,
            child: Icon(
              Icons.settings_outlined,
              size: 26,
              color: c.secondaryText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoAndTitle(AppColors c) {
    return Column(
      children: [
        Image.asset(
          'assets/logo.png',
          width: 130,
          height: 130,
        ),
        const SizedBox(height: 10),
        Text(
          'MAZELTOE',
          style: TextStyle(
            fontFamily: 'SulphurPoint',
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: c.wallColor,
          ),
        ),
      ],
    );
  }

  Widget _buildModeCarousel(AppColors c) {
    return Column(
      children: [
        GestureDetector(
          onHorizontalDragEnd: (details) {
            final v = details.primaryVelocity ?? 0;
            if (v < 0) {
              _goRight();
            } else if (v > 0) {
              _goLeft();
            }
          },
          child: Row(
            children: [
              GestureDetector(
                onTap: _goLeft,
                child: Icon(
                  Icons.arrow_left,
                  size: 36,
                  color: c.secondaryText,
                ),
              ),
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _selectedMode.title.toUpperCase(),
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: 'SulphurPoint',
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: c.primaryText,
                      ),
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: _goRight,
                child: Icon(
                  Icons.arrow_right,
                  size: 36,
                  color: c.secondaryText,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: _modes.map((mode) {
            final active = mode == _selectedMode;
            return Container(
              width: active ? 8 : 6,
              height: active ? 8 : 6,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? c.primaryText : c.border,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildBottomBar(AppColors c) {
    final hasProgress = _currentProgress.$1 > _selectedMode.startLevel;
    return Padding(
      padding: EdgeInsets.only(bottom: _bottomPadding),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => _openGame(startNew: true),
            child: Text(
              'START',
              style: TextStyle(
                fontFamily: 'SulphurPoint',
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: c.primaryText,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _openGame(startNew: false),
            child: Text(
              hasProgress ? 'RESUME L${_currentProgress.$1}' : 'RESUME',
              style: TextStyle(
                fontFamily: 'SulphurPoint',
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: c.primaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
