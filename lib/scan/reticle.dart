import 'package:flutter/material.dart';

import '../theme/tokens.dart';

enum ReticleState { scanning, locked, rejected }

Color reticleColor(ReticleState s) => switch (s) {
      ReticleState.scanning => AppTokens.lime,
      ReticleState.locked => AppTokens.amber,
      ReticleState.rejected => AppTokens.alertRed,
    };

/// The one signature element: a dimmed scrim with a clear rounded scan window,
/// corner brackets, and a sweeping line while scanning. Brackets/sweep follow
/// [reticleColor]; the sweep stops on lock/reject.
class Reticle extends StatefulWidget {
  const Reticle({super.key, required this.state});

  final ReticleState state;

  @override
  State<Reticle> createState() => _ReticleState();
}

class _ReticleState extends State<Reticle> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scanning = widget.state == ReticleState.scanning;
    return AnimatedBuilder(
      animation: _sweep,
      builder: (context, _) => CustomPaint(
        size: Size.infinite,
        painter: _ReticlePainter(
          color: reticleColor(widget.state),
          sweep: scanning ? _sweep.value : null,
        ),
      ),
    );
  }
}

class _ReticlePainter extends CustomPainter {
  _ReticlePainter({required this.color, required this.sweep});

  final Color color;
  final double? sweep; // 0..1 while scanning, null when stopped

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide * 0.70;
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2.2),
      width: side,
      height: side,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(22));

    // Dimmed scrim with the scan window cut out.
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawColor(Colors.black.withValues(alpha: 0.55), BlendMode.srcOver);
    canvas.drawRRect(rrect, Paint()..blendMode = BlendMode.clear);
    canvas.restore();

    // Corner brackets.
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const arm = 28.0;
    void corner(Offset c, Offset dx, Offset dy) {
      canvas.drawLine(c, c + dx, stroke);
      canvas.drawLine(c, c + dy, stroke);
    }

    corner(rect.topLeft, const Offset(arm, 0), const Offset(0, arm));
    corner(rect.topRight, const Offset(-arm, 0), const Offset(0, arm));
    corner(rect.bottomLeft, const Offset(arm, 0), const Offset(0, -arm));
    corner(rect.bottomRight, const Offset(-arm, 0), const Offset(0, -arm));

    // Sweep line.
    if (sweep != null) {
      final y = rect.top + rect.height * sweep!;
      final sweepPaint = Paint()
        ..shader = LinearGradient(
          colors: [color.withValues(alpha: 0), color, color.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(rect.left, y - 1, rect.width, 2))
        ..strokeWidth = 2;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), sweepPaint);
    }
  }

  @override
  bool shouldRepaint(_ReticlePainter old) =>
      old.color != color || old.sweep != sweep;
}
