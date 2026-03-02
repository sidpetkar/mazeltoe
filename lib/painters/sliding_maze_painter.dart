import 'package:flutter/material.dart';

import '../controllers/sliding_game_controller.dart';
import '../theme/app_colors.dart';

class SlidingMazePainter extends CustomPainter {
  final SlidingGameController controller;
  final Color wallColor;
  final Color ballColor;
  final Color goalColor;

  SlidingMazePainter({
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

    final mw = controller.mazeWidth;
    final mh = controller.mazeHeight;

    final wallPaint = Paint()
      ..color = wallColor
      ..strokeWidth = AppColors.wallStrokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, mw, mh));

    // -----------------------------------------------------------------------
    // Row-owned vertical walls: only right walls are row-shifted.
    // This keeps horizontal complexity under control while preserving motion.
    // -----------------------------------------------------------------------
    for (int row = 0; row < maze.rows; row++) {
      final rowOff = controller.rowVisualPixelOffset(row);
      final y1 = row * ch;
      final y2 = y1 + ch;

      for (int origCol = 0; origCol < maze.cols; origCol++) {
        final cell = maze.grid[row][origCol];
        final cellX = origCol * cw + rowOff;

        // Right wall (vertical, within-row)
        if (origCol < maze.cols - 1 && cell.rightWall) {
          _drawVWallWrapped(canvas, cellX + cw, y1, y2, mw, wallPaint);
        }
      }

      // Wrap-seam vertical wall (maze boundary wraps around)
      final seam = rowOff % mw;
      if (seam.abs() > 0.5 && (mw - seam).abs() > 0.5) {
        canvas.drawLine(Offset(seam, y1), Offset(seam, y2), wallPaint);
      }
    }

    // -----------------------------------------------------------------------
    // Column-owned horizontal walls: only bottom walls are column-shifted.
    // -----------------------------------------------------------------------
    for (int col = 0; col < maze.cols; col++) {
      final colOff = controller.colVisualPixelOffset(col);
      final x1 = col * cw;
      final x2 = x1 + cw;

      for (int origRow = 0; origRow < maze.rows; origRow++) {
        final cell = maze.grid[origRow][col];
        final cellY = origRow * ch + colOff;

        // Bottom wall (horizontal, within-column)
        if (origRow < maze.rows - 1 && cell.bottomWall) {
          _drawHWallWrappedV(canvas, x1, cellY + ch, cw, mh, wallPaint);
        }
      }

      // Wrap-seam horizontal wall (maze boundary wraps around)
      final seam = colOff % mh;
      if (seam.abs() > 0.5 && (mh - seam).abs() > 0.5) {
        canvas.drawLine(Offset(x1, seam), Offset(x2, seam), wallPaint);
      }
    }

    canvas.restore();

    // Goal
    final ballR = controller.ballRadius;
    canvas.drawCircle(
      Offset(controller.goalX, controller.goalY),
      ballR,
      Paint()..color = goalColor,
    );

    // Ball
    canvas.drawCircle(
      Offset(controller.ballX, controller.ballY),
      ballR,
      Paint()..color = ballColor,
    );
  }

  // Vertical wall line, wrapped horizontally within [0, totalW].
  void _drawVWallWrapped(
    Canvas canvas, double x, double y1, double y2, double totalW, Paint paint,
  ) {
    var wx = x % totalW;
    if (wx < 0) wx += totalW;
    if (wx < 1 || (totalW - wx) < 1) return;
    canvas.drawLine(Offset(wx, y1), Offset(wx, y2), paint);
  }

  // Horizontal wall segment, wrapped vertically within [0, totalH].
  void _drawHWallWrappedV(
    Canvas canvas, double x, double y, double segW, double totalH, Paint paint,
  ) {
    var wy = y % totalH;
    if (wy < 0) wy += totalH;
    if (wy < 1 || (totalH - wy) < 1) return;
    canvas.drawLine(Offset(x, wy), Offset(x + segW, wy), paint);
  }

  @override
  bool shouldRepaint(covariant SlidingMazePainter oldDelegate) => true;
}
