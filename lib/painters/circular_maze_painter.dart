import 'dart:math';

import 'package:flutter/material.dart';

import '../controllers/circular_game_controller.dart';
import '../theme/app_colors.dart';

class CircularMazePainter extends CustomPainter {
  final CircularGameController controller;
  final Color wallColor;
  final Color ballColor;
  final Color goalColor;

  CircularMazePainter({
    required this.controller,
    required this.wallColor,
    required this.ballColor,
    required this.goalColor,
  }) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    final maze = controller.maze;
    if (controller.ringWidth <= 0) return;

    final center = Offset(controller.centerX, controller.centerY);

    final wallPaint = Paint()
      ..color = wallColor
      ..strokeWidth = AppColors.wallStrokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (int ring = 0; ring < maze.rings; ring++) {
      final sectorCount = maze.sectorsPerRing[ring];
      final sa = controller.sectorAngleForRing(ring);
      final rotOff = controller.ringRotationOffsets[ring];

      final innerR = controller.innerRadius + ring * controller.ringWidth;
      final outerR = innerR + controller.ringWidth;

      for (int sector = 0; sector < sectorCount; sector++) {
        final cell = maze.grid[ring][sector];
        final start = sector * sa + rotOff;
        final sweep = sa;

        // Outer wall(s)
        if (ring < maze.rings - 1) {
          final outerSectors = maze.sectorsPerRing[ring + 1];
          final ratio = outerSectors ~/ sectorCount;
          if (ratio == 1) {
            if (cell.outerWalls[0]) {
              canvas.drawArc(
                Rect.fromCircle(center: center, radius: outerR),
                start, sweep, false, wallPaint,
              );
            }
          } else {
            final subSweep = sweep / ratio;
            for (int i = 0; i < ratio; i++) {
              if (!cell.outerWalls[i]) continue;
              canvas.drawArc(
                Rect.fromCircle(center: center, radius: outerR),
                start + i * subSweep, subSweep, false, wallPaint,
              );
            }
          }
        } else {
          canvas.drawArc(
            Rect.fromCircle(center: center, radius: outerR),
            start, sweep, false, wallPaint,
          );
        }

        // Inner wall — only for ring 0
        if (ring == 0 && cell.innerWall) {
          canvas.drawArc(
            Rect.fromCircle(center: center, radius: innerR),
            start, sweep, false, wallPaint,
          );
        }

        // CW radial wall — full length, no inset
        if (cell.cwWall) {
          final a = start + sweep;
          final p1 = Offset(
            center.dx + innerR * cos(a),
            center.dy + innerR * sin(a),
          );
          final p2 = Offset(
            center.dx + outerR * cos(a),
            center.dy + outerR * sin(a),
          );
          canvas.drawLine(p1, p2, wallPaint);
        }
      }

      // Short radial ticks at sector-doubling subdivision points.
      // Drawn only when both rings share the same rotation offset so
      // the tick aligns cleanly; otherwise the outer-arc gaps suffice.
      if (ring < maze.rings - 1) {
        final outerSectors = maze.sectorsPerRing[ring + 1];
        final ratio = outerSectors ~/ sectorCount;
        if (ratio > 1 &&
            (rotOff - controller.ringRotationOffsets[ring + 1]).abs() < 1e-9) {
          final tickLen = controller.ringWidth * 0.18;
          for (int sector = 0; sector < sectorCount; sector++) {
            final cell = maze.grid[ring][sector];
            if (cell.allOuterWallsOpen) continue;

            final subSweep = sa / ratio;
            for (int i = 1; i < ratio; i++) {
              final a = sector * sa + rotOff + i * subSweep;
              final p1 = Offset(
                center.dx + outerR * cos(a),
                center.dy + outerR * sin(a),
              );
              final p2 = Offset(
                center.dx + (outerR + tickLen) * cos(a),
                center.dy + (outerR + tickLen) * sin(a),
              );
              canvas.drawLine(p1, p2, wallPaint);
            }
          }
        }
      }
    }

    final ballRadius = controller.ballRadius;
    canvas.drawCircle(
      controller.goalOffset, ballRadius, Paint()..color = goalColor,
    );
    canvas.drawCircle(
      controller.ballOffset, ballRadius, Paint()..color = ballColor,
    );
  }

  @override
  bool shouldRepaint(covariant CircularMazePainter oldDelegate) => true;
}
