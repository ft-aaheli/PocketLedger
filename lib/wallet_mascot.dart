import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

class WalletMascot extends StatefulWidget {
  const WalletMascot({
    super.key,
    this.celebrating = false,
    this.roaming = false,
  });

  final bool celebrating;
  final bool roaming;

  @override
  State<WalletMascot> createState() => _WalletMascotState();
}

class _WalletMascotState extends State<WalletMascot>
    with SingleTickerProviderStateMixin {
  late final motion = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.roaming ? 3600 : 1050),
  );
  bool? reducedMotion;
  bool greeted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reducedMotion == reduced) return;
    reducedMotion = reduced;
    if (reduced) {
      motion.reset();
    } else if (widget.roaming || widget.celebrating) {
      motion.forward(from: 0);
    }
  }

  void greet() {
    if (reducedMotion == true) {
      setState(() => greeted = !greeted);
    } else {
      motion.forward(from: 0);
    }
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final character = AnimatedBuilder(
      animation: motion,
      builder: (context, _) {
        final progress = motion.value;
        final outbound = progress < .42;
        final walkPhase = outbound
            ? progress / .42
            : ((progress - .74) / .26).clamp(0.0, 1.0);
        final stride = widget.roaming
            ? math.sin(walkPhase * math.pi * (outbound ? 8 : 6))
            : 0.0;
        final travel = widget.roaming && reducedMotion == false
            ? 32 * (outbound ? 1 - walkPhase : walkPhase)
            : 0.0;
        final wavePhase = widget.roaming ? (progress - .42) / .32 : progress;
        final waving = wavePhase > 0 && wavePhase < 1
            ? math.sin(math.pi * wavePhase)
            : 0.0;
        final jump = widget.celebrating
            ? 8 * math.sin(2 * math.pi * progress).abs()
            : widget.roaming
            ? 4 * waving
            : 0.0;
        return Align(
          alignment: Alignment.centerLeft,
          child: Transform.translate(
            offset: Offset(travel, -jump - stride.abs()),
            child: CustomPaint(
              size: Size.square(widget.roaming ? 62 : 46),
              painter: _WalletPainter(
                widget.celebrating,
                stride: stride,
                wave: greeted ? 1 : waving,
                wrist: math.sin(wavePhase * math.pi * 8) * waving,
              ),
            ),
          ),
        );
      },
    );
    if (widget.celebrating) {
      return SizedBox.square(dimension: 46, child: character);
    }
    return Semantics(
      button: true,
      label: 'Wave to the wallet mascot',
      child: InkWell(
        onTap: greet,
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          width: widget.roaming ? 96 : 48,
          height: widget.roaming ? 64 : 48,
          child: character,
        ),
      ),
    );
  }
}

class _WalletPainter extends CustomPainter {
  const _WalletPainter(
    this.celebrating, {
    required this.stride,
    required this.wave,
    required this.wrist,
  });

  final bool celebrating;
  final double stride, wave, wrist;

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
    line.strokeWidth = 3;
    for (final side in [-1.0, 1.0]) {
      final step = stride * side;
      final toe = Offset(32 + side * 11 + step * 4, 56 - math.max(0, step) * 4);
      final leg = Path()
        ..moveTo(32 + side * 9, 46)
        ..quadraticBezierTo(toe.dx - side * 2, 52, toe.dx, toe.dy);
      canvas.drawPath(leg, line);
      canvas.drawOval(
        Rect.fromCenter(
          center: toe + Offset(side * 2, 1),
          width: 12,
          height: 7,
        ),
        ink,
      );

      final lift = celebrating ? 1.0 : (side > 0 ? wave : 0.0);
      final hand = Offset(
        32 + side * 25 + (side > 0 ? wrist * 3 : 0),
        39 - 20 * lift,
      );
      final arm = Path()
        ..moveTo(32 + side * 15, 34)
        ..quadraticBezierTo(32 + side * 23, 42 - lift * 9, hand.dx, hand.dy);
      canvas.drawPath(arm, line);
      canvas.drawCircle(hand, 4.3, ink);
      canvas.drawCircle(hand, 2.7, white);
    }
    line.strokeWidth = 2;
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
        const Rect.fromLTWH(14, 23, 36, 25),
        const Radius.circular(8),
      ),
      ink,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(43, 31, 10, 10),
        const Radius.circular(4),
      ),
      ink,
    );
    canvas.drawCircle(const Offset(48, 36), 1.6, paper);

    line.color = Colors.white;
    for (final eye in [22.0, 37.0]) {
      if (celebrating || wave > .45) {
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
      oldDelegate.celebrating != celebrating ||
      oldDelegate.stride != stride ||
      oldDelegate.wave != wave ||
      oldDelegate.wrist != wrist;
}
