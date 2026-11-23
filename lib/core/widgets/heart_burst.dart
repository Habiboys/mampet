import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Spawns rising mini hearts & sparkles when user pets a monster.
class HeartBurstOverlay extends StatefulWidget {
  final int triggerCount;
  final bool reduceMotion;

  const HeartBurstOverlay({
    super.key,
    required this.triggerCount,
    this.reduceMotion = false,
  });

  @override
  State<HeartBurstOverlay> createState() => _HeartBurstOverlayState();
}

class _HeartBurstOverlayState extends State<HeartBurstOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
  }

  @override
  void didUpdateWidget(covariant HeartBurstOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.triggerCount > oldWidget.triggerCount && !widget.reduceMotion) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reduceMotion || MediaQuery.disableAnimationsOf(context)) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, _) {
          if (_ctrl.value <= 0.01 || _ctrl.value >= 0.99) {
            return const SizedBox.shrink();
          }
          final t = _ctrl.value;
          final alpha = (1.0 - Curves.easeIn.transform(t)).clamp(0.0, 1.0);
          return SizedBox(
            width: 170,
            height: 150,
            child: Stack(
              alignment: Alignment.center,
              children: List.generate(5, (i) {
                final spread = (i - 2) * 26.0;
                final dx = spread * Curves.easeOut.transform(t) +
                    math.sin(t * math.pi * 2 + i) * 6;
                final dy = -20 - (68 + (i % 2) * 20) * Curves.easeOut.transform(t);
                final scale = (0.65 + (1 - t) * 0.5).clamp(0.4, 1.2);
                return Transform.translate(
                  offset: Offset(dx, dy),
                  child: Opacity(
                    opacity: alpha,
                    child: Transform.scale(
                      scale: scale,
                      child: Icon(
                        i.isEven ? Icons.favorite_rounded : Icons.auto_awesome_rounded,
                        size: i.isEven ? 20 : 16,
                        color: i.isEven
                            ? const Color(0xFFF43F5E)
                            : const Color(0xFFF5A623),
                      ),
                    ),
                  ),
                );
              }),
            ),
          );
        },
      ),
    );
  }
}
