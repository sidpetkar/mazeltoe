import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vibration/vibration.dart';

import '../models/maze.dart';

class GameController extends ChangeNotifier {
  static const double friction = 0.92;
  static const double maxSpeed = 14.0;
  static const double sensitivity = 0.35;
  static const double fixedBallRadius = 5.5;
  static const double bounceFactor = 0.9;
  static const double minBounceSpeed = 0.15;
  static const double magnetRangeCells = 1.25;
  static const double magnetBasePull = 0.04;
  static const double magnetExtraPull = 0.12;
  static const int _collisionCooldownMs = 350;

  static const int baseCols = 6;
  static const int baseRows = 9;

  late Maze maze;

  int highLevel = 1;
  int level = 1;
  int collisionCount = 0;
  final void Function(int level, int highLevel)? onProgressChanged;

  double mazeWidth = 0;
  double mazeHeight = 0;
  double cellWidth = 0;
  double cellHeight = 0;

  double ballX = 0;
  double ballY = 0;
  double velocityX = 0;
  double velocityY = 0;

  double _accelX = 0;
  double _accelY = 0;
  bool _needsStartPlacement = true;
  bool _collisionThisTick = false;
  bool _wasCollidingLastTick = false;
  DateTime _lastCollisionCountedAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _canVibrate = false;
  bool vibrationEnabled = true;

  StreamSubscription<AccelerometerEvent>? _sensorSub;

  GameController({
    int initialLevel = 1,
    int initialHighLevel = 1,
    this.onProgressChanged,
  }) {
    level = max(1, initialLevel);
    highLevel = max(level, initialHighLevel);
    _generateMazeForCurrentLevel();
    _initSensor();
    unawaited(_initVibration());
  }

  void _initSensor() {
    try {
      _sensorSub = accelerometerEventStream().listen((event) {
        _accelX = -event.x;
        _accelY = event.y;
      });
    } catch (_) {
      // No accelerometer (e.g. desktop web) — keyboard fallback used instead
    }
  }

  /// Allows external input (keyboard arrow keys on web) to drive the ball.
  void setAcceleration(double x, double y) {
    _accelX = x;
    _accelY = y;
  }

  int get cols => baseCols + (level - 1);
  int get rows => baseRows + (level - 1);

  double get ballRadius {
    final maxByCell = min(cellWidth, cellHeight) * 0.32;
    return min(fixedBallRadius, maxByCell);
  }

  void setMazeBounds({required double width, required double height}) {
    mazeWidth = width;
    mazeHeight = height;
    _recalculateCellMetrics();
    if (_needsStartPlacement) {
      _placeBallAtStart();
      _needsStartPlacement = false;
    }
  }

  void _recalculateCellMetrics() {
    if (mazeWidth <= 0 || mazeHeight <= 0) return;
    cellWidth = mazeWidth / maze.cols;
    cellHeight = mazeHeight / maze.rows;
  }

  void _generateMazeForCurrentLevel() {
    maze = Maze(rows: rows, cols: cols);
    maze.generate();
    _recalculateCellMetrics();
    velocityX = 0;
    velocityY = 0;
    collisionCount = 0;
    _needsStartPlacement = true;
  }

  void _placeBallAtStart() {
    if (cellWidth <= 0 || cellHeight <= 0) return;
    ballX = cellWidth / 2;
    ballY = cellHeight / 2;
    velocityX = 0;
    velocityY = 0;
    _collisionThisTick = false;
    _wasCollidingLastTick = false;
  }

  void restartMaze() {
    _placeBallAtStart();
    collisionCount = 0;
    notifyListeners();
  }

  void newMaze() {
    maze = Maze(rows: rows, cols: cols)..generate();
    _recalculateCellMetrics();
    _placeBallAtStart();
    collisionCount = 0;
    notifyListeners();
  }

  void update() {
    if (cellWidth <= 0 || cellHeight <= 0) return;
    _collisionThisTick = false;

    velocityX = (velocityX + _accelX * sensitivity) * friction;
    velocityY = (velocityY + _accelY * sensitivity) * friction;

    velocityX = velocityX.clamp(-maxSpeed, maxSpeed);
    velocityY = velocityY.clamp(-maxSpeed, maxSpeed);

    _moveBallWithSubsteps();
    _emitCollisionHapticIfNeeded();
    notifyListeners();
  }

  void _moveBallWithSubsteps() {
    final maxDelta = max(velocityX.abs(), velocityY.abs());
    final minCell = max(1.0, min(cellWidth, cellHeight));
    final steps = max(1, (maxDelta / (minCell * 0.2)).ceil());

    final stepX = velocityX / steps;
    final stepY = velocityY / steps;

    for (int i = 0; i < steps; i++) {
      _moveX(stepX);
      _moveY(stepY);
    }

    _applyGoalMagnet();
    _checkGoalReached();
  }

  void _moveX(double dx) {
    final r = ballRadius;
    const edgeEpsilon = 0.35;
    var nx = ballX + dx;

    final col = _colFor(ballX);
    final row = _rowFor(ballY);
    final cell = maze.grid[row][col];

    final leftWallX = col * cellWidth;
    final rightWallX = leftWallX + cellWidth;

    if (cell.leftWall && nx - r < leftWallX) {
      nx = leftWallX + r + edgeEpsilon;
      _bounceX();
    }

    if (cell.rightWall && nx + r > rightWallX) {
      nx = rightWallX - r - edgeEpsilon;
      _bounceX();
    }

    ballX = nx.clamp(r, mazeWidth - r);
  }

  void _moveY(double dy) {
    final r = ballRadius;
    const edgeEpsilon = 0.35;
    var ny = ballY + dy;

    final col = _colFor(ballX);
    final row = _rowFor(ballY);
    final cell = maze.grid[row][col];

    final topWallY = row * cellHeight;
    final bottomWallY = topWallY + cellHeight;

    if (cell.topWall && ny - r < topWallY) {
      ny = topWallY + r + edgeEpsilon;
      _bounceY();
    }

    if (cell.bottomWall && ny + r > bottomWallY) {
      ny = bottomWallY - r - edgeEpsilon;
      _bounceY();
    }

    ballY = ny.clamp(r, mazeHeight - r);
  }

  int _colFor(double x) {
    var idx = (x / cellWidth).floor();
    if (idx < 0) return 0;
    if (idx >= maze.cols) return maze.cols - 1;
    return idx;
  }

  int _rowFor(double y) {
    var idx = (y / cellHeight).floor();
    if (idx < 0) return 0;
    if (idx >= maze.rows) return maze.rows - 1;
    return idx;
  }

  void _applyGoalMagnet() {
    final goalCol = maze.cols - 1;
    final goalRow = maze.rows - 1;
    final goalCell = maze.grid[goalRow][goalCol];

    final col = _colFor(ballX);
    final row = _rowFor(ballY);

    final inGoalCell = row == goalRow && col == goalCol;
    final inLeftNeighborConnected =
        goalCol > 0 &&
        row == goalRow &&
        col == goalCol - 1 &&
        !goalCell.leftWall;
    final inTopNeighborConnected =
        goalRow > 0 &&
        col == goalCol &&
        row == goalRow - 1 &&
        !goalCell.topWall;

    if (!inGoalCell && !inLeftNeighborConnected && !inTopNeighborConnected) {
      return;
    }

    final gx = goalCol * cellWidth + cellWidth / 2;
    final gy = goalRow * cellHeight + cellHeight / 2;
    final dx = gx - ballX;
    final dy = gy - ballY;
    final dist = sqrt(dx * dx + dy * dy);

    final magnetRange = min(cellWidth, cellHeight) * magnetRangeCells;
    if (dist <= 0.0001 || dist > magnetRange) return;

    final t = 1 - (dist / magnetRange);
    final pull = magnetBasePull + (magnetExtraPull * t);

    final r = ballRadius;
    ballX = (ballX + dx * pull).clamp(r, mazeWidth - r);
    ballY = (ballY + dy * pull).clamp(r, mazeHeight - r);
    velocityX *= 0.92;
    velocityY *= 0.92;
  }

  void _bounceX() {
    if (velocityX.abs() >= minBounceSpeed) {
      velocityX = -velocityX * bounceFactor;
      _collisionThisTick = true;
    } else {
      velocityX = 0;
    }
  }

  void _bounceY() {
    if (velocityY.abs() >= minBounceSpeed) {
      velocityY = -velocityY * bounceFactor;
      _collisionThisTick = true;
    } else {
      velocityY = 0;
    }
  }

  void _emitCollisionHapticIfNeeded() {
    final isNewEdge = _collisionThisTick && !_wasCollidingLastTick;
    _wasCollidingLastTick = _collisionThisTick;
    if (!isNewEdge) return;
    final now = DateTime.now();
    if (now.difference(_lastCollisionCountedAt).inMilliseconds < _collisionCooldownMs) return;
    _lastCollisionCountedAt = now;
    collisionCount += 1;
    if (!vibrationEnabled) return;
    if (_canVibrate) {
      unawaited(Vibration.vibrate(duration: 24, amplitude: 200));
    } else {
      try {
        HapticFeedback.heavyImpact();
      } catch (_) {}
    }
  }

  Future<void> _initVibration() async {
    try {
      _canVibrate = await Vibration.hasVibrator();
    } catch (_) {
      _canVibrate = false;
    }
  }

  void _checkGoalReached() {
    final gx = (maze.cols - 1) * cellWidth + cellWidth / 2;
    final gy = (maze.rows - 1) * cellHeight + cellHeight / 2;
    final dx = ballX - gx;
    final dy = ballY - gy;

    final threshold = ballRadius * 1.35;
    if (dx * dx + dy * dy <= threshold * threshold) {
      level += 1;
      if (level > highLevel) {
        highLevel = level;
      }
      _generateMazeForCurrentLevel();
      _placeBallAtStart();
      onProgressChanged?.call(level, highLevel);
    }
  }

  @override
  void dispose() {
    _sensorSub?.cancel();
    super.dispose();
  }
}
