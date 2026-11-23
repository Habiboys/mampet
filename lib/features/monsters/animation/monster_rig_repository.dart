import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../core/domain/enums.dart';
import '../models/monster_rig.dart';
import 'monster_animation_config.dart';

/// Loaded pair of data-driven rig geometry and animation curves for a character.
class LoadedMonsterRig {
  final MonsterRig rig;
  final MonsterAnimationConfig animations;

  const LoadedMonsterRig({
    required this.rig,
    required this.animations,
  });
}

/// Lightweight in-memory cached loader for `rig.json` and `animations.json`.
/// Gracefully falls back to whole-body static sprite animation if a rig asset
/// is absent or marked `needs_manual_art`, ensuring zero runtime crashes.
class MonsterRigRepository {
  MonsterRigRepository._();

  static final Map<String, LoadedMonsterRig> _cache = {};
  static final Map<String, Future<LoadedMonsterRig>> _inFlight = {};

  static String _cacheKey(String slug, EvolutionPhase stage) =>
      '$slug/${stage.code}';

  static LoadedMonsterRig? getCached(String monsterIdOrSlug, EvolutionPhase stage) {
    final slug = MonsterRig.resolveSlug(monsterIdOrSlug);
    return _cache[_cacheKey(slug, stage)];
  }

  static Future<LoadedMonsterRig> load(
    String monsterIdOrSlug,
    EvolutionPhase stage, {
    AssetBundle? bundle,
  }) {
    final slug = MonsterRig.resolveSlug(monsterIdOrSlug);
    final key = _cacheKey(slug, stage);
    final existing = _cache[key];
    if (existing != null) return Future.value(existing);

    final pending = _inFlight[key];
    if (pending != null) return pending;

    final future = _loadFromBundle(slug, stage, bundle ?? rootBundle).then((res) {
      _cache[key] = res;
      _inFlight.remove(key);
      return res;
    });
    _inFlight[key] = future;
    return future;
  }

  static Future<LoadedMonsterRig> _loadFromBundle(
    String slug,
    EvolutionPhase stage,
    AssetBundle bundle,
  ) async {
    final basePath = 'assets/monsters/$slug/${stage.code}';
    MonsterRig rig;
    MonsterAnimationConfig animations;

    try {
      final rigRaw = await bundle.loadString('$basePath/rig.json');
      final rigJson = jsonDecode(rigRaw) as Map<String, dynamic>;
      rig = MonsterRig.fromJson(rigJson, basePath: basePath);
    } catch (_) {
      rig = MonsterRig.fallback(
        slug: slug,
        stage: stage,
        notes: 'Fallback whole-body rig (rig.json not bundled)',
      );
    }

    try {
      final animRaw = await bundle.loadString('$basePath/animations.json');
      final animJson = jsonDecode(animRaw) as Map<String, dynamic>;
      animations = MonsterAnimationConfig.fromJson(animJson);
    } catch (_) {
      animations = MonsterAnimationConfig.fallback(
        slug: slug,
        stage: stage.code,
      );
    }

    return LoadedMonsterRig(rig: rig, animations: animations);
  }

  /// Clears cached rig definitions (useful in tests or hot reload checks).
  static void clearCache() {
    _cache.clear();
    _inFlight.clear();
  }
}
