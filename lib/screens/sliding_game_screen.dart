import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../controllers/sliding_game_controller.dart';
import '../painters/sliding_maze_painter.dart';
import '../theme/app_colors.dart';

class SlidingGameScreen extends StatefulWidget {
  final int initialLevel;
  final int initialHighLevel;
  final bool timerEnabled;
  final bool vibrationEnabled;
  final void Function(int level, int highLevel)? onProgressChanged;

  const SlidingGameScreen({
    super.key,
    this.initialLevel = 1,
    this.initialHighLevel = 1,
    this.timerEnabled = true,
    this.vibrationEnabled = true,
    this.onProgressChanged,
  });

  @override
  State<SlidingGameScreen> createState() => _SlidingGameScreenState();
}

class _SlidingGameScreenState extends State<SlidingGameScreen>
    with SingleTickerProviderStateMixin {
  static const double _horizontalPadding = 32.0;
  static const int _levelTimeMs = 60000;
  static const double _keyAccel = 6.0;

  late SlidingGameController _controller;
  late Ticker _ticker;

  int _remainingMs = _levelTimeMs;
  Duration _lastTickerDuration = Duration.zero;
  bool _paused = false;
  int _lastKnownLevel = 1;
  final _pressedKeys = <LogicalKeyboardKey>{};
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = SlidingGameController(
      initialLevel: widget.initialLevel,
      initialHighLevel: widget.initialHighLevel,
      onProgressChanged: widget.onProgressChanged,
    );
    _controller.vibrationEnabled = widget.vibrationEnabled;
    _lastKnownLevel = _controller.level;
    _ticker = createTicker(_onTick)..start();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  void _onTick(Duration elapsed) {
    final delta = elapsed - _lastTickerDuration;
    _lastTickerDuration = elapsed;

    _controller.update();

    if (widget.timerEnabled && _remainingMs > 0) {
      _remainingMs -= delta.inMilliseconds;
      if (_remainingMs <= 0) {
        _remainingMs = _levelTimeMs;
        _controller.restartMaze();
      }
    }

    if (_controller.level != _lastKnownLevel) {
      _lastKnownLevel = _controller.level;
      _remainingMs = _levelTimeMs;
    }
  }

  void _togglePause() {
    setState(() {
      _paused = !_paused;
      if (_paused) {
        _ticker.stop();
      } else {
        _lastTickerDuration = Duration.zero;
        _ticker.start();
      }
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final isArrow = key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
    if (!isArrow) return KeyEventResult.ignored;

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _pressedKeys.add(key);
    } else if (event is KeyUpEvent) {
      _pressedKeys.remove(key);
    }
    _updateAccelFromKeys();
    return KeyEventResult.handled;
  }

  void _updateAccelFromKeys() {
    double ax = 0, ay = 0;
    if (_pressedKeys.contains(LogicalKeyboardKey.arrowLeft)) ax -= _keyAccel;
    if (_pressedKeys.contains(LogicalKeyboardKey.arrowRight)) ax += _keyAccel;
    if (_pressedKeys.contains(LogicalKeyboardKey.arrowUp)) ay -= _keyAccel;
    if (_pressedKeys.contains(LogicalKeyboardKey.arrowDown)) ay += _keyAccel;
    _controller.setAcceleration(ax, ay);
  }

  String _formatTimer(int ms) {
    final totalSeconds = (ms / 1000).ceil().clamp(0, 99);
    return '${totalSeconds}s';
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _ticker.dispose();
    _controller.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: c.background,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _buildTopBar(c),
                  Expanded(child: _buildMazeStage(c)),
                  _buildBottomBar(c),
                ],
              ),
              if (_paused) _buildPauseOverlay(c),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(AppColors c) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            _horizontalPadding, 20, _horizontalPadding, 8,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _label('LEVEL', '${_controller.level}', CrossAxisAlignment.start, c),
              ),
              if (widget.timerEnabled)
                Expanded(
                  child: _label('TIME LEFT', _formatTimer(_remainingMs), CrossAxisAlignment.center, c),
                ),
              Expanded(
                child: _label('COLLISIONS', '${_controller.collisionCount}', CrossAxisAlignment.end, c),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _label(String title, String value, CrossAxisAlignment alignment, AppColors c) {
    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: 'SulphurPoint',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: c.primaryText,
            letterSpacing: 1.5,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'SulphurPoint',
            fontSize: 36,
            fontWeight: FontWeight.w700,
            color: c.primaryText,
          ),
        ),
      ],
    );
  }

  Widget _buildMazeStage(AppColors c) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mazeWidth = constraints.maxWidth - (_horizontalPadding * 2);
        final targetHeight = mazeWidth * 1.45;
        final mazeHeight =
            targetHeight > constraints.maxHeight ? constraints.maxHeight : targetHeight;

        _controller.setMazeBounds(width: mazeWidth, height: mazeHeight);

        return Center(
          child: SizedBox(
            width: mazeWidth,
            height: mazeHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: c.wallColor,
                  width: AppColors.wallStrokeWidth,
                ),
              ),
              child: ClipRect(
                child: CustomPaint(
                  size: Size(mazeWidth, mazeHeight),
                  painter: SlidingMazePainter(
                    controller: _controller,
                    wallColor: c.wallColor,
                    ballColor: c.ballColor,
                    goalColor: c.goalColor,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar(AppColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _horizontalPadding, 8, _horizontalPadding, 40,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Text(
              'HOME',
              style: TextStyle(
                fontFamily: 'SulphurPoint',
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: c.primaryText,
              ),
            ),
          ),
          GestureDetector(
            onTap: _togglePause,
            child: Text(
              _paused ? 'RESUME' : 'PAUSE',
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

  Widget _buildPauseOverlay(AppColors c) {
    return GestureDetector(
      onTap: _togglePause,
      child: Container(
        color: c.pauseOverlay,
        child: Center(
          child: Text(
            'PAUSED',
            style: TextStyle(
              fontFamily: 'SulphurPoint',
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: c.primaryText,
              letterSpacing: 6,
            ),
          ),
        ),
      ),
    );
  }
}
