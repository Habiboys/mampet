import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../domain/enums.dart';

class EggSpriteWidget extends StatefulWidget {
  final MonsterElement element;
  final EggStatus status;
  final double size;
  final bool reduceMotion;

  const EggSpriteWidget({
    super.key,
    required this.element,
    required this.status,
    this.size = 120,
    this.reduceMotion = false,
  });

  @override
  State<EggSpriteWidget> createState() => _EggSpriteWidgetState();
}

class _EggSpriteWidgetState extends State<EggSpriteWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _sync();
  }

  void _sync() {
    if (!widget.reduceMotion && widget.status.isActiveInIncubator) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void didUpdateWidget(covariant EggSpriteWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reduceMotion != widget.reduceMotion ||
        oldWidget.status != widget.status) {
      _sync();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveReduce =
        widget.reduceMotion || MediaQuery.disableAnimationsOf(context);
    final asset = widget.status.usesCrackedAsset
        ? widget.element.crackedEggAsset
        : widget.element.intactEggAsset;
    final cachePx = (widget.size * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(128, 512);

    final eggImage = AnimatedSwitcher(
      duration: Duration(milliseconds: effectiveReduce ? 120 : 380),
      child: Image.asset(
        asset,
        key: ValueKey(asset),
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
        cacheWidth: cachePx,
        semanticLabel:
            'Telur ${widget.element.label} ${widget.status.usesCrackedAsset ? "retak" : "utuh"}',
      ),
    );

    if (effectiveReduce || !widget.status.isActiveInIncubator) {
      return Stack(
        alignment: Alignment.center,
        children: [
          if (widget.status == EggStatus.ready)
            Container(
              width: widget.size * 0.92,
              height: widget.size * 0.92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: widget.element.color.withValues(alpha: 0.35),
                    blurRadius: 24,
                    spreadRadius: 4,
                  ),
                ],
              ),
            ),
          eggImage,
        ],
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value * 2 * math.pi;
        final isReady = widget.status == EggStatus.ready;
        final isCracked = widget.status == EggStatus.cracked;

        final dy = math.sin(t) * 6.0;
        final scale = isReady ? 1.03 + math.sin(t * 2) * 0.03 : 1.0;
        final shakeAngle = isReady
            ? math.sin(t * 4) * 0.06
            : (isCracked && _controller.value < 0.25)
                ? math.sin(_controller.value * 8 * math.pi) * 0.07
                : math.sin(t) * 0.02;

        return Stack(
          alignment: Alignment.center,
          children: [
            if (isReady)
              Container(
                width: widget.size * (0.85 + math.sin(t * 2) * 0.08),
                height: widget.size * (0.85 + math.sin(t * 2) * 0.08),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      widget.element.color.withValues(alpha: 0.36),
                      widget.element.color.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            Transform.translate(
              offset: Offset(0, dy),
              child: Transform.rotate(
                angle: shakeAngle,
                child: Transform.scale(scale: scale, child: child),
              ),
            ),
          ],
        );
      },
      child: eggImage,
    );
  }
}
