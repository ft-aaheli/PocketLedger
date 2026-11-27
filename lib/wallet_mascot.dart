import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

class WalletMascot extends StatelessWidget {
  const WalletMascot({super.key, this.celebrating = false});

  final bool celebrating;

  @override
  Widget build(BuildContext context) {
    final mascot = CustomPaint(
      size: Size.square(celebrating ? 40 : 52),
      painter: _WalletPainter(celebrating),
    );
    if (MediaQuery.disableAnimationsOf(context)) return mascot;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: celebrating ? 680 : 850),
      child: mascot,
      builder: (context, progress, child) {
        final lift = math.sin(math.pi * progress);
        return Transform.translate(
          offset: Offset(
            celebrating ? 0 : -3 * lift,
            -(celebrating ? 8 : 3) * lift,
          ),
          child: Transform.rotate(angle: -.12 * lift, child: child),
        );
      },
    );
  }
}

class _WalletPainter extends CustomPainter {
  const _WalletPainter(this.celebrating);

  final bool celebrating;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64);
    final ink = Paint()..color = const Color(0xFF17243A);
    final paper = Paint()..color = const Color(0xFFE5F6F7);
    final white = Paint()..color = Colors.white;
    final line = Paint()
      ..color = const Color(0xFF17243A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(const Offset(32, 32), 30, paper);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(19, 12, 24, 27),
        const Radius.circular(4),
      ),
      ink,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(21, 14, 20, 24),
        const Radius.circular(3),
      ),
      white,
    );
    canvas.drawLine(const Offset(26, 19), const Offset(36, 19), line);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(9, 23, 45, 28),
        const Radius.circular(8),
      ),
      ink,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(44, 31, 13, 11),
        const Radius.circular(4),
      ),
      ink,
    );
    canvas.drawCircle(const Offset(50, 36.5), 1.6, paper);

    line.color = Colors.white;
    for (final eye in [22.0, 37.0]) {
      if (celebrating) {
        canvas.drawArc(
          Rect.fromLTWH(eye - 2.5, 31, 5, 6),
          math.pi,
          math.pi,
          false,
          line,
        );
      } else {
        canvas.drawCircle(Offset(eye, 34), 2.2, white);
      }
    }
    canvas.drawArc(const Rect.fromLTWH(25, 35, 9, 8), 0, math.pi, false, line);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WalletPainter oldDelegate) =>
      oldDelegate.celebrating != celebrating;
}
