import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../app/theme.dart';

/// Squishy 3D cartoon game button with thick outline, bottom bevel depth,
/// top specular shine, press-down squash, and haptic click.
class GameButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color color;
  final Color? shadowColor;
  final Color textColor;
  final double height;
  final bool loading;
  final bool compact;

  const GameButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.color = MamPetColors.coralPrimary,
    this.shadowColor,
    this.textColor = Colors.white,
    this.height = 52,
    this.loading = false,
    this.compact = false,
  });

  const GameButton.secondary({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.height = 48,
    this.loading = false,
    this.compact = false,
  })  : color = MamPetColors.warmSurface,
        shadowColor = MamPetColors.warmOutline,
        textColor = MamPetColors.espresso;

  const GameButton.sky({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.height = 50,
    this.loading = false,
    this.compact = false,
  })  : color = MamPetColors.skyAccent,
        shadowColor = const Color(0xFF0369A1),
        textColor = Colors.white;

  const GameButton.sage({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.height = 52,
    this.loading = false,
    this.compact = false,
  })  : color = MamPetColors.sageAccent,
        shadowColor = const Color(0xFF166534),
        textColor = Colors.white;

  @override
  State<GameButton> createState() => _GameButtonState();
}

class _GameButtonState extends State<GameButton> {
  bool _pressed = false;

  Color _darken(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness - 0.14).clamp(0.0, 1.0)).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null || widget.loading;
    final baseColor = disabled ? const Color(0xFFD6CCC2) : widget.color;
    final lipColor =
        disabled ? const Color(0xFFB8AEA4) : (widget.shadowColor ?? _darken(widget.color));
    final outlineColor = disabled
        ? const Color(0xFFA89F95)
        : (widget.color == MamPetColors.warmSurface
            ? MamPetColors.warmOutline
            : MamPetColors.espresso.withValues(alpha: 0.78));
    final double depth = _pressed && !disabled ? 1.0 : 4.5;

    return GestureDetector(
      onTapDown: disabled ? null : (_) => setState(() => _pressed = true),
      onTapUp: disabled
          ? null
          : (_) {
              setState(() => _pressed = false);
              HapticFeedback.lightImpact();
              widget.onPressed?.call();
            },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 85),
        curve: Curves.easeOut,
        height: widget.height,
        margin: EdgeInsets.only(top: _pressed && !disabled ? 3.5 : 0),
        padding: EdgeInsets.only(bottom: depth),
        decoration: BoxDecoration(
          color: lipColor,
          borderRadius: BorderRadius.circular(widget.compact ? 16 : 20),
          border: Border.all(color: outlineColor, width: 1.8),
        ),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: widget.compact ? 12 : 18),
          decoration: BoxDecoration(
            color: baseColor,
            borderRadius: BorderRadius.circular(widget.compact ? 14 : 18),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Subtle glossy top highlight strip
              if (!disabled && widget.color != MamPetColors.warmSurface)
                Positioned(
                  top: 3,
                  left: 12,
                  right: 12,
                  child: Container(
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              if (widget.loading)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: widget.textColor,
                  ),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(
                        widget.icon,
                        size: widget.compact ? 17 : 20,
                        color: disabled ? Colors.white70 : widget.textColor,
                      ),
                      const SizedBox(width: 7),
                    ],
                    Flexible(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Fredoka',
                          fontSize: widget.compact ? 13.5 : 15.5,
                          fontWeight: FontWeight.w700,
                          color: disabled ? Colors.white70 : widget.textColor,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tactile 2D Cozy Game panel with crisp outline & 3D shaded bottom lip.
class GamePanel extends StatelessWidget {
  final Widget child;
  final Color? color;
  final Gradient? gradient;
  final Color? borderColor;
  final Color? lipColor;
  final double borderWidth;
  final double radius;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const GamePanel({
    super.key,
    required this.child,
    this.color,
    this.gradient,
    this.borderColor,
    this.lipColor,
    this.borderWidth = 1.8,
    this.radius = 24,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = color ?? (isDark ? MamPetColors.darkSurface : Colors.white);
    final border = borderColor ??
        (isDark ? MamPetColors.darkOutline : const Color(0xFFDDCBB8));
    final lip = lipColor ??
        (isDark ? const Color(0xFF140F0D) : const Color(0xFFE2D2C0));

    final inner = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? bg : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius - 2),
      ),
      child: child,
    );

    final container = Container(
      padding: const EdgeInsets.only(bottom: 4.5),
      decoration: BoxDecoration(
        color: lip,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border, width: borderWidth),
        boxShadow: [
          BoxShadow(
            color: MamPetColors.espresso.withValues(alpha: isDark ? 0.3 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 2),
        child: onTap != null
            ? Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onTap!();
                  },
                  child: inner,
                ),
              )
            : inner,
      ),
    );

    return container;
  }
}

/// Candy-pill XP & discovery bar with glossy highlight & optional shimmer sweep.
class GameProgressBar extends StatelessWidget {
  final double progress;
  final Color fillColor;
  final Color? trackColor;
  final double height;
  final bool shimmer;
  final bool reduceMotion;

  const GameProgressBar({
    super.key,
    required this.progress,
    this.fillColor = MamPetColors.coralPrimary,
    this.trackColor,
    this.height = 14,
    this.shimmer = true,
    this.reduceMotion = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final clamped = progress.clamp(0.0, 1.0);
    final effectiveReduce =
        reduceMotion || MediaQuery.disableAnimationsOf(context);

    Widget barFill = FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: clamped > 0 ? clamped.clamp(0.06, 1.0) : 0.0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(fillColor, Colors.white, 0.22)!,
              fillColor,
            ],
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            height: height * 0.32,
            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.36),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
      ),
    );

    if (shimmer && clamped > 0.08 && !effectiveReduce) {
      barFill = barFill
          .animate(onPlay: (c) => c.repeat())
          .shimmer(
            delay: 1400.ms,
            duration: 1200.ms,
            color: Colors.white.withValues(alpha: 0.45),
          );
    }

    return Container(
      height: height,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: trackColor ??
            (isDark ? MamPetColors.darkSurfaceAlt : const Color(0xFFEDE2D4)),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDark ? MamPetColors.darkOutline : const Color(0xFFD5C3AF),
          width: 1.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: Align(
          alignment: Alignment.centerLeft,
          child: barFill,
        ),
      ),
    );
  }
}

/// Cute cartoon speech bubble floating above a pet or mascot.
class GameSpeechBubble extends StatelessWidget {
  final String text;
  final Color accentColor;

  const GameSpeechBubble({
    super.key,
    required this.text,
    this.accentColor = MamPetColors.coralPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? MamPetColors.darkSurfaceAlt : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.65),
              width: 1.8,
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.16),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : MamPetColors.espresso,
            ),
          ),
        ),
        CustomPaint(
          size: const Size(14, 7),
          painter: _BubbleTailPainter(
            fill: isDark ? MamPetColors.darkSurfaceAlt : Colors.white,
            stroke: accentColor.withValues(alpha: 0.65),
          ),
        ),
      ],
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  final Color fill;
  final Color stroke;
  const _BubbleTailPainter({required this.fill, required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = fill);
    final edge = Path()
      ..moveTo(1, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width - 1, 0);
    canvas.drawPath(
      edge,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter old) => false;
}

/// Rotating sunlit rays backdrop for hatching / ready eggs & celebration screens!
class SunburstRaysPainter extends CustomPainter {
  final Color color;
  final double rotation;

  const SunburstRaysPainter({required this.color, required this.rotation});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * 0.55;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.34),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    const rayCount = 12;
    const sweep = math.pi / rayCount;
    for (int i = 0; i < rayCount; i++) {
      final start = i * 2 * sweep;
      final path = Path()
        ..moveTo(0, 0)
        ..arcTo(
          Rect.fromCircle(center: Offset.zero, radius: radius),
          start,
          sweep * 0.9,
          false,
        )
        ..close();
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SunburstRaysPainter old) =>
      old.rotation != rotation || old.color != color;
}
