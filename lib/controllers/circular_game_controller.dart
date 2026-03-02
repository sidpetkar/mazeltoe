import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vibration/vibration.dart';

import '../models/circular_maze.dart';

class CircularGameController extends ChangeNotifier {
  static const double friction = 0.93;
  static const double sensitivity = 0.34;
  static const double maxRadialSpeed = 8;
  static const double maxTangentialSpeed = 8;
  static const double bounceFactor = 0.82;
  static const double fixedBallRadius = 5.5;
  static const int _collisionCooldownMs = 400;

  late CircularMaze maze;

  int level = 1;
  int highLevel = 1;
  int collisionCount = 0;
  final void Function(int level, int highLevel)? onProgressChanged;

  double canvasWidth = 0;
  double canvasHeight = 0;
  double centerX = 0;
  double centerY = 0;

  double innerRadius = 18;
  double ringWidth = 14;
  double outerRadius = 100;

  double radialPos = 0;
  double theta = 0;

  double radialVel = 0;
  double tangentialVel = 0;

  late List<double> ringRotationOffsets;
  late List<double> ringRotationSpeeds;

  double _accelX = 0;
  double _accelY = 0;
  bool _needsStartPlacement = true;
  bool _collisionThisTick = false;
  bool _wasCollidingLastTick = false;
  DateTime _lastCollisionCountedAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _canVibrate = false;
  bool vibrationEnabled = true;

  StreamSubscription<AccelerometerEvent>? _sensorSub;

  CircularGameController({
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
    } catch (_) {}
  }

  /// Allows external input (keyboard arrow keys on web) to drive the ball.
  void setAcceleration(double x, double y) {
    _accelX = x;
    _accelY = y;
  }

  // ---------------------------------------------------------------------------
  // Level scaling — phases 1-4+
  // ---------------------------------------------------------------------------

  int get _levelRings {
    if (level <= 10) return 6;
    if (level <= 13) return 7;
    if (level <= 20) return 8;
    return 9; // L21+
  }

  int get _levelBaseSectors {
    // Phases 1-2 (uniform): grow sectors, capped to keep center playable.
    if (level <= 10) return 12 + level; // 13..22
    if (level <= 15) return 22;
    // Phase 3+ (non-uniform): inner ring stays sparse, doubling handles outer.
    return min(14, 8 + ((level - 15) * 0.2).round());
  }

  List<int> _computeSectorsPerRing(int ringCount, int baseSectors) {
    if (ringCount <= 0) return [baseSectors];
    // Phases 1-2: uniform sectors across all rings.
    if (level <= 15) return List.filled(ringCount, baseSectors);

    // Phase 3+: double sector count at rings where cells become
    // significantly wider than they are tall (arc > 2× ringWidth).
    final usable = canvasWidth > 0 ? min(canvasWidth, canvasHeight) / 2 : 163.0;
    final ir = max(16.0, usable * 0.12);
    final rw = (usable - ir) / ringCount;

    final result = <int>[baseSectors];
    for (int r = 1; r < ringCount; r++) {
      final radius = ir + (r + 0.5) * rw;
      final prev = result[r - 1];
      final arcLen = 2 * pi * radius / prev;
      if (arcLen > rw * 2.0 && prev < 60) {
        result.add(prev * 2);
      } else {
        result.add(prev);
      }
    }
    return result;
  }

  double sectorAngleForRing(int ring) =>
      (2 * pi) / maze.sectorsPerRing[ring];

  double get ballRadius => fixedBallRadius;

  Offset get ballOffset => Offset(
    centerX + radialPos * cos(theta),
    centerY + radialPos * sin(theta),
  );

  Offset get goalOffset {
    final goal = _goalCenterPolar();
    return Offset(
      centerX + goal.$1 * cos(goal.$2),
      centerY + goal.$1 * sin(goal.$2),
    );
  }

  // ---------------------------------------------------------------------------
  // Rotating rings — phase 4+
  // ---------------------------------------------------------------------------

  void _initRotation(int ringCount) {
    ringRotationOffsets = List.filled(ringCount, 0.0);
    ringRotationSpeeds = List.filled(ringCount, 0.0);

    if (level < 21 || ringCount < 3) return;

    // Build contiguous groups of same-sector-count rings.
    // Entire groups rotate together so internal boundaries stay clean.
    // Boundaries between groups fall at sector-doubling points where
    // visual mismatch is the intended game mechanic (gates open/close).
    final groups = <List<int>>[];
    var cur = <int>[0];
    for (int r = 1; r < ringCount; r++) {
      if (maze.sectorsPerRing[r] == maze.sectorsPerRing[r - 1]) {
        cur.add(r);
      } else {
        groups.add(cur);
        cur = <int>[r];
      }
    }
    groups.add(cur);

    // Eligible groups: exclude the group containing ring 0 and the group
    // containing the outermost ring (goal lives there), require >= 2 rings.
    final eligible = <List<int>>[];
    for (final g in groups) {
      final trimmed = g.where((r) => r != 0 && r != ringCount - 1).toList();
      if (trimmed.length >= 2) eligible.add(trimmed);
    }
    if (eligible.isEmpty) return;

    // Sort by proximity to maze center so inner groups rotate first.
    final midRing = ringCount / 2;
    eligible.sort((a, b) {
      final aCenter = a.fold<double>(0, (s, r) => s + r) / a.length;
      final bCenter = b.fold<double>(0, (s, r) => s + r) / b.length;
      return (aCenter - midRing).abs().compareTo((bCenter - midRing).abs());
    });

    final groupCount = min(eligible.length, 1 + ((level - 21) ~/ 10));
    final baseSpeed = min(0.008, 0.0015 + (level - 21) * 0.0002);

    for (int i = 0; i < groupCount; i++) {
      final group = eligible[i];
      final direction = i.isEven ? 1.0 : -1.0;
      final speed = baseSpeed * direction * (1 + i * 0.25);
      for (final r in group) {
        ringRotationSpeeds[r] = speed;
      }
    }
  }

  void _tickRotation() {
    for (int i = 0; i < ringRotationOffsets.length; i++) {
      ringRotationOffsets[i] += ringRotationSpeeds[i];
    }
  }

  // ---------------------------------------------------------------------------
  // Layout
  // ---------------------------------------------------------------------------

  void setBounds({required double width, required double height}) {
    canvasWidth = width;
    canvasHeight = height;
    centerX = width / 2;
    centerY = height / 2;

    _recomputeLayout();

    if (_needsStartPlacement) {
      _placeBallAtStart();
      _needsStartPlacement = false;
    }
  }

  void _recomputeLayout() {
    final usable = min(canvasWidth, canvasHeight) / 2;
    innerRadius = max(16, usable * 0.12);
    ringWidth = (usable - innerRadius) / maze.rings;
    outerRadius = innerRadius + ringWidth * maze.rings;
  }

  void restartMaze() {
    _placeBallAtStart();
    collisionCount = 0;
    for (int i = 0; i < ringRotationOffsets.length; i++) {
      ringRotationOffsets[i] = 0;
    }
    notifyListeners();
  }

  void newMaze() {
    final ringCount = _levelRings;
    final spr = _computeSectorsPerRing(ringCount, _levelBaseSectors);
    maze = CircularMaze(rings: ringCount, sectorsPerRing: spr)..generateDfs();
    _initRotation(ringCount);
    _recomputeLayout();
    _placeBallAtStart();
    collisionCount = 0;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Update loop
  // ---------------------------------------------------------------------------

  void update() {
    if (ringWidth <= 0 || outerRadius <= 0) return;
    _collisionThisTick = false;

    _tickRotation();

    final radialUnitX = cos(theta);
    final radialUnitY = sin(theta);
    final tangentUnitX = -sin(theta);
    final tangentUnitY = cos(theta);

    final accelR = (_accelX * radialUnitX) + (_accelY * radialUnitY);
    final accelT = (_accelX * tangentUnitX) + (_accelY * tangentUnitY);

    radialVel = (radialVel + accelR * sensitivity) * friction;
    tangentialVel = (tangentialVel + accelT * sensitivity) * friction;

    radialVel = radialVel.clamp(-maxRadialSpeed, maxRadialSpeed);
    tangentialVel = tangentialVel.clamp(-maxTangentialSpeed, maxTangentialSpeed);

    _moveWithSubsteps();
    _handleRotatingWallPush();
    _emitCollisionHapticIfNeeded();
    notifyListeners();
  }

  void _generateMazeForCurrentLevel() {
    final ringCount = _levelRings;
    final spr = _computeSectorsPerRing(ringCount, _levelBaseSectors);
    maze = CircularMaze(rings: ringCount, sectorsPerRing: spr)..generateDfs();
    _initRotation(ringCount);
    _needsStartPlacement = true;
    radialVel = 0;
    tangentialVel = 0;
    collisionCount = 0;
    _collisionThisTick = false;
    _wasCollidingLastTick = false;
  }

  void _placeBallAtStart() {
    final sa = sectorAngleForRing(0);
    radialPos = innerRadius + (ringWidth * 0.5);
    theta = sa * 0.5;
    radialVel = 0;
    tangentialVel = 0;
    _collisionThisTick = false;
    _wasCollidingLastTick = false;
  }

  // ---------------------------------------------------------------------------
  // Movement & collision
  // ---------------------------------------------------------------------------

  void _moveWithSubsteps() {
    final maxDelta = max(radialVel.abs(), tangentialVel.abs());
    final ring0Angle = sectorAngleForRing(0);
    final innerArc = (innerRadius + ringWidth * 0.5) * ring0Angle;
    final smallestDim = min(ringWidth, innerArc);
    final stepUnit = max(0.1, smallestDim * 0.04);
    final steps = max(1, (maxDelta / stepUnit).ceil());

    final stepR = radialVel / steps;
    final stepT = tangentialVel / steps;

    for (int i = 0; i < steps; i++) {
      _moveRadial(stepR);
      _moveAngular(stepT);
    }

    _applyGoalMagnet();
    _checkGoalReached();
  }

  int _sectorForRing(int ring, double angle) {
    final sa = sectorAngleForRing(ring);
    final a = _normalizeAngle(angle - ringRotationOffsets[ring]);
    final idx = (a / sa).floor();
    return idx.clamp(0, maze.sectorsPerRing[ring] - 1);
  }

  void _moveRadial(double deltaR) {
    final ring = _ringFor(radialPos);
    final sector = _sectorForRing(ring, theta);
    final cell = maze.grid[ring][sector];
    final r = ballRadius;

    var nextR = radialPos + deltaR;
    final ringInner = innerRadius + (ring * ringWidth);
    final ringOuter = ringInner + ringWidth;

    if (cell.innerWall && nextR - r < ringInner) {
      nextR = ringInner + r;
      radialVel = -radialVel * bounceFactor;
      _collisionThisTick = true;
    }

    if (_isOuterWallBlocking(cell, ring, theta) && nextR + r > ringOuter) {
      nextR = ringOuter - r;
      radialVel = -radialVel * bounceFactor;
      _collisionThisTick = true;
    }

    radialPos = nextR.clamp(innerRadius + r, outerRadius - r);
  }

  bool _isOuterWallBlocking(CircularCell cell, int ring, double ballTheta) {
    if (ring >= maze.rings - 1) return cell.outerWalls[0];
    final ratio = maze.sectorsPerRing[ring + 1] ~/ maze.sectorsPerRing[ring];
    if (ratio == 1) return cell.outerWalls[0];

    final sa = sectorAngleForRing(ring);
    final localAngle = _localAngleInCell(ring, cell.sector, ballTheta);
    final childIndex = (localAngle / (sa / ratio)).floor().clamp(0, ratio - 1);
    return cell.outerWalls[childIndex];
  }

  void _moveAngular(double deltaTangent) {
    final ring = _ringFor(radialPos);
    final sector = _sectorForRing(ring, theta);
    final cell = maze.grid[ring][sector];
    final sa = sectorAngleForRing(ring);

    final radiusForAngle = max(radialPos, innerRadius + 1);
    final deltaTheta = deltaTangent / radiusForAngle;
    final margin = ballRadius / radiusForAngle;

    final sectorStart = sector * sa + ringRotationOffsets[ring];
    var localAngle = _normalizeAngle(theta) - _normalizeAngle(sectorStart);
    if (localAngle < -pi) localAngle += 2 * pi;
    if (localAngle > pi) localAngle -= 2 * pi;
    if (localAngle < -1e-9) localAngle += 2 * pi;
    localAngle = localAngle.clamp(0.0, sa);

    var nextLocal = localAngle + deltaTheta;

    if (cell.ccwWall && nextLocal < margin) {
      nextLocal = margin;
      tangentialVel = -tangentialVel * bounceFactor;
      _collisionThisTick = true;
    }

    if (cell.cwWall && nextLocal > sa - margin) {
      nextLocal = sa - margin;
      tangentialVel = -tangentialVel * bounceFactor;
      _collisionThisTick = true;
    }

    theta = _normalizeAngle(sectorStart + nextLocal);
  }

  double _localAngleInCell(int ring, int sector, double ballTheta) {
    final sa = sectorAngleForRing(ring);
    final sectorStart = sector * sa + ringRotationOffsets[ring];
    var local = _normalizeAngle(ballTheta) - _normalizeAngle(sectorStart);
    if (local < -pi) local += 2 * pi;
    if (local > pi) local -= 2 * pi;
    if (local < 0) local += 2 * pi;
    return local.clamp(0.0, sa);
  }

  /// Push ball out if a rotating wall has swept into it.
  void _handleRotatingWallPush() {
    final ring = _ringFor(radialPos);
    final sector = _sectorForRing(ring, theta);
    final cell = maze.grid[ring][sector];
    final sa = sectorAngleForRing(ring);
    final radiusForAngle = max(radialPos, innerRadius + 1);
    final margin = ballRadius / radiusForAngle;

    final local = _localAngleInCell(ring, sector, theta);
    final sectorStart = sector * sa + ringRotationOffsets[ring];

    if (cell.ccwWall && local < margin) {
      theta = _normalizeAngle(sectorStart + margin);
      tangentialVel = tangentialVel.abs() * 0.5;
      _collisionThisTick = true;
    } else if (cell.cwWall && local > sa - margin) {
      theta = _normalizeAngle(sectorStart + sa - margin);
      tangentialVel = -tangentialVel.abs() * 0.5;
      _collisionThisTick = true;
    }
  }

  int _ringFor(double radius) {
    final idx = ((radius - innerRadius) / ringWidth).floor();
    return idx.clamp(0, maze.rings - 1);
  }

  double _normalizeAngle(double angle) {
    var a = angle % (2 * pi);
    if (a < 0) a += 2 * pi;
    return a;
  }

  // ---------------------------------------------------------------------------
  // Goal
  // ---------------------------------------------------------------------------

  (double, double) _goalCenterPolar() {
    final goalRing = maze.rings - 1;
    final outerSectors = maze.sectorsPerRing[goalRing];
    final goalSector = outerSectors ~/ 2;
    final goalR = innerRadius + (goalRing + 0.5) * ringWidth;
    final sa = sectorAngleForRing(goalRing);
    final goalTheta = (goalSector + 0.5) * sa +
        ringRotationOffsets[goalRing];
    return (goalR, goalTheta);
  }

  void _applyGoalMagnet() {
    final goal = _goalCenterPolar();
    final gx = centerX + goal.$1 * cos(goal.$2);
    final gy = centerY + goal.$1 * sin(goal.$2);
    final b = ballOffset;
    final dx = gx - b.dx;
    final dy = gy - b.dy;
    final dist = sqrt(dx * dx + dy * dy);
    final magnetRange = ringWidth * 1.25;
    if (dist <= 0.001 || dist > magnetRange) return;

    final t = 1 - (dist / magnetRange);
    final pull = 0.02 + 0.1 * t;

    final toGoalX = dx / dist;
    final toGoalY = dy / dist;
    final radialUnitX = cos(theta);
    final radialUnitY = sin(theta);
    final tangentUnitX = -sin(theta);
    final tangentUnitY = cos(theta);

    final pullR = (toGoalX * radialUnitX + toGoalY * radialUnitY) * pull * ringWidth;
    final pullT = (toGoalX * tangentUnitX + toGoalY * tangentUnitY) * pull * ringWidth;

    radialPos = (radialPos + pullR).clamp(innerRadius + ballRadius, outerRadius - ballRadius);
    theta = _normalizeAngle(theta + (pullT / max(radialPos, 1)));
  }

  void _checkGoalReached() {
    final goal = _goalCenterPolar();
    final radialDiff = (radialPos - goal.$1).abs();
    final angularDiff = min(
      (theta - goal.$2).abs(),
      (2 * pi) - (theta - goal.$2).abs(),
    );
    final angularArcDiff = angularDiff * radialPos;

    if (radialDiff <= ringWidth * 0.32 && angularArcDiff <= ringWidth * 0.32) {
      level += 1;
      if (level > highLevel) {
        highLevel = level;
      }
      _generateMazeForCurrentLevel();
      if (canvasWidth > 0 && canvasHeight > 0) {
        _recomputeLayout();
      }
      _placeBallAtStart();
      onProgressChanged?.call(level, highLevel);
    }
  }

  // ---------------------------------------------------------------------------
  // Haptics
  // ---------------------------------------------------------------------------

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

  @override
  void dispose() {
    _sensorSub?.cancel();
    super.dispose();
  }
}
