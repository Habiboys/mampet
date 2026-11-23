import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'openbone_document.dart';
import 'openbone_runtime.dart';

/// Decoded GPU texture page + cached [ui.ImageShader] ready for 60 FPS `drawVertices`.
class OpenBoneGpuTexture {
  final ui.Image image;
  final ui.ImageShader shader;
  final double scaleX;
  final double scaleY;

  OpenBoneGpuTexture({
    required this.image,
    required int declaredWidth,
    required int declaredHeight,
  })  : shader = ui.ImageShader(
          image,
          TileMode.clamp,
          TileMode.clamp,
          Float64List.fromList(const <double>[
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
          ]),
          filterQuality: FilterQuality.medium,
        ),
        scaleX = declaredWidth > 0 ? image.width / declaredWidth : 1.0,
        scaleY = declaredHeight > 0 ? image.height / declaredHeight : 1.0;

  void dispose() {
    image.dispose();
  }
}

/// GPU-accelerated 2D OpenBone weighted-mesh + expression-slot painter.
///
/// Renders every visible slot via Flutter's native [Canvas.drawVertices] with
/// bilinear [ui.ImageShader] sampling, preserving OpenBone's uniform-fit
/// artboard padding (1024×1024) for jumps and wing span.
class OpenBoneCanvasPainter extends CustomPainter {
  final OpenBonePlayer player;
  final Map<String, OpenBoneGpuTexture> textures;
  final int repaintTick;
  final bool showSleepZzz;
  final double sleepPhase;
  final bool showDebugBones;
  final bool showDebugHitboxes;

  const OpenBoneCanvasPainter({
    required this.player,
    required this.textures,
    required this.repaintTick,
    this.showSleepZzz = false,
    this.sleepPhase = 0.0,
    this.showDebugBones = false,
    this.showDebugHitboxes = false,
  });

  /// Computes the uniform-fit scale and top-left artboard offset for [canvasSize].
  static ({double scale, double offsetX, double offsetY}) computeFit(
    OpenBoneDocument doc,
    Size canvasSize,
  ) {
    final sx = canvasSize.width / doc.width;
    final sy = canvasSize.height / doc.height;
    final scale = math.min(sx, sy);
    final offsetX = (canvasSize.width - doc.width * scale) * 0.5;
    final offsetY = (canvasSize.height - doc.height * scale) * 0.5;
    return (scale: scale, offsetX: offsetX, offsetY: offsetY);
  }

  /// Converts a local widget tap [localPos] to OpenBone artboard coordinates.
  static Offset localToArtboard(
    OpenBoneDocument doc,
    Size canvasSize,
    Offset localPos,
  ) {
    final fit = computeFit(doc, canvasSize);
    if (fit.scale <= 1e-6) return Offset.zero;
    return Offset(
      (localPos.dx - fit.offsetX) / fit.scale,
      (localPos.dy - fit.offsetY) / fit.scale,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final doc = player.doc;
    final fit = computeFit(doc, size);
    final scale = fit.scale;
    final ox = fit.offsetX + doc.originX * scale;
    final oy = fit.offsetY + doc.originY * scale;

    final drawList = player.skeleton.buildDrawList();
    for (final item in drawList) {
      final tex = textures[item.pageId];
      if (tex == null) continue;

      final world = item.worldVertices;
      final positions = Float32List(world.length);
      for (int i = 0; i < world.length; i += 2) {
        positions[i] = ox + world[i] * scale;
        positions[i + 1] = oy - world[i + 1] * scale;
      }

      Float32List texCoords = item.atlasTexCoords;
      if ((tex.scaleX - 1.0).abs() > 1e-4 || (tex.scaleY - 1.0).abs() > 1e-4) {
        final scaled = Float32List(texCoords.length);
        for (int i = 0; i < texCoords.length; i += 2) {
          scaled[i] = texCoords[i] * tex.scaleX;
          scaled[i + 1] = texCoords[i + 1] * tex.scaleY;
        }
        texCoords = scaled;
      }

      final vertices = ui.Vertices.raw(
        ui.VertexMode.triangles,
        positions,
        textureCoordinates: texCoords,
        indices: item.triangles,
      );

      final paint = Paint()
        ..shader = tex.shader
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.medium;
      if (item.alpha < 0.999) {
        final a = (item.alpha.clamp(0.0, 1.0) * 255.0).round();
        paint.colorFilter = ColorFilter.mode(
          Color.fromARGB(a, 255, 255, 255),
          BlendMode.modulate,
        );
      }

      canvas.drawVertices(vertices, BlendMode.srcOver, paint);
    }

    if (showSleepZzz) {
      _paintSleepZzz(canvas, size);
    }
    if (showDebugHitboxes) {
      _paintHitboxes(canvas, ox, oy, scale);
    }
    if (showDebugBones) {
      _paintBones(canvas, ox, oy, scale);
    }
  }

  void _paintHitboxes(Canvas canvas, double ox, double oy, double scale) {
    final fill = Paint()
      ..color = const Color(0xFFFFB400).withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = const Color(0xFFFF9800).withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    for (int i = 0; i < player.skeleton.slots.length; i++) {
      final poly = player.skeleton.boundingBoxWorldVertices(i);
      if (poly == null || poly.length < 6) continue;
      final path = Path();
      for (int p = 0; p < poly.length; p += 2) {
        final x = ox + poly[p] * scale;
        final y = oy - poly[p + 1] * scale;
        if (p == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      canvas.drawPath(path, fill);
      canvas.drawPath(path, stroke);
    }
  }

  void _paintBones(Canvas canvas, double ox, double oy, double scale) {
    final fill = Paint()
      ..color = const Color(0xFF0EA5E9).withValues(alpha: 0.28)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = const Color(0xFF0284C7).withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    final dot = Paint()
      ..color = const Color(0xFFFF5A5F)
      ..style = PaintingStyle.fill;

    for (final bone in player.skeleton.bones) {
      final m = bone.world;
      final sx = ox + m.x * scale;
      final sy = oy - m.y * scale;
      final len = bone.data.length;
      if (len > 1.0) {
        final tx = ox + (m.x + m.a * len) * scale;
        final ty = oy - (m.y + m.c * len) * scale;
        final half = math.min(len * 0.12 * scale, 7.0) + 1.5;
        final mx = ox + (m.x + m.a * len * 0.18) * scale;
        final my = oy - (m.y + m.c * len * 0.18) * scale;
        final dx = tx - sx;
        final dy = ty - sy;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist > 1e-3) {
          final nx = -dy / dist * half;
          final ny = dx / dist * half;
          final path = Path()
            ..moveTo(sx, sy)
            ..lineTo(mx + nx, my + ny)
            ..lineTo(tx, ty)
            ..lineTo(mx - nx, my - ny)
            ..close();
          canvas.drawPath(path, fill);
          canvas.drawPath(path, stroke);
        }
      }
      canvas.drawCircle(Offset(sx, sy), 3.0, dot);
    }
  }

  void _paintSleepZzz(Canvas canvas, Size size) {
    const labels = ['z', 'Z', 'Z'];
    for (int i = 0; i < 3; i++) {
      final t = (sleepPhase + i * 0.33) % 1.0;
      final opacity = math.sin(t * math.pi).clamp(0.0, 1.0);
      if (opacity < 0.05) continue;
      final dx = size.width * 0.66 + math.sin(t * math.pi * 2.0) * 6.0 + i * 9.0;
      final dy = size.height * 0.25 - t * size.height * 0.18;
      final fontSize = (size.width * (0.068 + i * 0.02)).clamp(10.0, 22.0);

      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            fontFamily: 'Fredoka',
            fontWeight: FontWeight.w800,
            fontSize: fontSize,
            color: const Color(0xFF4F6DF5).withValues(alpha: opacity * 0.85),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(dx, dy));
    }
  }

  @override
  bool shouldRepaint(covariant OpenBoneCanvasPainter oldDelegate) {
    return oldDelegate.repaintTick != repaintTick ||
        oldDelegate.player != player ||
        oldDelegate.showSleepZzz != showSleepZzz ||
        oldDelegate.showDebugBones != showDebugBones ||
        oldDelegate.showDebugHitboxes != showDebugHitboxes;
  }
}
