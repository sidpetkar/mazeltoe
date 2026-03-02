import 'package:flutter/material.dart';

import '../controllers/game_controller.dart';
import '../theme/app_colors.dart';

class MazePainter extends CustomPainter {
  final GameController controller;
  final Color wallColor;
  final Color ballColor;
  final Color goalColor;

  MazePainter({
    required this.controller,
    required this.wallColor,
    required this.ballColor,
    required this.goalColor,
  }) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    final maze = controller.maze;
    final cw = controller.cellWidth;
    final ch = controller.cellHeight;
    if (cw <= 0 || ch <= 0) return;

    final wallPaint = Paint()
      ..color = wallColor
      ..strokeWidth = AppColors.wallStrokeWidth
      ..strokeCap = StrokeCap.round;

    for (int row = 0; row < maze.rows; row++) {
      for (int col = 0; col < maze.cols; col++) {
        final cell = maze.grid[row][col];
        final x = col * cw;
        final y = row * ch;

        if (cell.rightWall && col < maze.cols - 1) {
          canvas.drawLine(Offset(x + cw, y), Offset(x + cw, y + ch), wallPaint);
        }
        if (cell.bottomWall && row < maze.rows - 1) {
          canvas.drawLine(Offset(x, y + ch), Offset(x + cw, y + ch), wallPaint);
        }
      }
    }

    final ballR = controller.ballRadius;

    final gx = (maze.cols - 1) * cw + cw / 2;
    final gy = (maze.rows - 1) * ch + ch / 2;
    canvas.drawCircle(
      Offset(gx, gy),
      ballR,
      Paint()..color = goalColor,
    );

    canvas.drawCircle(
      Offset(controller.ballX, controller.ballY),
      ballR,
      Paint()..color = ballColor,
    );
  }

  @override
  bool shouldRepaint(covariant MazePainter oldDelegate) => true;
}
