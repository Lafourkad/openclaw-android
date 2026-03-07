import 'package:flutter/material.dart';
import 'mascot_painter.dart';

/// Small static mascot icon for use in AppBar, message bubbles, etc.
/// Optionally does idle eye animation.
class MiniMascot extends StatefulWidget {
  final double size;
  final bool animate;

  const MiniMascot({super.key, this.size = 32, this.animate = false});

  @override
  State<MiniMascot> createState() => _MiniMascotState();
}

class _MiniMascotState extends State<MiniMascot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 4000),
      vsync: this,
    );
    if (widget.animate) _ctrl.repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          size: Size(widget.size, widget.size),
          painter: const MascotPainter(clawOpen: 0.3),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        // Subtle idle: gentle antenna wobble + occasional blink
        final t = _ctrl.value;
        final wobble = 0.3 * (t * 3.14 * 2).clamp(-1.0, 1.0);
        // Blink at ~75% of the cycle
        final blinkT = ((t - 0.75).abs() < 0.03) ? 1.0 : 0.0;

        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            size: Size(widget.size, widget.size),
            painter: MascotPainter(
              clawOpen: 0.3,
              antennaWobble: wobble,
              blink: blinkT,
            ),
          ),
        );
      },
    );
  }
}
