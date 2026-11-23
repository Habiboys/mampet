import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../features/monsters/animation/monster_animation_controller.dart';
import '../../features/monsters/animation/monster_animation_state.dart';
import '../../features/monsters/widgets/interactive_monster.dart';
import '../domain/enums.dart';
import 'game_ui.dart';
import 'heart_burst.dart';

/// Full Living 2D Cozy Game Habitat:
/// Painted sky + drifting fluffy clouds + rolling pastel hills + ambient
/// element particles + cute dynamic speech bubble + interactive 2D rigged pet!
class RoamingPetStage extends StatefulWidget {
  final String assetPath;
  final String? monsterSlug;
  final EvolutionPhase evolutionStage;
  final MonsterAnimationController? monsterController;
  final MonsterElement element;
  final double spriteSize;
  final bool reduceMotion;
  final int heartTrigger;
  final String? feedbackBanner;
  final String speechText;
  final VoidCallback onTapPet;
  final void Function(String part, MonsterAnimation reaction)? onPartTap;
  final String? semanticLabel;

  const RoamingPetStage({
    super.key,
    required this.assetPath,
    this.monsterSlug,
    this.evolutionStage = EvolutionPhase.baby,
    this.monsterController,
    required this.element,
    this.spriteSize = 152,
    this.reduceMotion = false,
    this.heartTrigger = 0,
    this.feedbackBanner,
    this.speechText = 'Ayo catat makan hari ini!',
    required this.onTapPet,
    this.onPartTap,
    this.semanticLabel,
  });

  @override
  State<RoamingPetStage> createState() => _RoamingPetStageState();
}

class _RoamingPetStageState extends State<RoamingPetStage>
    with TickerProviderStateMixin {
  late final AnimationController _roamCtrl;
  late final AnimationController _hopCtrl;
  late final Animation<double> _tapBounce;

  @override
  void initState() {
    super.initState();
    _roamCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 9500),
    );
    _hopCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _tapBounce = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.14), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 1.14, end: 0.94), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 0.94, end: 1.0), weight: 30),
    ]).animate(CurvedAnimation(parent: _hopCtrl, curve: Curves.easeOut));

    _syncAnim();
  }

  void _syncAnim() {
    if (!widget.reduceMotion) {
      if (!_roamCtrl.isAnimating) _roamCtrl.repeat();
    } else {
      _roamCtrl.stop();
      _roamCtrl.value = 0;
    }
  }

  @override
  void didUpdateWidget(covariant RoamingPetStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reduceMotion != widget.reduceMotion) {
      _syncAnim();
    }
  }

  @override
  void dispose() {
    _roamCtrl.dispose();
    _hopCtrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (!widget.reduceMotion) {
      _hopCtrl.forward(from: 0);
    }
    widget.onTapPet();
  }

  ({double xNorm, bool facingRight, double hop, double tilt}) _roamPose(
      double t) {
    if (t < 0.14) {
      return (
        xNorm: 0.0,
        facingRight: true,
        hop: 0.0,
        tilt: math.sin(t * 20) * 0.018,
      );
    }
    if (t < 0.36) {
      final p = (t - 0.14) / 0.22;
      final x = Curves.easeInOutSine.transform(p);
      final hop = math.sin(p * 3 * math.pi).abs();
      return (
        xNorm: x,
        facingRight: true,
        hop: hop,
        tilt: math.sin(p * 6 * math.pi) * 0.05,
      );
    }
    if (t < 0.50) {
      return (
        xNorm: 1.0,
        facingRight: true,
        hop: 0.0,
        tilt: math.sin(t * 18) * 0.02,
      );
    }
    if (t < 0.80) {
      final p = (t - 0.50) / 0.30;
      final x = 1.0 - 2.0 * Curves.easeInOutSine.transform(p);
      final hop = math.sin(p * 4 * math.pi).abs();
      return (
        xNorm: x,
        facingRight: false,
        hop: hop,
        tilt: math.sin(p * 8 * math.pi) * 0.05,
      );
    }
    if (t < 0.88) {
      return (
        xNorm: -1.0,
        facingRight: false,
        hop: 0.0,
        tilt: math.sin(t * 18) * 0.02,
      );
    }
    final p = (t - 0.88) / 0.12;
    final x = -1.0 + Curves.easeInOutSine.transform(p);
    final hop = math.sin(p * 2 * math.pi).abs();
    return (
      xNorm: x,
      facingRight: true,
      hop: hop,
      tilt: math.sin(p * 4 * math.pi) * 0.045,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveReduce =
        widget.reduceMotion || MediaQuery.disableAnimationsOf(context);
    final cachePx = (widget.spriteSize * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(160, 400);

    final Widget petWidget = widget.monsterSlug != null
        ? InteractiveMonster(
            monsterId: widget.monsterSlug!,
            evolutionStage: widget.evolutionStage,
            controller: widget.monsterController,
            size: widget.spriteSize,
            reduceMotion: effectiveReduce,
            semanticLabel: widget.semanticLabel,
            onTap: widget.onPartTap == null ? _handleTap : null,
            onPartTap: widget.onPartTap,
          )
        : Image.asset(
            widget.assetPath,
            width: widget.spriteSize,
            height: widget.spriteSize,
            fit: BoxFit.contain,
            cacheWidth: cachePx,
            filterQuality: FilterQuality.medium,
            semanticLabel: widget.semanticLabel,
          );

    final listenables = <Listenable>[
      _roamCtrl,
      _hopCtrl,
      if (widget.monsterController != null) widget.monsterController!,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxRoamPx =
            ((constraints.maxWidth - widget.spriteSize) * 0.36).clamp(18.0, 74.0);

        return ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: SizedBox(
            height: 226,
            width: double.infinity,
            child: AnimatedBuilder(
              animation: Listenable.merge(listenables),
              builder: (_, child) {
                final isSleeping = widget.monsterController?.isSleeping ?? false;
                final isReacting = widget.monsterController != null &&
                    widget.monsterController!.state != MonsterAnimation.idle;
                final t = effectiveReduce ? 0.0 : _roamCtrl.value;
                // Pause roaming gently while sleeping or playing an interactive reaction
                final pose = (effectiveReduce || isSleeping || isReacting)
                    ? (xNorm: 0.0, facingRight: true, hop: 0.0, tilt: 0.0)
                    : _roamPose(t);

                final dx = pose.xNorm * maxRoamPx;
                final idleBreath = (effectiveReduce || widget.monsterSlug != null)
                    ? 1.0
                    : 1.0 + math.sin(t * 8 * math.pi) * 0.02;
                final tapScale =
                    (_hopCtrl.isAnimating && widget.monsterSlug == null)
                        ? _tapBounce.value
                        : 1.0;
                final tapJump =
                    (_hopCtrl.isAnimating && widget.monsterSlug == null)
                        ? math.sin(_hopCtrl.value * math.pi) * 20.0
                        : 0.0;
                final dy = -(pose.hop * 10.0 + tapJump);
                final shadowScale =
                    (1.0 - (pose.hop * 0.14) - (tapJump / 80.0))
                        .clamp(0.68, 1.0);

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // 1. Living 2D Cozy Game Landscape Canvas!
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _HabitatLandscapePainter(
                          element: widget.element,
                          t: t,
                          isDark: isDark,
                        ),
                      ),
                    ),

                    // 2. Cute floating speech bubble or Bond reaction banner
                    Positioned(
                      top: 8,
                      child: Transform.translate(
                        offset: Offset(dx * 0.35, math.sin(t * 4 * math.pi) * 2),
                        child: GameSpeechBubble(
                          text: widget.feedbackBanner ??
                              (isSleeping
                                  ? 'Zzz... sedang tidur pulas'
                                  : widget.speechText),
                          accentColor: widget.feedbackBanner != null
                              ? const Color(0xFFF43F5E)
                              : isSleeping
                                  ? const Color(0xFF6366F1)
                                  : widget.element.color,
                        ),
                      ),
                    ),

                    // 3. Soft true-ellipse ground shadow beneath roaming pet
                    Positioned(
                      bottom: 12,
                      child: Transform.translate(
                        offset: Offset(dx, 0),
                        child: Transform.scale(
                          scale: shadowScale,
                          child: CustomPaint(
                            size: const Size(112, 22),
                            painter: _SoftOvalShadowPainter(
                              alpha: isDark ? 0.42 : 0.22,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // 4. Roaming interactive 2D animated pet
                    Positioned(
                      bottom: 9,
                      child: Transform.translate(
                        offset: Offset(dx, dy),
                        child: widget.monsterSlug != null
                            ? Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.identity()
                                  ..scaleByDouble(
                                    pose.facingRight ? 1.0 : -1.0,
                                    1.0,
                                    1.0,
                                    1.0,
                                  )
                                  ..rotateZ(pose.tilt * 0.55),
                                child: child,
                              )
                            : GestureDetector(
                                onTap: _handleTap,
                                behavior: HitTestBehavior.opaque,
                                child: Transform(
                                  alignment: Alignment.center,
                                  transform: Matrix4.identity()
                                    ..scaleByDouble(
                                      (pose.facingRight ? 1.0 : -1.0) *
                                          idleBreath *
                                          tapScale,
                                      idleBreath * tapScale,
                                      1.0,
                                      1.0,
                                    )
                                    ..rotateZ(pose.tilt),
                                  child: child,
                                ),
                              ),
                      ),
                    ),

                    // 5. Floating hearts & sparkles on tap
                    Transform.translate(
                      offset: Offset(dx, -6),
                      child: HeartBurstOverlay(
                        triggerCount: widget.heartTrigger,
                        reduceMotion: effectiveReduce,
                      ),
                    ),
                  ],
                );
              },
              child: petWidget,
            ),
          ),
        );
      },
    );
  }
}

class _HabitatLandscapePainter extends CustomPainter {
  final MonsterElement element;
  final double t;
  final bool isDark;

  const _HabitatLandscapePainter({
    required this.element,
    required this.t,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Element-coordinated cozy sky + hills palette
    final (skyTop, skyBot, hillFar, hillNear, particleColor) = switch (element) {
      MonsterElement.fire => (
          isDark ? const Color(0xFF422118) : const Color(0xFFFFD9B8),
          isDark ? const Color(0xFF2B1813) : const Color(0xFFFFF4E3),
          isDark ? const Color(0xFF543022) : const Color(0xFFFED39F),
          isDark ? const Color(0xFF3E241B) : const Color(0xFFFBB36B),
          const Color(0xFFFF7A2F),
        ),
      MonsterElement.water => (
          isDark ? const Color(0xFF13334B) : const Color(0xFFBAE6FD),
          isDark ? const Color(0xFF152536) : const Color(0xFFEFF9FF),
          isDark ? const Color(0xFF1A4B6E) : const Color(0xFF93D9FA),
          isDark ? const Color(0xFF153B54) : const Color(0xFF67C4F0),
          const Color(0xFF38BDF8),
        ),
      MonsterElement.nature => (
          isDark ? const Color(0xFF163526) : const Color(0xFFCFF6DF),
          isDark ? const Color(0xFF17271E) : const Color(0xFFF3FDF7),
          isDark ? const Color(0xFF1E4F35) : const Color(0xFFA7E8B8),
          isDark ? const Color(0xFF1A3E2A) : const Color(0xFF7CD992),
          const Color(0xFF22C55E),
        ),
      MonsterElement.wind => (
          isDark ? const Color(0xFF183447) : const Color(0xFFCEEFFE),
          isDark ? const Color(0xFF1A2630) : const Color(0xFFF5FBFF),
          isDark ? const Color(0xFF254D63) : const Color(0xFFB5E3F9),
          isDark ? const Color(0xFF1E3C4F) : const Color(0xFF8CD3F5),
          const Color(0xFF38BDF8),
        ),
      MonsterElement.earth => (
          isDark ? const Color(0xFF3B2C1B) : const Color(0xFFFDEBC8),
          isDark ? const Color(0xFF261D14) : const Color(0xFFFFF9EC),
          isDark ? const Color(0xFF523E26) : const Color(0xFFECD09E),
          isDark ? const Color(0xFF3E2F1E) : const Color(0xFFDAB370),
          const Color(0xFFF59E0B),
        ),
      MonsterElement.mystery => (
          isDark ? const Color(0xFF2E1E4E) : const Color(0xFFE6D5FF),
          isDark ? const Color(0xFF1D1530) : const Color(0xFFF7F0FF),
          isDark ? const Color(0xFF422C6E) : const Color(0xFFD2B5FA),
          isDark ? const Color(0xFF312054) : const Color(0xFFB98EF5),
          const Color(0xFFA855F7),
        ),
    };

    // 1. Sky gradient
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [skyTop, skyBot],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // 2. Soft sunlit orb
    canvas.drawCircle(
      Offset(w * 0.85, h * 0.22),
      26,
      Paint()..color = Colors.white.withValues(alpha: isDark ? 0.1 : 0.65),
    );

    // 3. Drifting fluffy cartoon clouds
    final cloudPaint =
        Paint()..color = Colors.white.withValues(alpha: isDark ? 0.1 : 0.78);
    void drawCloud(double cx, double cy, double r) {
      canvas.drawCircle(Offset(cx, cy), r, cloudPaint);
      canvas.drawCircle(Offset(cx - r * 0.85, cy + r * 0.22), r * 0.72, cloudPaint);
      canvas.drawCircle(Offset(cx + r * 0.85, cy + r * 0.25), r * 0.68, cloudPaint);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - r * 1.4, cy + r * 0.15, r * 2.8, r * 0.78),
          Radius.circular(r),
        ),
        cloudPaint,
      );
    }

    final c1x = ((w * 0.18 + t * w * 0.35) % (w + 90)) - 45;
    final c2x = ((w * 0.72 + t * w * 0.22) % (w + 100)) - 50;
    drawCloud(c1x, h * 0.24, 14);
    drawCloud(c2x, h * 0.36, 11);

    // 4. Far rolling hill
    final farPath = Path()
      ..moveTo(0, h * 0.72)
      ..quadraticBezierTo(w * 0.28, h * 0.56, w * 0.58, h * 0.68)
      ..quadraticBezierTo(w * 0.82, h * 0.77, w, h * 0.64)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(farPath, Paint()..color = hillFar);

    // 5. Near cozy meadow ground
    final nearPath = Path()
      ..moveTo(0, h * 0.79)
      ..quadraticBezierTo(w * 0.35, h * 0.70, w * 0.68, h * 0.78)
      ..quadraticBezierTo(w * 0.86, h * 0.82, w, h * 0.75)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(nearPath, Paint()..color = hillNear);

    // 6. Floating ambient element sparkles / bubbles
    for (int i = 0; i < 6; i++) {
      final phase = (t + i / 6.0) % 1.0;
      final px = w * (0.12 + (i * 0.16)) + math.sin(phase * 2 * math.pi) * 10;
      final py = h * (0.72 - phase * 0.52);
      final alpha = (math.sin(phase * math.pi) * 0.55).clamp(0.0, 0.55);
      canvas.drawCircle(
        Offset(px, py),
        3.2 + (i % 2) * 1.6,
        Paint()..color = particleColor.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HabitatLandscapePainter old) =>
      old.t != t || old.element != element || old.isDark != isDark;
}

class _SoftOvalShadowPainter extends CustomPainter {
  final double alpha;
  const _SoftOvalShadowPainter({required this.alpha});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Transform radial gradient into a smooth true ellipse matching rect aspect ratio
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.black.withValues(alpha: alpha),
          Colors.black.withValues(alpha: alpha * 0.55),
          Colors.black.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(
        Rect.fromCircle(
          center: rect.center,
          radius: size.width * 0.5,
        ),
      );
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.scale(1.0, size.height / size.width);
    canvas.drawCircle(Offset.zero, size.width * 0.5, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SoftOvalShadowPainter old) => old.alpha != alpha;
}
