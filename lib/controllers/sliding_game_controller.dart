import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vibration/vibration.dart';

import '../models/maze.dart';

class SlidingGameController extends ChangeNotifier {
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

  static const int mazeCols = 10;
  static const int mazeRows = 15;
  static const double _animSpeed = 3.0;
  static const int _maxShiftMagnitude = 1;

  late Maze maze;
  late List<int> rowShifts;
  late List<int> colShifts;
  late List<int> slidableRows;
  late List<int> slidableCols;

  // Row animation
  int _pendingShiftRow = -1;
  int _pendingRowDir = 0;
  double _rowAnimProgress = 0;

  // Column animation
  int _pendingShiftCol = -1;
  int _pendingColDir = 0;
  double _colAnimProgress = 0;

  double _shiftTimer = 0;
  double _nextShiftIntervalSec = 2.4;

  int level = 1;
  int highLevel = 1;
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
  final _random = Random();

  SlidingGameController({
    int initialLevel = 1,
    int initialHighLevel = 1,
    this.onProgressChanged,
  }) {
    level = max(1, initialLevel);
    highLevel = max(level, initialHighLevel);
    _generateMaze();
    _initSensor();
    unawaited(_initVibration());
  }

  void _initSensor() {
    try {
      _sensorSub = accelerometerEventStream().listen((event) {
        _accelX = -event.x;
        _accelY = event.y;
      });
    } catch (_) {}
  }

  void setAcceleration(double x, double y) {
    _accelX = x;
    _accelY = y;
  }

  double get ballRadius {
    final maxByCell = min(cellWidth, cellHeight) * 0.32;
    return min(fixedBallRadius, maxByCell);
  }

  bool get isAnimating => _pendingShiftRow >= 0 || _pendingShiftCol >= 0;

  // ---------------------------------------------------------------------------
  // Maze generation
  // ---------------------------------------------------------------------------

  void _generateMaze() {
    maze = Maze(rows: mazeRows, cols: mazeCols)..generate();
    rowShifts = List.filled(mazeRows, 0);
    colShifts = List.filled(mazeCols, 0);

    slidableRows = [];
    for (int r = 4; r < mazeRows - 2; r += 4) {
      slidableRows.add(r);
    }
    slidableCols = [];
    for (int c = 3; c < mazeCols - 1; c += 4) {
      slidableCols.add(c);
    }

    _shiftTimer = 0;
    _pendingShiftRow = -1;
    _rowAnimProgress = 0;
    _pendingShiftCol = -1;
    _colAnimProgress = 0;
    _nextShiftIntervalSec = _randomShiftInterval();
    _needsStartPlacement = true;
    velocityX = 0;
    velocityY = 0;
    collisionCount = 0;
  }

  // ---------------------------------------------------------------------------
  // Layout
  // ---------------------------------------------------------------------------

  void setMazeBounds({required double width, required double height}) {
    mazeWidth = width;
    mazeHeight = height;
    cellWidth = width / maze.cols;
    cellHeight = height / maze.rows;
    if (_needsStartPlacement) {
      _placeBallAtStart();
      _needsStartPlacement = false;
    }
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
    for (int i = 0; i < rowShifts.length; i++) {
      rowShifts[i] = 0;
    }
    for (int i = 0; i < colShifts.length; i++) {
      colShifts[i] = 0;
    }
    _shiftTimer = 0;
    _pendingShiftRow = -1;
    _rowAnimProgress = 0;
    _pendingShiftCol = -1;
    _colAnimProgress = 0;
    _placeBallAtStart();
    collisionCount = 0;
    notifyListeners();
  }

  void newMaze() {
    _generateMaze();
    if (mazeWidth > 0 && mazeHeight > 0) {
      cellWidth = mazeWidth / maze.cols;
      cellHeight = mazeHeight / maze.rows;
      _placeBallAtStart();
      _needsStartPlacement = false;
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Composed cell lookup: visual position → original grid cell
  // ---------------------------------------------------------------------------

  int _effectiveRow(int visRow, int visCol) {
    return (visRow - colShifts[visCol] + maze.rows * 100) % maze.rows;
  }

  int _effectiveCol(int visRow, int visCol) {
    return (visCol - rowShifts[visRow] + maze.cols * 100) % maze.cols;
  }

  // ---------------------------------------------------------------------------
  // Wall queries — used by collision AND painter
  // ---------------------------------------------------------------------------

  bool isRightWallAt(int visRow, int visCol) {
    if (visCol >= maze.cols - 1) return true;
    final origR = _effectiveRow(visRow, visCol);
    final origC = _effectiveCol(visRow, visCol);
    final origR2 = _effectiveRow(visRow, visCol + 1);
    final origC2 = _effectiveCol(visRow, visCol + 1);

    if (origR == origR2) {
      if (origC2 == origC + 1) {
        return maze.grid[origR][origC].rightWall;
      }
      return true;
    }
    return maze.grid[origR][origC].rightWall &&
        maze.grid[origR2][origC2].leftWall;
  }

  bool isLeftWallAt(int visRow, int visCol) {
    if (visCol <= 0) return true;
    return isRightWallAt(visRow, visCol - 1);
  }

  bool isBottomWallAt(int visRow, int visCol) {
    if (visRow >= maze.rows - 1) return true;
    final origR = _effectiveRow(visRow, visCol);
    final origC = _effectiveCol(visRow, visCol);
    final origR2 = _effectiveRow(visRow + 1, visCol);
    final origC2 = _effectiveCol(visRow + 1, visCol);

    if (origC == origC2) {
      if (origR2 == origR + 1) {
        return maze.grid[origR][origC].bottomWall;
      }
      return true;
    }
    return maze.grid[origR][origC].bottomWall &&
        maze.grid[origR2][origC2].topWall;
  }

  bool isTopWallAt(int visRow, int visCol) {
    if (visRow <= 0) return true;
    return isBottomWallAt(visRow - 1, visCol);
  }

  // ---------------------------------------------------------------------------
  // Visual pixel offsets for painter (includes animation)
  // ---------------------------------------------------------------------------

  double rowVisualPixelOffset(int row) {
    double base = (rowShifts[row] % maze.cols) * cellWidth;
    if (row == _pendingShiftRow) {
      base += _pendingRowDir * _rowAnimProgress * cellWidth;
    }
    return base;
  }

  double colVisualPixelOffset(int col) {
    double base = (colShifts[col] % maze.rows) * cellHeight;
    if (col == _pendingShiftCol) {
      base += _pendingColDir * _colAnimProgress * cellHeight;
    }
    return base;
  }

  // ---------------------------------------------------------------------------
  // Update loop
  // ---------------------------------------------------------------------------

  void update() {
    if (cellWidth <= 0 || cellHeight <= 0) return;
    _collisionThisTick = false;

    _tickShiftTimer();
    _tickAnimation();

    velocityX = (velocityX + _accelX * sensitivity) * friction;
    velocityY = (velocityY + _accelY * sensitivity) * friction;
    velocityX = velocityX.clamp(-maxSpeed, maxSpeed);
    velocityY = velocityY.clamp(-maxSpeed, maxSpeed);

    _moveBallWithSubsteps();
    _emitCollisionHapticIfNeeded();
    notifyListeners();
  }

  void _tickShiftTimer() {
    _shiftTimer += 1 / 60;
    if (_shiftTimer >= _nextShiftIntervalSec && !isAnimating) {
      _shiftTimer = 0;
      _nextShiftIntervalSec = _randomShiftInterval();
      _triggerRandomShiftBurst();
    }
  }

  void _triggerRandomShiftBurst() {
    final triggerRow = slidableRows.isNotEmpty && _random.nextDouble() < 0.8;
    final triggerCol = slidableCols.isNotEmpty && _random.nextDouble() < 0.8;

    if (triggerRow && _pendingShiftRow < 0) {
      final row = slidableRows[_random.nextInt(slidableRows.length)];
      _pendingShiftRow = row;
      _pendingRowDir = _pickShiftDir(rowShifts[row]);
      _rowAnimProgress = 0;
    }

    if (triggerCol && _pendingShiftCol < 0) {
      final col = slidableCols[_random.nextInt(slidableCols.length)];
      _pendingShiftCol = col;
      _pendingColDir = _pickShiftDir(colShifts[col]);
      _colAnimProgress = 0;
    }

    if (_pendingShiftRow < 0 &&
        _pendingShiftCol < 0 &&
        slidableRows.isNotEmpty) {
      final row = slidableRows[_random.nextInt(slidableRows.length)];
      _pendingShiftRow = row;
      _pendingRowDir = _pickShiftDir(rowShifts[row]);
      _rowAnimProgress = 0;
    }
  }

  void _tickAnimation() {
    if (_pendingShiftRow >= 0) {
      _rowAnimProgress += _animSpeed / 60;
      if (_rowAnimProgress >= 1.0) {
        rowShifts[_pendingShiftRow] =
            (rowShifts[_pendingShiftRow] + _pendingRowDir)
                .clamp(-_maxShiftMagnitude, _maxShiftMagnitude);
        _pendingShiftRow = -1;
        _rowAnimProgress = 0;
        _pushBallOutOfWalls();
      }
    }
    if (_pendingShiftCol >= 0) {
      _colAnimProgress += _animSpeed / 60;
      if (_colAnimProgress >= 1.0) {
        colShifts[_pendingShiftCol] =
            (colShifts[_pendingShiftCol] + _pendingColDir)
                .clamp(-_maxShiftMagnitude, _maxShiftMagnitude);
        _pendingShiftCol = -1;
        _colAnimProgress = 0;
        _pushBallOutOfWalls();
      }
    }
  }

  int _pickShiftDir(int currentShift) {
    if (currentShift >= _maxShiftMagnitude) return -1;
    if (currentShift <= -_maxShiftMagnitude) return 1;
    if (currentShift != 0 && _random.nextDouble() < 0.7) {
      return -currentShift.sign;
    }
    return _random.nextBool() ? 1 : -1;
  }

  double _randomShiftInterval() => 1.8 + _random.nextDouble() * 2.0;

  void _pushBallOutOfWalls() {
    final r = ballRadius;
    final visCol = _visualColFor(ballX);
    final visRow = _visualRowFor(ballY);

    final leftX = visCol * cellWidth;
    final rightX = leftX + cellWidth;
    final topY = visRow * cellHeight;
    final bottomY = topY + cellHeight;

    if (isLeftWallAt(visRow, visCol) && ballX - r < leftX) {
      ballX = leftX + r + 0.5;
    }
    if (isRightWallAt(visRow, visCol) && ballX + r > rightX) {
      ballX = rightX - r - 0.5;
    }
    if (isTopWallAt(visRow, visCol) && ballY - r < topY) {
      ballY = topY + r + 0.5;
    }
    if (isBottomWallAt(visRow, visCol) && ballY + r > bottomY) {
      ballY = bottomY - r - 0.5;
    }
  }

  // ---------------------------------------------------------------------------
  // Movement & collision
  // ---------------------------------------------------------------------------

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
    const edgeEps = 0.35;
    var nx = ballX + dx;

    final visCol = _visualColFor(ballX);
    final visRow = _visualRowFor(ballY);

    final leftX = visCol * cellWidth;
    final rightX = leftX + cellWidth;

    if (isLeftWallAt(visRow, visCol) && nx - r < leftX) {
      nx = leftX + r + edgeEps;
      _bounceX();
    }
    if (isRightWallAt(visRow, visCol) && nx + r > rightX) {
      nx = rightX - r - edgeEps;
      _bounceX();
    }

    ballX = nx.clamp(r, mazeWidth - r);
  }

  void _moveY(double dy) {
    final r = ballRadius;
    const edgeEps = 0.35;
    var ny = ballY + dy;

    final visCol = _visualColFor(ballX);
    final visRow = _visualRowFor(ballY);

    final topY = visRow * cellHeight;
    final bottomY = topY + cellHeight;

    if (isTopWallAt(visRow, visCol) && ny - r < topY) {
      ny = topY + r + edgeEps;
      _bounceY();
    }
    if (isBottomWallAt(visRow, visCol) && ny + r > bottomY) {
      ny = bottomY - r - edgeEps;
      _bounceY();
    }

    ballY = ny.clamp(r, mazeHeight - r);
  }

  int _visualColFor(double x) =>
      (x / cellWidth).floor().clamp(0, maze.cols - 1);
  int _visualRowFor(double y) =>
      (y / cellHeight).floor().clamp(0, maze.rows - 1);

  // ---------------------------------------------------------------------------
  // Goal
  // ---------------------------------------------------------------------------

  double get goalX => (maze.cols - 1) * cellWidth + cellWidth / 2;
  double get goalY => (maze.rows - 1) * cellHeight + cellHeight / 2;

  void _applyGoalMagnet() {
    final gx = goalX;
    final gy = goalY;
    final col = _visualColFor(ballX);
    final row = _visualRowFor(ballY);
    final goalCol = maze.cols - 1;
    final goalRow = maze.rows - 1;

    final inGoalCell = row == goalRow && col == goalCol;
    final inLeft = goalCol > 0 &&
        row == goalRow &&
        col == goalCol - 1 &&
        !isRightWallAt(goalRow, goalCol - 1);
    final inTop = goalRow > 0 &&
        col == goalCol &&
        row == goalRow - 1 &&
        !isBottomWallAt(goalRow - 1, goalCol);

    if (!inGoalCell && !inLeft && !inTop) return;

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

  void _checkGoalReached() {
    final dx = ballX - goalX;
    final dy = ballY - goalY;
    final threshold = ballRadius * 1.35;
    if (dx * dx + dy * dy <= threshold * threshold) {
      level += 1;
      if (level > highLevel) highLevel = level;
      _generateMaze();
      _placeBallAtStart();
      onProgressChanged?.call(level, highLevel);
    }
  }

  // ---------------------------------------------------------------------------
  // Bounce & haptics
  // ---------------------------------------------------------------------------

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
    if (now.difference(_lastCollisionCountedAt).inMilliseconds <
        _collisionCooldownMs) {
      return;
    }
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

  @override
  void dispose() {
    _sensorSub?.cancel();
    super.dispose();
  }
}
