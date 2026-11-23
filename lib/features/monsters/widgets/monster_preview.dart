import 'package:flutter/material.dart';

import '../../../core/domain/enums.dart';
import '../models/monster_rig.dart';

/// Lightweight static monster preview widget intended for dense lists and
/// MonsterDex grids (zero tickers, low decoded bitmap memory footprint).
class MonsterPreview extends StatelessWidget {
  final String monsterId;
  final EvolutionPhase evolutionStage;
  final double size;
  final bool isLocked;
  final String? semanticLabel;

  const MonsterPreview({
    super.key,
    required this.monsterId,
    required this.evolutionStage,
    this.size = 96,
    this.isLocked = false,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final slug = MonsterRig.resolveSlug(monsterId);
    final assetPath = 'assets/monsters/$slug/${evolutionStage.code}.png';
    final cachePx = (size * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(96, 320);

    Widget img = Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      cacheWidth: cachePx,
      filterQuality: FilterQuality.medium,
      semanticLabel: semanticLabel,
      errorBuilder: (_, _, _) => SizedBox(
        width: size,
        height: size,
        child: const Icon(Icons.pets_rounded, size: 36, color: Colors.black26),
      ),
    );

    if (isLocked) {
      img = ColorFiltered(
        colorFilter: const ColorFilter.mode(Color(0xFF1F1612), BlendMode.srcIn),
        child: Opacity(opacity: 0.82, child: img),
      );
    }

    return SizedBox(width: size, height: size, child: img);
  }
}
