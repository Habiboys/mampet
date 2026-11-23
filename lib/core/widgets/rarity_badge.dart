import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../domain/enums.dart';

/// Color-blind accessible collectible rarity crest (shape icon + text label + color).
class RarityBadge extends StatelessWidget {
  final MonsterRarity rarity;
  final bool compact;

  const RarityBadge({
    super.key,
    required this.rarity,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Rarity ${rarity.displayName}',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 11,
          vertical: compact ? 3 : 4.5,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.white,
              rarity.cardSurface,
            ],
          ),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: rarity.borderColor,
            width: rarity == MonsterRarity.rare ? 2.0 : 1.5,
          ),
          boxShadow: rarity == MonsterRarity.rare
              ? [
                  BoxShadow(
                    color: rarity.borderColor.withValues(alpha: 0.3),
                    blurRadius: 6,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              rarity.shapeIcon,
              size: compact ? 11 : 13.5,
              color: rarity.textColor,
            ),
            const SizedBox(width: 4),
            Text(
              rarity.badgeLabel,
              style: TextStyle(
                fontFamily: 'Fredoka',
                fontSize: compact ? 9.5 : 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: rarity.textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Collectible trading-card frame with 3D bottom lip, diagonal sheen pattern,
/// holographic foil shimmer for Uncommon/Rare, and mysterious dark card back when locked.
class RarityCardFrame extends StatelessWidget {
  final MonsterRarity? rarity; // null when locked -> mysterious neutral dark card back
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool reduceMotion;

  const RarityCardFrame({
    super.key,
    required this.rarity,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.onTap,
    this.reduceMotion = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locked = rarity == null;
    final effectiveReduce =
        reduceMotion || MediaQuery.disableAnimationsOf(context);

    final Color borderColor;
    final Color lipColor;
    final double borderWidth;
    final Gradient bgGradient;
    final List<BoxShadow> shadows;

    if (locked) {
      bgGradient = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? const [Color(0xFF262E3D), Color(0xFF1A202C)]
            : const [Color(0xFFE7ECF2), Color(0xFFD5DDE8)],
      );
      borderColor = isDark ? const Color(0xFF3E4A5E) : const Color(0xFFB5C2D4);
      lipColor = isDark ? const Color(0xFF11161F) : const Color(0xFFA8B6C9);
      borderWidth = 2.0;
      shadows = [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ];
    } else if (rarity == MonsterRarity.rare) {
      bgGradient = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? const [Color(0xFF3B2264), Color(0xFF231838)]
            : const [Color(0xFFF6EEFF), Color(0xFFE9DBFF), Color(0xFFFFF4FD)],
      );
      borderColor = const Color(0xFF8B5CF6);
      lipColor = const Color(0xFF6D28D9);
      borderWidth = 3.0;
      shadows = [
        BoxShadow(
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.34),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ];
    } else if (rarity == MonsterRarity.uncommon) {
      bgGradient = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? const [Color(0xFF13403D), Color(0xFF1A2929)]
            : const [Color(0xFFEAFCF8), Color(0xFFD5F7F0)],
      );
      borderColor = const Color(0xFF14B8A6);
      lipColor = const Color(0xFF0F766E);
      borderWidth = 2.4;
      shadows = [
        BoxShadow(
          color: const Color(0xFF14B8A6).withValues(alpha: 0.22),
          blurRadius: 12,
          offset: const Offset(0, 5),
        ),
      ];
    } else {
      bgGradient = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? const [Color(0xFF2B2523), Color(0xFF211C1A)]
            : const [Color(0xFFFFFDFA), Color(0xFFF3EEE6)],
      );
      borderColor = const Color(0xFF94A3B8);
      lipColor = const Color(0xFF64748B);
      borderWidth = 2.0;
      shadows = [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ];
    }

    Widget cardInner = Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: bgGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(
        children: [
          // Subtle corner stars on Rare / Uncommon cards
          if (!locked && rarity == MonsterRarity.rare) ...[
            Positioned(
              right: 2,
              bottom: 24,
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 16,
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.38),
              ),
            ),
            Positioned(
              left: 2,
              top: 26,
              child: Icon(
                Icons.star_rounded,
                size: 13,
                color: const Color(0xFFF5A623).withValues(alpha: 0.55),
              ),
            ),
          ] else if (!locked && rarity == MonsterRarity.uncommon)
            Positioned(
              right: 2,
              bottom: 26,
              child: Icon(
                Icons.hexagon_outlined,
                size: 15,
                color: const Color(0xFF14B8A6).withValues(alpha: 0.35),
              ),
            ),
          child,
        ],
      ),
    );

    // Holographic foil sweep on Uncommon & Rare cards!
    if (!locked &&
        !effectiveReduce &&
        (rarity == MonsterRarity.rare || rarity == MonsterRarity.uncommon)) {
      cardInner = cardInner
          .animate(onPlay: (c) => c.repeat())
          .shimmer(
            delay: rarity == MonsterRarity.rare ? 1600.ms : 2800.ms,
            duration: 1300.ms,
            color: rarity == MonsterRarity.rare
                ? const Color(0xFFFFE082).withValues(alpha: 0.32)
                : Colors.white.withValues(alpha: 0.38),
          );
    }

    return Container(
      padding: const EdgeInsets.only(bottom: 5),
      decoration: BoxDecoration(
        color: lipColor,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: shadows,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onTap!();
                  },
            child: cardInner,
          ),
        ),
      ),
    );
  }
}
