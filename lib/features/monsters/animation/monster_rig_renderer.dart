import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/monster_rig.dart';
import 'monster_animation_config.dart';

/// Renders a layered [MonsterRig] using hierarchical parent-child [Matrix4]
/// transforms so attached parts (eyes/mouth on head, head/wings/tail on body)
/// stay locked together with zero joint separation at 60 FPS.
class MonsterRigRenderer extends StatelessWidget {
  final MonsterRig rig;
  final Map<String, LayerTransform> pose;
  final String activeEyesLayerId;
  final String activeMouthLayerId;
  final double size;
  final bool showSleepZzz;
  final double sleepPhase;
  final bool showDebugPivots;
  final bool showDebugHitboxes;
  final String? highlightedPart;

  const MonsterRigRenderer({
    super.key,
    required this.rig,
    required this.pose,
    required this.activeEyesLayerId,
    required this.activeMouthLayerId,
    required this.size,
    this.showSleepZzz = false,
    this.sleepPhase = 0.0,
    this.showDebugPivots = false,
    this.showDebugHitboxes = false,
    this.highlightedPart,
  });

  bool _isLayerVisible(RigLayer layer) {
    if (layer.slot == 'eyes') {
      // Check if rig actually has the requested eye layer; otherwise fallback to defaultVisible
      final hasRequested = rig.layers.any(
        (l) => l.slot == 'eyes' && l.id == activeEyesLayerId,
      );
      if (hasRequested) return layer.id == activeEyesLayerId;
      return layer.defaultVisible;
    }
    if (layer.slot == 'mouth') {
      final hasRequested = rig.layers.any(
        (l) => l.slot == 'mouth' && l.id == activeMouthLayerId,
      );
      if (hasRequested) return layer.id == activeMouthLayerId;
      return layer.defaultVisible;
    }
    return layer.defaultVisible;
  }

  /// Recursively computes composed world [Matrix4] for [layer] in widget pixel space.
  Matrix4 _worldMatrixFor(
    RigLayer layer,
    Map<String, RigLayer> byId,
    Map<String, Matrix4> memo,
    Set<String> visiting,
  ) {
    final cached = memo[layer.id];
    if (cached != null) return cached;

    final scaleToWidget = size / math.max(1.0, rig.canvasWidth);
    final t = pose[layer.id] ?? LayerTransform.identity;
    final px = layer.pivot.dx * size;
    final py = layer.pivot.dy * size;

    final local = Matrix4.identity()
      ..translateByDouble(
        px + t.dx * scaleToWidget,
        py + t.dy * scaleToWidget,
        0.0,
        1.0,
      )
      ..rotateZ(t.rotDeg * math.pi / 180.0)
      ..scaleByDouble(t.scaleX, t.scaleY, 1.0, 1.0)
      ..translateByDouble(-px, -py, 0.0, 1.0);

    Matrix4 world = local;
    final parentId = layer.parent;
    if (parentId != null &&
        byId.containsKey(parentId) &&
        !visiting.contains(parentId)) {
      visiting.add(layer.id);
      final parentWorld = _worldMatrixFor(byId[parentId]!, byId, memo, visiting);
      world = parentWorld.multiplied(local);
      visiting.remove(layer.id);
    }

    memo[layer.id] = world;
    return world;
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cachePx = (size * dpr).round().clamp(160, 640);

    final layers = rig.sortedLayers;
    final byId = <String, RigLayer>{
      for (final l in layers) l.id: l,
    };
    final matrices = <String, Matrix4>{};
    final visiting = <String>{};

    for (final l in layers) {
      _worldMatrixFor(l, byId, matrices, visiting);
    }

    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final layer in layers)
              if (_isLayerVisible(layer))
                Positioned.fill(
                  child: Transform(
                    transform: matrices[layer.id]!,
                    filterQuality: FilterQuality.medium,
                    child: Opacity(
                      opacity: (pose[layer.id]?.opacity ?? 1.0).clamp(0.0, 1.0),
                      child: Image.asset(
                        rig.resolveLayerAsset(layer),
                        width: size,
                        height: size,
                        fit: BoxFit.contain,
                        cacheWidth: cachePx,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),

            // Cozy floating "Z z z" bubble while sleeping
            if (showSleepZzz)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _SleepZzzPainter(phase: sleepPhase),
                  ),
                ),
              ),

            // Optional Developer QA overlay for pivot crosshairs & hitboxes
            if (showDebugHitboxes || showDebugPivots)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _RigDebugOverlayPainter(
                      rig: rig,
                      matrices: matrices,
                      size: size,
                      showPivots: showDebugPivots,
                      showHitboxes: showDebugHitboxes,
                      highlightedPart: highlightedPart,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SleepZzzPainter extends CustomPainter {
  final double phase;
  const _SleepZzzPainter({required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final labels = ['z', 'Z', 'Z'];
    for (int i = 0; i < 3; i++) {
      final p = (phase + i * 0.33) % 1.0;
      final x = size.width * (0.68 + i * 0.05) + math.sin(p * math.pi * 2) * 5;
      final y = size.height * (0.30 - p * 0.22);
      final alpha = (math.sin(p * math.pi) * 0.9).clamp(0.0, 0.9);
      final fontSize = (size.width * (0.06 + i * 0.018)).clamp(10.0, 22.0);
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            fontFamily: 'Fredoka',
            fontWeight: FontWeight.w700,
            fontSize: fontSize,
            color: const Color(0xFF6366F1).withValues(alpha: alpha),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x, y));
    }
  }

  @override
  bool shouldRepaint(covariant _SleepZzzPainter old) => old.phase != phase;
}

class _RigDebugOverlayPainter extends CustomPainter {
  final MonsterRig rig;
  final Map<String, Matrix4> matrices;
  final double size;
  final bool showPivots;
  final bool showHitboxes;
  final String? highlightedPart;

  const _RigDebugOverlayPainter({
    required this.rig,
    required this.matrices,
    required this.size,
    required this.showPivots,
    required this.showHitboxes,
    this.highlightedPart,
  });

  static const List<Color> _palette = [
    Color(0xFFEF4444),
    Color(0xFF3B82F6),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
  ];

  @override
  void paint(Canvas canvas, Size canvasSize) {
    if (showHitboxes) {
      for (int i = 0; i < rig.hitboxes.length; i++) {
        final hb = rig.hitboxes[i];
        final isHot = hb.part == highlightedPart;
        final color = _palette[i % _palette.length];
        final rect = Rect.fromLTWH(
          hb.rect.left * size,
          hb.rect.top * size,
          hb.rect.width * size,
          hb.rect.height * size,
        );
        canvas.drawRect(
          rect,
          Paint()..color = color.withValues(alpha: isHot ? 0.28 : 0.11),
        );
        canvas.drawRect(
          rect,
          Paint()
            ..color = color.withValues(alpha: isHot ? 0.95 : 0.72)
            ..style = PaintingStyle.stroke
            ..strokeWidth = isHot ? 2.4 : 1.4,
        );
        final tp = TextPainter(
          text: TextSpan(
            text: '${hb.part} (${hb.reaction})',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              backgroundColor: color.withValues(alpha: 0.85),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(rect.left + 2, rect.top + 2));
      }
    }

    if (showPivots) {
      for (int i = 0; i < rig.layers.length; i++) {
        final layer = rig.layers[i];
        if (layer.slot != null) continue; // skip expression slot duplicates
        final m = matrices[layer.id];
        if (m == null) continue;
        final rawX = layer.pivot.dx * size;
        final rawY = layer.pivot.dy * size;
        // Transform pivot point by world matrix so crosshair tracks live motion
        final tx = m.entry(0, 0) * rawX + m.entry(0, 1) * rawY + m.entry(0, 3);
        final ty = m.entry(1, 0) * rawX + m.entry(1, 1) * rawY + m.entry(1, 3);

        final color = _palette[i % _palette.length];
        final p = Paint()
          ..color = color
          ..strokeWidth = 1.8;
        canvas.drawLine(Offset(tx - 6, ty), Offset(tx + 6, ty), p);
        canvas.drawLine(Offset(tx, ty - 6), Offset(tx, ty + 6), p);
        canvas.drawCircle(Offset(tx, ty), 3.2, Paint()..color = Colors.white);
        canvas.drawCircle(
          Offset(tx, ty),
          3.2,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );

        final tp = TextPainter(
          text: TextSpan(
            text: layer.id,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              backgroundColor: Colors.black.withValues(alpha: 0.65),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(tx + 6, ty - 6));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RigDebugOverlayPainter old) => true;
}
