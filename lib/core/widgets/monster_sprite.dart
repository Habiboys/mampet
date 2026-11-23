import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../app/theme.dart';

class MonsterSpriteWidget extends StatefulWidget {
  final String assetPath;
  final double size;
  final bool isLocked;
  final bool animateIdle;
  final bool reduceMotion;
  final VoidCallback? onTap;
  final String? semanticLabel;

  const MonsterSpriteWidget({
    super.key,
    required this.assetPath,
    this.size = 140,
    this.isLocked = false,
    this.animateIdle = false,
    this.reduceMotion = false,
    this.onTap,
    this.semanticLabel,
  });

  @override
  State<MonsterSpriteWidget> createState() => _MonsterSpriteWidgetState();
}

class _MonsterSpriteWidgetState extends State<MonsterSpriteWidget>
    with TickerProviderStateMixin {
  late final AnimationController _idleController;
  late final AnimationController _bounceController;
  late final Animation<double> _bounceScale;

  @override
  void initState() {
    super.initState();
    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _bounceScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.08), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 1.08, end: 0.97), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 0.97, end: 1.0), weight: 30),
    ]).animate(CurvedAnimation(parent: _bounceController, curve: Curves.easeOut));

    _syncIdleAnimation();
  }

  void _syncIdleAnimation() {
    if (widget.animateIdle && !widget.reduceMotion && !widget.isLocked) {
      if (!_idleController.isAnimating) {
        _idleController.repeat();
      }
    } else {
      _idleController.stop();
      _idleController.value = 0;
    }
  }

  @override
  void didUpdateWidget(covariant MonsterSpriteWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animateIdle != widget.animateIdle ||
        oldWidget.reduceMotion != widget.reduceMotion ||
        oldWidget.isLocked != widget.isLocked) {
      _syncIdleAnimation();
    }
  }

  @override
  void dispose() {
    _idleController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (!widget.reduceMotion) {
      _bounceController.forward(from: 0);
    }
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveReduce =
        widget.reduceMotion || MediaQuery.disableAnimationsOf(context);
    final cachePx = (widget.size * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(128, 512);

    Widget img = Image.asset(
      widget.assetPath,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
      cacheWidth: cachePx,
      filterQuality: FilterQuality.medium,
      semanticLabel: widget.semanticLabel,
      errorBuilder: (_, _, _) => SizedBox(
        width: widget.size,
        height: widget.size,
        child: Icon(
          Icons.pets_rounded,
          size: widget.size * 0.45,
          color: MamPetColors.cocoaMuted,
        ),
      ),
    );

    if (widget.isLocked) {
      img = ColorFiltered(
        colorFilter: const ColorFilter.mode(
          MamPetColors.silhouetteDark,
          BlendMode.srcIn,
        ),
        child: Opacity(opacity: 0.94, child: img),
      );
    }

    Widget animated = img;
    if (!effectiveReduce && (widget.animateIdle || widget.onTap != null)) {
      animated = AnimatedBuilder(
        animation: Listenable.merge([_idleController, _bounceController]),
        builder: (context, child) {
          final t = _idleController.value * 2 * math.pi;
          final dy = widget.animateIdle && !widget.isLocked ? math.sin(t) * 5.5 : 0.0;
          final breath = widget.animateIdle && !widget.isLocked
              ? 1.0 + math.sin(t) * 0.02
              : 1.0;
          final angle = widget.animateIdle && !widget.isLocked
              ? math.sin(t) * 0.024
              : 0.0;
          final tapScale = _bounceController.isAnimating ? _bounceScale.value : 1.0;

          return Transform.translate(
            offset: Offset(0, dy),
            child: Transform.rotate(
              angle: angle,
              child: Transform.scale(
                scale: breath * tapScale,
                child: child,
              ),
            ),
          );
        },
        child: img,
      );
    }

    if (widget.onTap != null) {
      return GestureDetector(
        onTap: _handleTap,
        behavior: HitTestBehavior.opaque,
        child: animated,
      );
    }
    return animated;
  }
}
