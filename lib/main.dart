import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'services/settings_storage.dart';
import 'theme/app_colors.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ZenMazeApp());
}

class ZenMazeApp extends StatefulWidget {
  const ZenMazeApp({super.key});

  static final darkModeNotifier = ValueNotifier<bool>(false);

  @override
  State<ZenMazeApp> createState() => _ZenMazeAppState();
}

class _ZenMazeAppState extends State<ZenMazeApp> {
  @override
  void initState() {
    super.initState();
    _loadDarkMode();
    ZenMazeApp.darkModeNotifier.addListener(_onThemeChange);
  }

  @override
  void dispose() {
    ZenMazeApp.darkModeNotifier.removeListener(_onThemeChange);
    super.dispose();
  }

  void _onThemeChange() => setState(() {});

  Future<void> _loadDarkMode() async {
    final isDark = await SettingsStorage().loadDarkMode();
    ZenMazeApp.darkModeNotifier.value = isDark;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ZenMazeApp.darkModeNotifier.value;
    return MaterialApp(
      title: 'Mazeltoe',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) {
        if (!kIsWeb) return child!;
        final colors = AppColors.of(context);
        return Container(
          color: HSLColor.fromColor(colors.background)
              .withLightness(
                (HSLColor.fromColor(colors.background).lightness - 0.06)
                    .clamp(0.0, 1.0),
              )
              .toColor(),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: child,
            ),
          ),
        );
      },
      home: const HomeScreen(),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final colors = brightness == Brightness.dark
        ? AppColors.dark
        : AppColors.light;
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'SulphurPoint',
      brightness: brightness,
      scaffoldBackgroundColor: colors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: colors.wallColor,
        brightness: brightness,
      ),
    );
  }
}
