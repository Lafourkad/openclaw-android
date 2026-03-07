import 'dart:math';
import 'package:flutter/material.dart';

/// Draws the OpenClaw mascot robot with animatable parameters.
///
/// The robot has: antennae, eyes, body, crab-claw arms, feet.
/// All parts are parameterized for animation.
class MascotPainter extends CustomPainter {
  /// 0=front, 1=right side, -1=left side, 2=back
  final double viewAngle;
  final Offset eyeLook;
  final double blink;
  final double clawOpen;
  final double leftLeg;
  final double rightLeg;
  final double antennaWobble;
  final double bodyBounce;
  final double bodyTilt;
  final double opacity;
  /// 0=neutral, 1=happy, -1=angry/annoyed
  final double mood;

  const MascotPainter({
    this.viewAngle = 0,
    this.eyeLook = Offset.zero,
    this.blink = 0,
    this.clawOpen = 0.3,
    this.leftLeg = 0,
    this.rightLeg = 0,
    this.antennaWobble = 0,
    this.bodyBounce = 0,
    this.bodyTilt = 0,
    this.opacity = 1.0,
    this.mood = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = min(size.width, size.height);
    final cx = size.width / 2;
    final cy = size.height / 2;

    canvas.save();
    canvas.translate(cx, cy + bodyBounce);
    canvas.rotate(bodyTilt);

    final paint = Paint()..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.02
      ..strokeCap = StrokeCap.round;

    final bodyColor = Color.fromRGBO(220, 50, 47, opacity);
    final darkColor = Color.fromRGBO(180, 35, 35, opacity);
    final eyeWhite = Color.fromRGBO(255, 255, 255, opacity);
    final eyePupil = Color.fromRGBO(20, 20, 20, opacity);
    final highlight = Color.fromRGBO(255, 120, 100, opacity);

    final u = s / 100;

    if (viewAngle.abs() < 0.5) {
      _drawFront(canvas, u, paint, strokePaint, bodyColor, darkColor,
          eyeWhite, eyePupil, highlight);
    } else if (viewAngle > 1.5) {
      _drawBack(canvas, u, paint, strokePaint, bodyColor, darkColor, highlight);
    } else {
      _drawSide(canvas, u, paint, strokePaint, bodyColor, darkColor,
          eyeWhite, eyePupil, highlight, viewAngle > 0);
    }

    canvas.restore();
  }

  void _drawFront(Canvas canvas, double u, Paint paint, Paint strokePaint,
      Color body, Color dark, Color eyeW, Color eyeP, Color highlight) {

    // --- Antennae (close at base, spread outward at top) ---
    strokePaint.color = body;
    strokePaint.strokeWidth = u * 2.5;
    // Left antenna: base at -8, tip at -14 (spreads outward)
    canvas.drawLine(
      Offset(-8 * u, -28 * u),
      Offset(-14 * u + antennaWobble * 3 * u, -42 * u),
      strokePaint,
    );
    paint.color = body;
    canvas.drawCircle(
      Offset(-14 * u + antennaWobble * 3 * u, -42 * u), 3 * u, paint);
    // Right antenna: base at +8, tip at +14 (spreads outward)
    canvas.drawLine(
      Offset(8 * u, -28 * u),
      Offset(14 * u + antennaWobble * 3 * u, -42 * u),
      strokePaint,
    );
    canvas.drawCircle(
      Offset(14 * u + antennaWobble * 3 * u, -42 * u), 3 * u, paint);

    // --- Legs ---
    paint.color = dark;
    final legW = 10 * u;
    final legH = 12 * u;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(-12 * u + leftLeg * 4 * u, 28 * u),
          width: legW, height: legH,
        ),
        Radius.circular(3 * u),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(12 * u + rightLeg * 4 * u, 28 * u),
          width: legW, height: legH,
        ),
        Radius.circular(3 * u),
      ),
      paint,
    );

    // --- Claw arms ---
    _drawClawFront(canvas, u, paint, strokePaint, body, dark, true);
    _drawClawFront(canvas, u, paint, strokePaint, body, dark, false);

    // --- Body ---
    paint.color = body;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 44 * u, height: 38 * u),
        Radius.circular(10 * u),
      ), paint);

    // Highlight
    paint.color = highlight;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(-6 * u, -6 * u), width: 12 * u, height: 8 * u),
        Radius.circular(4 * u),
      ), paint);

    // --- Eyes ---
    _drawEyes(canvas, u, paint, eyeW, eyeP, false);

    // --- Mouth ---
    _drawMouth(canvas, u, strokePaint, dark);
  }

  void _drawEyes(Canvas canvas, double u, Paint paint, Color eyeW, Color eyeP, bool singleEye) {
    final eyeRadius = 7 * u;
    final pupilRadius = 3.5 * u;
    final blinkHeight = (eyeRadius * 2 * (1 - blink)).clamp(u * 0.5, eyeRadius * 2);

    final eyes = singleEye ? [0.0] : [-1.0, 1.0];
    final spacing = singleEye ? 0.0 : 11 * u;

    for (final side in eyes) {
      final ex = side * spacing;
      final ey = -4 * u;

      paint.color = eyeW;
      canvas.save();
      canvas.translate(ex, ey);

      // Eye white
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: eyeRadius * 2, height: blinkHeight),
        paint,
      );

      // Pupil
      if (blink < 0.7) {
        paint.color = eyeP;
        final px = eyeLook.dx * 3 * u;
        final py = eyeLook.dy * 2 * u;
        canvas.drawCircle(Offset(px, py), pupilRadius * (1 - blink * 0.5), paint);

        // Pupil highlight
        paint.color = Color.fromRGBO(255, 255, 255, (1 - blink) * 0.8);
        canvas.drawCircle(Offset(px + 1.5 * u, py - 1.5 * u), 1.5 * u, paint);
      }
      canvas.restore();
    }

    // Angry eyebrows
    if (mood < -0.3) {
      final strokeP = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * 2.5
        ..strokeCap = StrokeCap.round
        ..color = Color.fromRGBO(20, 20, 20, opacity);
      if (!singleEye) {
        // Left eyebrow — angled down inward
        canvas.drawLine(
          Offset(-18 * u, -16 * u), Offset(-5 * u, -12 * u), strokeP);
        // Right eyebrow
        canvas.drawLine(
          Offset(18 * u, -16 * u), Offset(5 * u, -12 * u), strokeP);
      } else {
        canvas.drawLine(
          Offset(-8 * u, -16 * u), Offset(8 * u, -12 * u), strokeP);
      }
    }
  }

  void _drawMouth(Canvas canvas, double u, Paint strokePaint, Color dark) {
    strokePaint.color = dark;
    strokePaint.strokeWidth = u * 1.5;
    strokePaint.style = PaintingStyle.stroke;
    if (mood > 0.3) {
      // Happy — smile arc
      final path = Path()
        ..moveTo(-7 * u, 7 * u)
        ..quadraticBezierTo(0, 13 * u, 7 * u, 7 * u);
      canvas.drawPath(path, strokePaint);
    } else if (mood < -0.3) {
      // Angry — frown
      final path = Path()
        ..moveTo(-7 * u, 11 * u)
        ..quadraticBezierTo(0, 5 * u, 7 * u, 11 * u);
      canvas.drawPath(path, strokePaint);
    } else {
      // Neutral — straight line
      canvas.drawLine(Offset(-6 * u, 8 * u), Offset(6 * u, 8 * u), strokePaint);
    }
  }

  void _drawClawFront(Canvas canvas, double u, Paint paint, Paint strokePaint,
      Color body, Color dark, bool isLeft) {
    final side = isLeft ? -1.0 : 1.0;
    final armX = side * 28 * u;
    final armY = -2 * u;

    // Arm segment
    strokePaint.color = body;
    strokePaint.strokeWidth = u * 5;
    strokePaint.style = PaintingStyle.stroke;
    canvas.drawLine(Offset(side * 22 * u, armY), Offset(armX, armY), strokePaint);

    // Claw pincers
    final open = clawOpen * 0.4;
    canvas.save();
    canvas.translate(armX, armY);
    strokePaint.strokeWidth = u * 3.5;
    strokePaint.color = dark;

    final upperAngle = side > 0 ? -0.3 - open : pi + 0.3 + open;
    canvas.drawLine(Offset.zero,
      Offset(cos(upperAngle) * 12 * u, sin(upperAngle) * 12 * u), strokePaint);
    final lowerAngle = side > 0 ? 0.3 + open : pi - 0.3 - open;
    canvas.drawLine(Offset.zero,
      Offset(cos(lowerAngle) * 12 * u, sin(lowerAngle) * 12 * u), strokePaint);

    canvas.restore();
  }

  void _drawSide(Canvas canvas, double u, Paint paint, Paint strokePaint,
      Color body, Color dark, Color eyeW, Color eyeP, Color highlight,
      bool facingRight) {
    final dir = facingRight ? 1.0 : -1.0;

    // --- Antenna (one visible, spreads outward) ---
    strokePaint.color = body;
    strokePaint.strokeWidth = u * 2.5;
    strokePaint.style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(dir * 4 * u, -28 * u),
      Offset(dir * 10 * u + antennaWobble * 3 * u, -42 * u),
      strokePaint,
    );
    paint.color = body;
    canvas.drawCircle(
      Offset(dir * 10 * u + antennaWobble * 3 * u, -42 * u), 3 * u, paint);

    // --- Back leg (further, darker) ---
    paint.color = dark.withOpacity(dark.opacity * 0.6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(-dir * 2 * u + rightLeg * 4 * u, 28 * u),
          width: 9 * u, height: 12 * u),
        Radius.circular(3 * u),
      ), paint);

    // --- Body (narrower from side) ---
    paint.color = body;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 30 * u, height: 38 * u),
        Radius.circular(10 * u),
      ), paint);

    // Highlight
    paint.color = highlight;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(dir * 4 * u, -6 * u), width: 8 * u, height: 6 * u),
        Radius.circular(3 * u),
      ), paint);

    // --- Front leg ---
    paint.color = dark;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(dir * 2 * u + leftLeg * 4 * u, 28 * u),
          width: 10 * u, height: 12 * u),
        Radius.circular(3 * u),
      ), paint);

    // --- Eye (single, on the visible side) ---
    final eyeX = dir * 6 * u;
    paint.color = eyeW;
    final blinkH = (7 * u * 2 * (1 - blink)).clamp(u * 0.5, 14.0 * u);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(eyeX, -4 * u), width: 12 * u, height: blinkH),
      paint,
    );
    if (blink < 0.7) {
      paint.color = eyeP;
      canvas.drawCircle(
        Offset(eyeX + eyeLook.dx * 2 * u, -4 * u + eyeLook.dy * 2 * u),
        3.5 * u * (1 - blink * 0.5), paint);
      paint.color = Color.fromRGBO(255, 255, 255, (1 - blink) * 0.8);
      canvas.drawCircle(
        Offset(eyeX + eyeLook.dx * 2 * u + 1 * u, -4 * u - 1 * u),
        1.2 * u, paint);
    }
    // Angry eyebrow on side
    if (mood < -0.3) {
      final brow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * 2.5
        ..strokeCap = StrokeCap.round
        ..color = Color.fromRGBO(20, 20, 20, opacity);
      canvas.drawLine(
        Offset(eyeX - 6 * u, -14 * u),
        Offset(eyeX + 6 * u, -11 * u), brow);
    }

    // --- Front arm + claw (small, tucked close to body) ---
    strokePaint.color = body;
    strokePaint.strokeWidth = u * 4;
    strokePaint.style = PaintingStyle.stroke;
    // Short arm stub visible from side
    final armStartX = dir * 13 * u;
    final armEndX = dir * 19 * u;
    canvas.drawLine(
      Offset(armStartX, 2 * u), Offset(armEndX, 0), strokePaint);

    // Tiny claw tip
    strokePaint.color = dark;
    strokePaint.strokeWidth = u * 2.5;
    final open = clawOpen * 0.2;
    canvas.drawLine(
      Offset(armEndX, 0),
      Offset(armEndX + dir * 5 * u, -3 * u - open * 3 * u),
      strokePaint);
    canvas.drawLine(
      Offset(armEndX, 0),
      Offset(armEndX + dir * 5 * u, 3 * u + open * 3 * u),
      strokePaint);

    // --- Mouth (offset to visible side, smaller) ---
    strokePaint.color = dark;
    strokePaint.strokeWidth = u * 1.5;
    strokePaint.style = PaintingStyle.stroke;
    final mouthX = dir * 4 * u;
    if (mood > 0.3) {
      final path = Path()
        ..moveTo(mouthX - 4 * u, 7 * u)
        ..quadraticBezierTo(mouthX, 11 * u, mouthX + 4 * u, 7 * u);
      canvas.drawPath(path, strokePaint);
    } else if (mood < -0.3) {
      final path = Path()
        ..moveTo(mouthX - 4 * u, 10 * u)
        ..quadraticBezierTo(mouthX, 6 * u, mouthX + 4 * u, 10 * u);
      canvas.drawPath(path, strokePaint);
    } else {
      canvas.drawLine(
        Offset(mouthX - 4 * u, 8 * u),
        Offset(mouthX + 4 * u, 8 * u), strokePaint);
    }
  }

  void _drawBack(Canvas canvas, double u, Paint paint, Paint strokePaint,
      Color body, Color dark, Color highlight) {

    // --- Antennae (close at base, spread outward at top) ---
    strokePaint.color = body;
    strokePaint.strokeWidth = u * 2.5;
    strokePaint.style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(-8 * u, -28 * u),
      Offset(-14 * u + antennaWobble * 3 * u, -42 * u),
      strokePaint);
    paint.color = body;
    canvas.drawCircle(
      Offset(-14 * u + antennaWobble * 3 * u, -42 * u), 3 * u, paint);
    canvas.drawLine(
      Offset(8 * u, -28 * u),
      Offset(14 * u + antennaWobble * 3 * u, -42 * u),
      strokePaint);
    canvas.drawCircle(
      Offset(14 * u + antennaWobble * 3 * u, -42 * u), 3 * u, paint);

    // --- Legs ---
    paint.color = dark;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(-12 * u + leftLeg * 4 * u, 28 * u),
          width: 10 * u, height: 12 * u),
        Radius.circular(3 * u),
      ), paint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(12 * u + rightLeg * 4 * u, 28 * u),
          width: 10 * u, height: 12 * u),
        Radius.circular(3 * u),
      ), paint);

    // --- Body ---
    paint.color = body;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 44 * u, height: 38 * u),
        Radius.circular(10 * u),
      ), paint);

    // Back panel
    strokePaint.color = dark;
    strokePaint.strokeWidth = u * 1.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(0, 2 * u), width: 20 * u, height: 16 * u),
        Radius.circular(4 * u),
      ), strokePaint);
  }

  @override
  bool shouldRepaint(MascotPainter old) =>
      viewAngle != old.viewAngle || eyeLook != old.eyeLook ||
      blink != old.blink || clawOpen != old.clawOpen ||
      leftLeg != old.leftLeg || rightLeg != old.rightLeg ||
      antennaWobble != old.antennaWobble || bodyBounce != old.bodyBounce ||
      bodyTilt != old.bodyTilt || opacity != old.opacity || mood != old.mood;
}
