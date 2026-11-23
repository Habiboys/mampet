import 'dart:math' as math;
import 'package:flutter/material.dart';

class ConfettiBurstOverlay extends StatefulWidget {
  final bool active;
  final bool reduceMotion;
  final Duration duration;

  const ConfettiBurstOverlay({
    super.key,
    required this.active,
    this.reduceMotion = false,
    this.duration = const Duration(milliseconds: 1200),
  });

  @override
  State<ConfettiBurstOverlay> createState() => _ConfettiBurstOverlayState();
}

class _ConfettiBurstOverlayState extends State<ConfettiBurstOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    final rng = math.Random(42);
    const colors = [
      Color(0xFFE86A33),
      Color(0xFFF5A623),
      Color(0xFF14B8A6),
      Color(0xFF8B5CF6),
      Color(0xFF3B82F6),
      Color(0xFFEC4899),
    ];
    _particles = List.generate(38, (i) {
      final angle = rng.nextDouble() * 2 * math.pi;
      final speed = 90 + rng.nextDouble() * 190;
      return _Particle(
        angle: angle,
        speed: speed,
        size: 5 + rng.nextDouble() * 6,
        color: colors[i % colors.length],
        spin: (rng.nextDouble() - 0.5) * 10,
      );
    });
    if (widget.active && !widget.reduceMotion) {
      _controller.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(covariant ConfettiBurstOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && !widget.reduceMotion) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active ||
        widget.reduceMotion ||
        MediaQuery.disableAnimationsOf(context)) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          if (_controller.value == 0 || _controller.value >= 1.0) {
            return const SizedBox.shrink();
          }
          return CustomPaint(
            painter: _ConfettiPainter(_particles, _controller.value),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _Particle {
  final double angle;
  final double speed;
  final double size;
  final Color color;
  final double spin;
  const _Particle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.color,
    required this.spin,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> particles;
  final double t;

  _ConfettiPainter(this.particles, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.44;
    final opacity = (1.0 - Curves.easeIn.transform(t)).clamp(0.0, 1.0);

    for (final p in particles) {
      final dist = p.speed * Curves.easeOut.transform(t);
      final gravity = 150 * t * t;
      final x = cx + math.cos(p.angle) * dist;
      final y = cy + math.sin(p.angle) * dist + gravity;

      final paint = Paint()..color = p.color.withValues(alpha: opacity);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * t);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.55),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => oldDelegate.t != t;
}
