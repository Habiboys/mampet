import 'dart:ui';

import '../../../core/domain/enums.dart';

/// Honest quality classification for every monster rig in the MamPet collection.
enum RigTier {
  /// Full multi-part anatomical separation (head, body, wings/tail/ears/limbs + expressions)
  /// verified via visual comparison sheet with zero seams or broken joints.
  fullLayered('full_layered', 'Full Layered Rig'),

  /// Clean facial expression rig (blinking, happy, sleep, eating) + elastic body motion
  /// where dense overlapping art requires manual artist inpainting for limb separation.
  partialRig('partial_rig', 'Partial Facial + Body Rig'),

  /// Lightweight single-layer breathing / squash-and-stretch fallback animation.
  wholeBody('whole_body', 'Whole-Body Animation'),

  /// Source artwork is missing, blank, or duplicated and requires manual artist creation.
  needsManualArt('needs_manual_art', 'Needs Manual Art');

  const RigTier(this.code, this.label);
  final String code;
  final String label;

  static RigTier fromCode(String? code) {
    for (final tier in RigTier.values) {
      if (tier.code == code) return tier;
    }
    return RigTier.wholeBody;
  }
}

/// Single drawable transparent layer inside a [MonsterRig].
class RigLayer {
  final String id;
  final String asset;
  final int zIndex;

  /// Normalized pivot coordinate in `[0.0 .. 1.0]` relative to canvas size.
  final Offset pivot;

  /// Parent layer id for hierarchical transform inheritance, or `null` for root.
  final String? parent;

  /// Optional mutually-exclusive slot name (e.g. `'eyes'`, `'mouth'`).
  final String? slot;

  /// Whether this layer is visible by default when no state overrides its slot.
  final bool defaultVisible;

  const RigLayer({
    required this.id,
    required this.asset,
    required this.zIndex,
    required this.pivot,
    this.parent,
    this.slot,
    this.defaultVisible = true,
  });

  factory RigLayer.fromJson(Map<String, dynamic> json) {
    final pivotList = (json['pivot'] as List<dynamic>?) ?? const [0.5, 0.5];
    final px = (pivotList.isNotEmpty ? (pivotList[0] as num).toDouble() : 0.5)
        .clamp(0.0, 1.0);
    final py = (pivotList.length > 1 ? (pivotList[1] as num).toDouble() : 0.5)
        .clamp(0.0, 1.0);
    return RigLayer(
      id: json['id'] as String,
      asset: json['asset'] as String,
      zIndex: (json['z_index'] as num?)?.toInt() ?? 0,
      pivot: Offset(px, py),
      parent: json['parent'] as String?,
      slot: json['slot'] as String?,
      defaultVisible: (json['default_visible'] as bool?) ?? true,
    );
  }
}

/// Interactive touch hitbox defined in normalized `[0.0 .. 1.0]` canvas space.
class RigHitbox {
  final String part;

  /// `[left, top, width, height]` normalized in `0.0 .. 1.0`.
  final Rect rect;

  /// Preferred reaction animation code (`'pet'`, `'play'`, `'happy'`, etc.).
  final String reaction;

  const RigHitbox({
    required this.part,
    required this.rect,
    required this.reaction,
  });

  factory RigHitbox.fromJson(Map<String, dynamic> json) {
    final r = (json['rect'] as List<dynamic>?) ?? const [0.15, 0.15, 0.7, 0.7];
    final left = r.isNotEmpty ? (r[0] as num).toDouble() : 0.15;
    final top = r.length > 1 ? (r[1] as num).toDouble() : 0.15;
    final width = r.length > 2 ? (r[2] as num).toDouble() : 0.7;
    final height = r.length > 3 ? (r[3] as num).toDouble() : 0.7;
    return RigHitbox(
      part: (json['part'] as String?) ?? 'body',
      rect: Rect.fromLTWH(left, top, width, height),
      reaction: (json['reaction'] as String?) ?? 'happy',
    );
  }
}

/// Data-driven 2D character rig parsed from `assets/monsters/<slug>/<stage>/rig.json`.
class MonsterRig {
  final String monsterId;
  final String stage;
  final RigTier rigTier;
  final String archetype;
  final double canvasWidth;
  final double canvasHeight;
  final List<RigLayer> layers;
  final List<RigHitbox> hitboxes;
  final List<String> animations;
  final String? notes;

  /// Base Flutter asset folder, e.g. `'assets/monsters/fire_dragon/baby'`.
  final String basePath;

  const MonsterRig({
    required this.monsterId,
    required this.stage,
    required this.rigTier,
    required this.archetype,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.layers,
    required this.hitboxes,
    required this.animations,
    required this.basePath,
    this.notes,
  });

  bool get hasRigLayers => layers.isNotEmpty && rigTier != RigTier.needsManualArt;

  /// Resolves a layer's relative asset path (e.g. `'layers/head.png'`) into a full
  /// Flutter asset bundle path.
  String resolveLayerAsset(RigLayer layer) {
    if (layer.asset.startsWith('assets/')) return layer.asset;
    return '$basePath/${layer.asset}';
  }

  /// Lightweight static preview asset path used as fallback or in MonsterDex grids.
  String get staticPreviewAsset => 'assets/monsters/$monsterId/$stage.png';

  /// Sorted copy of layers by ascending [RigLayer.zIndex] for deterministic painting.
  List<RigLayer> get sortedLayers {
    final copy = List<RigLayer>.from(layers);
    copy.sort((a, b) => a.zIndex.compareTo(b.zIndex));
    return copy;
  }

  /// Looks up a layer by id.
  RigLayer? layerById(String id) {
    for (final l in layers) {
      if (l.id == id) return l;
    }
    return null;
  }

  factory MonsterRig.fromJson(
    Map<String, dynamic> json, {
    required String basePath,
  }) {
    final canvas = (json['canvas_size'] as List<dynamic>?) ?? const [1024, 1024];
    final cw = canvas.isNotEmpty ? (canvas[0] as num).toDouble() : 1024.0;
    final ch = canvas.length > 1 ? (canvas[1] as num).toDouble() : 1024.0;

    final rawLayers = (json['layers'] as List<dynamic>?) ?? const [];
    final rawHitboxes = (json['hitboxes'] as List<dynamic>?) ?? const [];
    final rawAnims = (json['animations'] as List<dynamic>?) ?? const [];

    return MonsterRig(
      monsterId: (json['monster_id'] as String?) ?? 'unknown',
      stage: (json['stage'] as String?) ?? 'baby',
      rigTier: RigTier.fromCode(json['rig_tier'] as String?),
      archetype: (json['archetype'] as String?) ?? 'generic',
      canvasWidth: cw,
      canvasHeight: ch,
      layers: rawLayers
          .map((e) => RigLayer.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      hitboxes: rawHitboxes
          .map((e) => RigHitbox.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      animations: rawAnims.map((e) => e.toString()).toList(growable: false),
      basePath: basePath,
      notes: json['notes'] as String?,
    );
  }

  /// Creates a safe single-layer fallback rig pointing directly to the static
  /// preview sprite (`assets/monsters/<slug>/<stage>.png`) when no layered rig exists.
  factory MonsterRig.fallback({
    required String slug,
    required EvolutionPhase stage,
    String? notes,
  }) {
    final stageCode = stage.code;
    return MonsterRig(
      monsterId: slug,
      stage: stageCode,
      rigTier: RigTier.wholeBody,
      archetype: 'whole_body_fallback',
      canvasWidth: 1024,
      canvasHeight: 1024,
      layers: [
        RigLayer(
          id: 'body',
          asset: 'assets/monsters/$slug/$stageCode.png',
          zIndex: 5,
          pivot: const Offset(0.5, 0.82),
        ),
      ],
      hitboxes: const [
        RigHitbox(
          part: 'head',
          rect: Rect.fromLTWH(0.22, 0.14, 0.56, 0.36),
          reaction: 'pet',
        ),
        RigHitbox(
          part: 'body',
          rect: Rect.fromLTWH(0.18, 0.45, 0.64, 0.44),
          reaction: 'happy',
        ),
      ],
      animations: const ['idle', 'happy', 'pet', 'eat', 'sleep', 'play', 'evolve'],
      basePath: 'assets/monsters/$slug/$stageCode',
      notes: notes,
    );
  }

  /// Maps either a MamPet species ID (`'01'`..`'20'`), a species slug (`'fire_dragon'`),
  /// or an asset path (`'assets/monsters/fire_dragon/baby.png'`) into the canonical slug.
  static String resolveSlug(String monsterIdOrSlug) {
    final cleaned = monsterIdOrSlug.trim();
    if (_idToSlug.containsKey(cleaned)) {
      return _idToSlug[cleaned]!;
    }
    if (cleaned.startsWith('assets/monsters/')) {
      final parts = cleaned.split('/');
      if (parts.length >= 3) return parts[2];
    }
    return cleaned;
  }

  /// Authoritative mapping of all 20 MamPet species IDs to folder slugs.
  static const Map<String, String> _idToSlug = {
    '01': 'fire_dragon',
    '02': 'leaf_gorilla',
    '03': 'sky_bird',
    '04': 'fox',
    '05': 'water_slime',
    '06': 'leaf_spirit',
    '07': 'pink_axolotl',
    '08': 'dessert_panda',
    '09': 'lamb',
    '10': 'bread_turtle',
    '11': 'sea_dragon',
    '12': 'moss_golem',
    '13': 'dessert_ghost',
    '14': 'bee_moth',
    '15': 'ice_fox',
    '16': 'forest_deer',
    '17': 'chef_penguin',
    '18': 'mage_cat',
    '19': 'mushroom',
    '20': 'bamboo_panda',
  };

  /// All 20 species slugs in MamPet collection order (`01`..`20`).
  static const List<String> allSlugs = [
    'fire_dragon',
    'leaf_gorilla',
    'sky_bird',
    'fox',
    'water_slime',
    'leaf_spirit',
    'pink_axolotl',
    'dessert_panda',
    'lamb',
    'bread_turtle',
    'sea_dragon',
    'moss_golem',
    'dessert_ghost',
    'bee_moth',
    'ice_fox',
    'forest_deer',
    'chef_penguin',
    'mage_cat',
    'mushroom',
    'bamboo_panda',
  ];
}
