import 'package:flutter/material.dart';

class AppColors {
  final Color background;
  final Color primaryText;
  final Color secondaryText;
  final Color border;
  final Color chevronFill;
  final Color chevronIcon;
  final Color switchActive;
  final Color pauseOverlay;
  final Color settingsSheetBg;
  final Color wallColor;

  final Color ballColor;
  final Color goalColor;
  static const double wallStrokeWidth = 5.0;

  const AppColors._({
    required this.background,
    required this.primaryText,
    required this.secondaryText,
    required this.border,
    required this.chevronFill,
    required this.chevronIcon,
    required this.switchActive,
    required this.pauseOverlay,
    required this.settingsSheetBg,
    required this.wallColor,
    required this.ballColor,
    required this.goalColor,
  });

  static const light = AppColors._(
    background: Color(0xFFFFFFFF),
    primaryText: Color(0xFF48484A),
    secondaryText: Color(0xFF8F8F95),
    border: Color(0xFFBBBBBF),
    chevronFill: Color(0xFF4A4A4E),
    chevronIcon: Color(0xFFFFFFFF),
    switchActive: Color(0xFF48484A),
    pauseOverlay: Color(0xC8FFFFFF),
    settingsSheetBg: Color(0xFFFFFFFF),
    wallColor: Color(0xFFAFC3B6),
    ballColor: Color(0xFF5C4033),
    goalColor: Color(0xFF34C759),
  );

  static const dark = AppColors._(
    background: Color(0xFF1C1C1E),
    primaryText: Color(0xFFE5E5EA),
    secondaryText: Color(0xFF8E8E93),
    border: Color(0xFF3A3A3C),
    chevronFill: Color(0xFF636366),
    chevronIcon: Color(0xFFFFFFFF),
    switchActive: Color(0xFFE5E5EA),
    pauseOverlay: Color(0xC81C1C1E),
    settingsSheetBg: Color(0xFF2C2C2E),
    wallColor: Color(0xFF19A14D),
    ballColor: Color(0xFFFFFFFF),
    goalColor: Color(0xFF39FF14),
  );

  static AppColors of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }
}
