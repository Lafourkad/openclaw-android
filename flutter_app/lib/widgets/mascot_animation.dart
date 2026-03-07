import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'mascot_painter.dart';

/// Rich animated mascot during loading screens.
/// Vector-drawn robot with animated eyes, claws, legs, antennae.
/// Shake the phone to make it fall and get angry!
class MascotAnimation extends StatefulWidget {
  final double size;
  const MascotAnimation({super.key, this.size = 120});

  @override
  State<MascotAnimation> createState() => _MascotAnimationState();
}

class _MascotAnimationState extends State<MascotAnimation>
    with TickerProviderStateMixin {
  final _rng = Random();

  // Mascot state
  double _x = -150, _y = 0, _scale = 1.0, _rotation = 0;
  double _viewAngle = 0, _blink = 0, _clawOpen = 0.3;
  double _leftLeg = 0, _rightLeg = 0, _antennaWobble = 0;
  double _bodyBounce = 0, _opacity = 0, _mood = 0;
  Offset _eyeLook = Offset.zero;
  bool _disposed = false;
  bool _fell = false; // shake-triggered fall

  static const _shakeChannel = EventChannel('com.openclaw.android/shake');
  StreamSubscription? _shakeSub;
  DateTime _lastShake = DateTime(2000);

  @override
  void initState() {
    super.initState();
    _setupShakeDetection();
    _startSequence();
  }

  void _setupShakeDetection() {
    try {
      _shakeSub = _shakeChannel.receiveBroadcastStream().listen((event) {
        if (_disposed) return;
        if (DateTime.now().difference(_lastShake).inSeconds > 4) {
          _lastShake = DateTime.now();
          _triggerFall();
        }
      });
    } catch (_) {} // Channel not available
  }

  Future<void> _triggerFall() async {
    if (_fell || _disposed) return;
    _fell = true;

    // Fall down!
    await _animateTo(
      y: 120, rotation: _rotation + 0.5, bodyBounce: 20,
      ms: 300, curve: Curves.easeIn,
    );
    // Bounce on ground
    await _animateTo(y: 80, bodyBounce: -10, ms: 150, curve: Curves.easeOut);
    await _animateTo(y: 100, bodyBounce: 0, ms: 100);

    // Get angry!
    await _animateTo(
      viewAngle: 0, mood: -1, rotation: 0,
      eyeLook: const Offset(0, -0.8),
      ms: 300,
    );

    // Shake head angrily
    for (int i = 0; i < 4; i++) {
      if (_disposed) return;
      await _animateTo(antennaWobble: 1, bodyTilt: 0.1, ms: 80);
      await _animateTo(antennaWobble: -1, bodyTilt: -0.1, ms: 80);
    }
    await _animateTo(antennaWobble: 0, bodyTilt: 0, ms: 100);

    // Angry claw snaps
    for (int i = 0; i < 3; i++) {
      if (_disposed) return;
      await _animateTo(clawOpen: 1, ms: 60);
      await _animateTo(clawOpen: 0, ms: 60);
    }

    // Huff — look away
    await _wait(500);
    await _animateTo(
      eyeLook: const Offset(-1, 0), mood: -0.5,
      ms: 300,
    );
    await _wait(800);

    // Slowly calm down
    await _animateTo(mood: 0, eyeLook: Offset.zero, ms: 600);
    await _wait(300);

    // Get back up and resume
    _fell = false;
  }

  @override
  void dispose() {
    _disposed = true;
    _shakeSub?.cancel();
    super.dispose();
  }

  // --- Animation primitives ---

  Future<void> _wait(int ms) async {
    if (_disposed) return;
    await Future.delayed(Duration(milliseconds: ms));
  }

  Future<void> _animateTo({
    double? x, double? y, double? scale, double? rotation,
    double? viewAngle, Offset? eyeLook, double? blink,
    double? clawOpen, double? leftLeg, double? rightLeg,
    double? antennaWobble, double? bodyBounce, double? bodyTilt,
    double? opacity, double? mood,
    required int ms, Curve curve = Curves.easeInOut,
  }) async {
    if (_disposed || !mounted) return;
    final s = _SavedState(
      _x, _y, _scale, _rotation, _viewAngle, _eyeLook, _blink,
      _clawOpen, _leftLeg, _rightLeg, _antennaWobble, _bodyBounce,
      0, _opacity, _mood,
    );
    final eX = x ?? _x, eY = y ?? _y, eS = scale ?? _scale;
    final eR = rotation ?? _rotation, eV = viewAngle ?? _viewAngle;
    final eE = eyeLook ?? _eyeLook, eB = blink ?? _blink;
    final eC = clawOpen ?? _clawOpen, eLL = leftLeg ?? _leftLeg;
    final eRL = rightLeg ?? _rightLeg, eA = antennaWobble ?? _antennaWobble;
    final eBo = bodyBounce ?? _bodyBounce;
    final eBt = bodyTilt ?? 0;
    final eO = opacity ?? _opacity, eM = mood ?? _mood;

    final steps = max(1, (ms / 16).ceil());
    for (int i = 0; i <= steps; i++) {
      if (_disposed || !mounted) return;
      if (_fell && x == null && y == null && rotation == null) return; // Interrupt for fall
      final t = curve.transform((i / steps).clamp(0.0, 1.0));
      setState(() {
        _x = _lerp(s.x, eX, t); _y = _lerp(s.y, eY, t);
        _scale = _lerp(s.scale, eS, t); _rotation = _lerp(s.rotation, eR, t);
        _viewAngle = _lerp(s.viewAngle, eV, t);
        _eyeLook = Offset(_lerp(s.eyeLook.dx, eE.dx, t), _lerp(s.eyeLook.dy, eE.dy, t));
        _blink = _lerp(s.blink, eB, t); _clawOpen = _lerp(s.clawOpen, eC, t);
        _leftLeg = _lerp(s.leftLeg, eLL, t); _rightLeg = _lerp(s.rightLeg, eRL, t);
        _antennaWobble = _lerp(s.antennaWobble, eA, t);
        _bodyBounce = _lerp(s.bodyBounce, eBo, t);
        _opacity = _lerp(s.opacity, eO, t); _mood = _lerp(s.mood, eM, t);
      });
      await Future.delayed(const Duration(milliseconds: 16));
    }
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  Future<void> _doBlink() async {
    await _animateTo(blink: 1, ms: 80, curve: Curves.easeIn);
    await _animateTo(blink: 0, ms: 80, curve: Curves.easeOut);
  }

  Future<void> _doWalk(double fromX, double toX, int ms) async {
    final steps = max(1, (ms / 200).ceil());
    final dx = (toX - fromX) / steps;
    for (int i = 0; i < steps; i++) {
      if (_disposed || _fell) return;
      final leg = (i % 2 == 0) ? 1.0 : -1.0;
      await _animateTo(
        x: fromX + dx * i, leftLeg: leg, rightLeg: -leg,
        bodyBounce: leg * 2, antennaWobble: leg * 0.5,
        ms: 180, curve: Curves.linear,
      );
    }
    await _animateTo(x: toX, leftLeg: 0, rightLeg: 0, bodyBounce: 0, ms: 100);
  }

  Future<void> _doClawSnap({int count = 2}) async {
    for (int i = 0; i < count; i++) {
      if (_disposed || _fell) return;
      await _animateTo(clawOpen: 1, ms: 120, curve: Curves.easeOut);
      await _animateTo(clawOpen: 0, ms: 80, curve: Curves.easeIn);
      await _wait(80);
    }
    await _animateTo(clawOpen: 0.3, ms: 150);
  }

  Future<void> _lookAround() async {
    await _animateTo(eyeLook: const Offset(-1, 0), ms: 300);
    await _wait(300 + _rng.nextInt(300));
    await _animateTo(eyeLook: const Offset(1, 0), ms: 400);
    await _wait(300 + _rng.nextInt(300));
    await _animateTo(eyeLook: Offset.zero, ms: 200);
  }

  Future<void> _doJump() async {
    await _animateTo(bodyBounce: 5, ms: 100, curve: Curves.easeIn); // crouch
    await _animateTo(bodyBounce: -25, leftLeg: 0.5, rightLeg: 0.5, ms: 200, curve: Curves.easeOut);
    await _animateTo(bodyBounce: 0, leftLeg: 0, rightLeg: 0, ms: 300, curve: Curves.bounceOut);
  }

  Future<void> _doDance() async {
    for (int i = 0; i < 4; i++) {
      if (_disposed || _fell) return;
      await _animateTo(
        bodyBounce: -8, clawOpen: 0.8, antennaWobble: 0.8,
        leftLeg: 1, rightLeg: -1, mood: 0.8,
        ms: 200,
      );
      await _animateTo(
        bodyBounce: 0, clawOpen: 0.2, antennaWobble: -0.8,
        leftLeg: -1, rightLeg: 1,
        ms: 200,
      );
    }
    await _animateTo(
      bodyBounce: 0, clawOpen: 0.3, antennaWobble: 0,
      leftLeg: 0, rightLeg: 0, mood: 0,
      ms: 200,
    );
  }

  Future<void> _doSpin() async {
    final startRot = _rotation;
    await _animateTo(rotation: startRot + pi * 2, scale: _scale * 0.8, ms: 600, curve: Curves.easeInOut);
    await _animateTo(rotation: startRot, scale: _scale / 0.8, ms: 100);
  }

  Future<void> _doScaredRetreat(double toX) async {
    await _animateTo(
      eyeLook: const Offset(0, 0.5), scale: 0.7, bodyBounce: -5,
      ms: 150, curve: Curves.easeIn,
    );
    await _animateTo(
      x: toX, scale: 0.6, opacity: 0.8,
      ms: 250, curve: Curves.easeIn,
    );
  }

  // --- Animation sequences (randomly picked) ---

  Future<void> _seqPeekLeft() async {
    _viewAngle = 1; _x = -160; _y = _rng.nextDouble() * 40 - 20;
    _scale = 0.9; _opacity = 1; _rotation = 0; _mood = 0;
    if (mounted) setState(() {});

    await _animateTo(x: -20, viewAngle: 1, ms: 1200, curve: Curves.easeOutCubic);
    await _animateTo(viewAngle: 0, eyeLook: Offset(_rng.nextDouble() - 0.5, -0.3), ms: 400);
    await _wait(500);
    await _doBlink();
    if (_rng.nextBool()) await _lookAround();
    if (_rng.nextBool()) await _doClawSnap();
    await _wait(400);
    await _doScaredRetreat(-180);
  }

  Future<void> _seqPeekRight() async {
    _viewAngle = -1; _x = 200; _y = _rng.nextDouble() * 40 - 20;
    _scale = 0.85; _opacity = 1; _rotation = 0; _mood = 0;
    if (mounted) setState(() {});

    await _animateTo(x: 40, viewAngle: -1, ms: 1000, curve: Curves.easeOutCubic);
    await _animateTo(viewAngle: 0, ms: 300);
    await _doBlink();
    await _lookAround();
    await _wait(300);
    await _doScaredRetreat(220);
  }

  Future<void> _seqWalkAcross() async {
    final goRight = _rng.nextBool();
    final startX = goRight ? -140.0 : 140.0;
    final endX = goRight ? 180.0 : -180.0;
    _x = startX; _y = 30; _scale = 0.9; _opacity = 1;
    _viewAngle = goRight ? 1 : -1; _rotation = 0; _mood = 0;
    if (mounted) setState(() {});

    await _animateTo(opacity: 1, ms: 200);
    await _doWalk(startX, endX, 3000 + _rng.nextInt(1000));
    await _animateTo(opacity: 0, ms: 200);
  }

  Future<void> _seqGrowBig() async {
    _x = 0; _y = 10; _scale = 0.5; _opacity = 1; _viewAngle = 0; _rotation = 0; _mood = 0;
    if (mounted) setState(() {});

    await _animateTo(opacity: 1, scale: 0.5, ms: 200);
    await _animateTo(scale: 1.6, eyeLook: const Offset(0, -0.3), ms: 1000, curve: Curves.easeInOutCubic);
    await _wait(500);
    await _animateTo(blink: 1, ms: 300);
    await _wait(200);
    await _animateTo(blink: 0, ms: 300);
    await _wait(500);
    if (_rng.nextBool()) await _doClawSnap(count: 3);
    if (_rng.nextBool()) await _doDance();
    await _wait(300);

    // Shy retreat
    await _animateTo(
      eyeLook: const Offset(-0.8, 0.8), scale: 0.4,
      ms: 400, curve: Curves.easeIn,
    );
    await _animateTo(y: 200, opacity: 0, scale: 0.3, ms: 500, curve: Curves.easeIn);
  }

  Future<void> _seqDropFromTop() async {
    _x = _rng.nextDouble() * 80 - 40; _y = -180; _scale = 1.0;
    _rotation = pi; _opacity = 1; _viewAngle = 0; _mood = 0;
    if (mounted) setState(() {});

    await _animateTo(y: -50, ms: 800, curve: Curves.bounceOut);
    await _lookAround();
    await _doBlink();

    // Gentle swing
    for (int i = 0; i < 3 + _rng.nextInt(3); i++) {
      if (_disposed || _fell) return;
      final swing = 0.08 + _rng.nextDouble() * 0.05;
      await _animateTo(rotation: pi + swing, x: _x + 8, antennaWobble: 0.5, ms: 600);
      await _animateTo(rotation: pi - swing, x: _x - 8, antennaWobble: -0.5, ms: 600);
    }

    // Leave
    await _animateTo(y: -200, opacity: 0, ms: 500, curve: Curves.easeIn);
  }

  Future<void> _seqDanceParty() async {
    _x = 0; _y = 20; _scale = 1.1; _opacity = 1; _viewAngle = 0; _rotation = 0; _mood = 1;
    if (mounted) setState(() {});

    await _animateTo(opacity: 1, ms: 200);
    await _doDance();
    await _doJump();
    await _doDance();
    await _doSpin();
    await _animateTo(mood: 0, ms: 200);
    await _wait(300);
    await _animateTo(opacity: 0, y: 200, ms: 400, curve: Curves.easeIn);
  }

  Future<void> _seqSneakPeek() async {
    // Slowly rise from bottom
    _x = _rng.nextDouble() * 60 - 30; _y = 150; _scale = 0.8;
    _opacity = 1; _viewAngle = 0; _rotation = 0; _mood = 0;
    if (mounted) setState(() {});

    await _animateTo(y: 50, eyeLook: const Offset(0, -1), ms: 1500, curve: Curves.easeOutCubic);
    await _wait(800);
    await _doBlink();
    await _doBlink();
    await _wait(400);

    // Slowly sink back
    await _animateTo(y: 150, opacity: 0, ms: 1200, curve: Curves.easeIn);
  }

  Future<void> _seqZoomBy() async {
    // Zoom across screen super fast
    _x = -200; _y = _rng.nextDouble() * 60 - 30; _scale = 0.7;
    _opacity = 1; _viewAngle = 1; _rotation = 0.15; _mood = 1;
    if (mounted) setState(() {});

    await _animateTo(x: 250, ms: 600, curve: Curves.linear);
    await _wait(800);
    // Come back the other way
    _x = 250; _viewAngle = -1; _rotation = -0.15;
    if (mounted) setState(() {});
    await _animateTo(x: -200, ms: 500, curve: Curves.linear);
    _opacity = 0;
    if (mounted) setState(() {});
  }

  Future<void> _seqCuriousStare() async {
    _x = 0; _y = 0; _scale = 1.2; _opacity = 0; _viewAngle = 0; _rotation = 0; _mood = 0;
    if (mounted) setState(() {});

    // Fade in
    await _animateTo(opacity: 1, ms: 800);
    // Follow cursor (eyes track around)
    for (int i = 0; i < 6; i++) {
      if (_disposed || _fell) return;
      final dx = cos(i * pi / 3) * 0.8;
      final dy = sin(i * pi / 3) * 0.6;
      await _animateTo(eyeLook: Offset(dx, dy), ms: 500);
      await _wait(200);
    }
    await _animateTo(eyeLook: Offset.zero, ms: 300);
    await _doBlink();
    await _wait(500);
    // Fade out
    await _animateTo(opacity: 0, ms: 600);
  }

  // --- Main sequence ---

  Future<void> _startSequence() async {
    await _wait(1500);

    // All available animations (dropFromTop removed — upside down looks bad)
    final sequences = [
      _seqPeekLeft,
      _seqPeekRight,
      _seqWalkAcross,
      _seqGrowBig,
      _seqDanceParty,
      _seqSneakPeek,
      _seqZoomBy,
      _seqCuriousStare,
    ];

    // Always start with peek from left
    await _seqPeekLeft();

    while (!_disposed && mounted) {
      await _wait(1000 + _rng.nextInt(2000)); // Random pause between acts

      if (_fell) {
        // Wait for fall animation to finish
        await _wait(3000);
        _fell = false;
        continue;
      }

      // Pick a random sequence
      final seq = sequences[_rng.nextInt(sequences.length)];
      await seq();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final areaW = constraints.maxWidth > 0
            ? constraints.maxWidth : MediaQuery.of(context).size.width;
        final areaH = constraints.maxHeight > 0
            ? constraints.maxHeight : MediaQuery.of(context).size.height;
        final s = widget.size * _scale;
        final centerX = areaW / 2 + _x;
        final centerY = areaH / 2 + _y;

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: centerX - s / 2,
              top: centerY - s / 2,
              width: s,
              height: s,
              child: Transform.rotate(
                angle: _rotation,
                child: Opacity(
                  opacity: _opacity.clamp(0.0, 1.0),
                  child: CustomPaint(
                    size: Size(s, s),
                    painter: MascotPainter(
                      viewAngle: _viewAngle,
                      eyeLook: _eyeLook,
                      blink: _blink,
                      clawOpen: _clawOpen,
                      leftLeg: _leftLeg,
                      rightLeg: _rightLeg,
                      antennaWobble: _antennaWobble,
                      bodyBounce: _bodyBounce,
                      mood: _mood,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SavedState {
  final double x, y, scale, rotation, viewAngle;
  final Offset eyeLook;
  final double blink, clawOpen, leftLeg, rightLeg;
  final double antennaWobble, bodyBounce, bodyTilt, opacity, mood;
  _SavedState(this.x, this.y, this.scale, this.rotation, this.viewAngle,
      this.eyeLook, this.blink, this.clawOpen, this.leftLeg, this.rightLeg,
      this.antennaWobble, this.bodyBounce, this.bodyTilt, this.opacity, this.mood);
}
