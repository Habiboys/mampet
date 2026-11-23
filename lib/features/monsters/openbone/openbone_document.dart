import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Binary blob extracted directly from an OpenBone `.obonb` `data` tag (tag 10).
class OpenBoneBinaryBlob {
  final String mimeType;
  final Uint8List bytes;

  const OpenBoneBinaryBlob(this.mimeType, this.bytes);
}

/// Entry from `assets/animated_monsters/collection_manifest.json`.
class OpenBoneFormEntry {
  final String monsterId;
  final String monsterSlug;
  final String monsterName;
  final String stage;
  final String element;
  final String rarity;
  final String sourceAsset;

  /// `'exported'`, `'review_only'`, or `'source_blocked'`.
  final String status;

  /// Relative path to `animation_manifest.json` inside `assets/animated_monsters/`.
  final String? manifestRelPath;
  final bool eyesAttachment;
  final bool mouthAttachment;
  final String? reason;

  const OpenBoneFormEntry({
    required this.monsterId,
    required this.monsterSlug,
    required this.monsterName,
    required this.stage,
    required this.element,
    required this.rarity,
    required this.sourceAsset,
    required this.status,
    this.manifestRelPath,
    this.eyesAttachment = false,
    this.mouthAttachment = false,
    this.reason,
  });

  bool get isExported => status == 'exported' && manifestRelPath != null;
  bool get isReviewOnly => status == 'review_only';
  bool get isSourceBlocked => status == 'source_blocked';

  String get key => '$monsterSlug/$stage';

  String? get fullManifestAssetPath =>
      manifestRelPath == null ? null : 'assets/animated_monsters/$manifestRelPath';

  factory OpenBoneFormEntry.fromJson(Map<String, dynamic> json) {
    return OpenBoneFormEntry(
      monsterId: (json['monster_id'] ?? '').toString(),
      monsterSlug: (json['monster_slug'] ?? '').toString(),
      monsterName: (json['monster_name'] ?? '').toString(),
      stage: (json['stage'] ?? '').toString(),
      element: (json['element'] ?? '').toString(),
      rarity: (json['rarity'] ?? '').toString(),
      sourceAsset: (json['source_asset'] ?? '').toString(),
      status: (json['status'] ?? 'source_blocked').toString(),
      manifestRelPath: json['manifest'] as String?,
      eyesAttachment: (json['eyes_attachment'] as bool?) ?? false,
      mouthAttachment: (json['mouth_attachment'] as bool?) ?? false,
      reason: json['reason'] as String?,
    );
  }
}

/// Index parsed from `assets/animated_monsters/collection_manifest.json`.
class OpenBoneCollectionManifest {
  final int schemaVersion;
  final int totalForms;
  final Map<String, int> counts;
  final List<OpenBoneFormEntry> forms;
  final Map<String, OpenBoneFormEntry> byKey;

  OpenBoneCollectionManifest({
    required this.schemaVersion,
    required this.totalForms,
    required this.counts,
    required this.forms,
  }) : byKey = {for (final f in forms) f.key: f};

  OpenBoneFormEntry? lookup(String slug, String stage) => byKey['$slug/$stage'];

  int get exportedCount => counts['exported'] ?? 0;

  factory OpenBoneCollectionManifest.fromJson(Map<String, dynamic> json) {
    final rawCounts = (json['counts'] as Map<String, dynamic>?) ?? const {};
    final parsedCounts = <String, int>{
      for (final e in rawCounts.entries) e.key: (e.value as num).toInt(),
    };
    final rawForms = (json['forms'] as List<dynamic>?) ?? const [];
    final parsedForms = rawForms
        .whereType<Map<String, dynamic>>()
        .map(OpenBoneFormEntry.fromJson)
        .toList(growable: false);
    return OpenBoneCollectionManifest(
      schemaVersion: (json['schema_version'] as num?)?.toInt() ?? 1,
      totalForms: (json['total_forms'] as num?)?.toInt() ?? parsedForms.length,
      counts: parsedCounts,
      forms: parsedForms,
    );
  }
}

/// Clip metadata inside `<slug>/<stage>/animation_manifest.json`.
class OpenBoneClipMeta {
  final String name;
  final double durationSec;
  final bool loop;
  final String? trigger;

  const OpenBoneClipMeta({
    required this.name,
    required this.durationSec,
    required this.loop,
    this.trigger,
  });

  factory OpenBoneClipMeta.fromJson(String name, Map<String, dynamic> json) {
    return OpenBoneClipMeta(
      name: name,
      durationSec: (json['duration_sec'] as num?)?.toDouble() ?? 1.5,
      loop: (json['loop'] as bool?) ?? (name == 'idle' || name == 'sleep'),
      trigger: json['trigger'] as String?,
    );
  }
}

/// Facial expression revision metadata parsed from `animation_manifest.json`.
class OpenBoneExpressionRevision {
  final int version;
  final bool eyesRedrawnOpen;
  final bool mouthCavityRedrawn;
  final bool beakPreserved;
  final String? defaultEyes;
  final String? defaultMouth;

  const OpenBoneExpressionRevision({
    required this.version,
    required this.eyesRedrawnOpen,
    required this.mouthCavityRedrawn,
    required this.beakPreserved,
    this.defaultEyes,
    this.defaultMouth,
  });

  factory OpenBoneExpressionRevision.fromJson(Map<String, dynamic> json) {
    return OpenBoneExpressionRevision(
      version: (json['version'] as num?)?.toInt() ?? 1,
      eyesRedrawnOpen: (json['eyes_redrawn_open'] as bool?) ?? false,
      mouthCavityRedrawn: (json['mouth_cavity_redrawn'] as bool?) ?? false,
      beakPreserved: (json['beak_preserved'] as bool?) ?? false,
      defaultEyes: json['default_eyes'] as String?,
      defaultMouth: json['default_mouth'] as String?,
    );
  }
}

/// Per-form manifest parsed from `<slug>/<stage>/animation_manifest.json`.
class OpenBonePackageManifest {
  final String baseDirAssetPath;
  final String exportRelPath;
  final String? stateMachineName;
  final Map<String, OpenBoneClipMeta> clips;
  final OpenBoneExpressionRevision? expressionRevision;

  const OpenBonePackageManifest({
    required this.baseDirAssetPath,
    required this.exportRelPath,
    this.stateMachineName,
    required this.clips,
    this.expressionRevision,
  });

  String get exportAssetPath => '$baseDirAssetPath/$exportRelPath';

  factory OpenBonePackageManifest.fromJson(
    Map<String, dynamic> json, {
    required String baseDirAssetPath,
  }) {
    final exports = (json['exports'] as List<dynamic>?) ?? const [];
    String exportRel = 'exports/character.obonb';
    for (final e in exports) {
      if (e is Map<String, dynamic> && e['path'] is String) {
        exportRel = e['path'] as String;
        if ((e['format'] ?? '') == 'obonb' || exportRel.endsWith('.obonb')) {
          break;
        }
      }
    }

    final sm = json['state_machine'] as Map<String, dynamic>?;
    final smName = sm?['name'] as String?;

    final rawClips = (json['clips'] as Map<String, dynamic>?) ?? const {};
    final parsedClips = <String, OpenBoneClipMeta>{};
    rawClips.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        parsedClips[key] = OpenBoneClipMeta.fromJson(key, value);
      }
    });

    final rawExpRev = json['expression_revision'];
    final expRev = rawExpRev is Map<String, dynamic>
        ? OpenBoneExpressionRevision.fromJson(rawExpRev)
        : null;

    return OpenBonePackageManifest(
      baseDirAssetPath: baseDirAssetPath,
      exportRelPath: exportRel,
      stateMachineName: smName,
      clips: parsedClips,
      expressionRevision: expRev,
    );
  }
}

/// Embedded PNG atlas page inside `.obonb`.
class OpenBoneAtlasPage {
  final String id;
  final String name;
  final int width;
  final int height;
  final Uint8List imageBytes;

  const OpenBoneAtlasPage({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    required this.imageBytes,
  });
}

/// Sub-rectangle of a packed image inside an [OpenBoneAtlasPage].
class OpenBoneAtlasRegion {
  final String imageId;
  final String pageId;
  final double x;
  final double y;
  final double width;
  final double height;
  final double offsetX;
  final double offsetY;
  final double originalWidth;
  final double originalHeight;
  final bool rotated;

  const OpenBoneAtlasRegion({
    required this.imageId,
    required this.pageId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.offsetX,
    required this.offsetY,
    required this.originalWidth,
    required this.originalHeight,
    required this.rotated,
  });

  bool get isTrimmed =>
      offsetX != 0 ||
      offsetY != 0 ||
      width != originalWidth ||
      height != originalHeight;

  /// Converts normalized attachment UVs (`[0..1]`) to atlas pixel coordinates.
  Float32List mapUvsToAtlasPixels(List<double> uvs) {
    final out = Float32List(uvs.length);
    for (int i = 0; i < uvs.length; i += 2) {
      final u = uvs[i];
      final v = uvs[i + 1];
      if (rotated) {
        out[i] = (x + height + offsetY) - v * originalHeight;
        out[i + 1] = (y - offsetX) + u * originalWidth;
      } else {
        out[i] = (x - offsetX) + u * originalWidth;
        out[i + 1] = (y - offsetY) + v * originalHeight;
      }
    }
    return out;
  }
}

/// Static bone definition in setup pose.
class OpenBoneBoneData {
  final int index;
  final String id;
  final String name;
  final String? parentId;
  final int parentIndex;
  final double length;
  final double x;
  final double y;
  final double rotation;
  final double scaleX;
  final double scaleY;
  final double shearX;
  final double shearY;
  final String inherit;

  const OpenBoneBoneData({
    required this.index,
    required this.id,
    required this.name,
    required this.parentId,
    required this.parentIndex,
    required this.length,
    required this.x,
    required this.y,
    required this.rotation,
    required this.scaleX,
    required this.scaleY,
    required this.shearX,
    required this.shearY,
    required this.inherit,
  });
}

/// Static slot definition in draw order.
class OpenBoneSlotData {
  final int index;
  final String id;
  final String name;
  final String boneId;
  final int boneIndex;
  final Float32List color;
  final String? attachment;
  final String blend;

  const OpenBoneSlotData({
    required this.index,
    required this.id,
    required this.name,
    required this.boneId,
    required this.boneIndex,
    required this.color,
    required this.attachment,
    required this.blend,
  });
}

/// Base class for OpenBone slot attachments.
sealed class OpenBoneAttachment {
  final String name;
  const OpenBoneAttachment(this.name);
}

/// Deformable weighted-bone triangle mesh attachment.
class OpenBoneMeshAttachment extends OpenBoneAttachment {
  final String imageId;
  final String? pageId;
  final int vertexCount;
  final Float32List setupVertices;
  final Float32List atlasTexCoords;
  final Uint16List triangles;
  final Float32List color;
  final bool hasWeights;

  // Flattened per-vertex bone weights for allocation-free 60 FPS LBS skinning.
  final Int32List weightOffsets;
  final Int32List weightCounts;
  final Int32List weightBoneIndices;
  final Float32List weightLocalX;
  final Float32List weightLocalY;
  final Float32List weightValues;

  const OpenBoneMeshAttachment({
    required String name,
    required this.imageId,
    required this.pageId,
    required this.vertexCount,
    required this.setupVertices,
    required this.atlasTexCoords,
    required this.triangles,
    required this.color,
    required this.hasWeights,
    required this.weightOffsets,
    required this.weightCounts,
    required this.weightBoneIndices,
    required this.weightLocalX,
    required this.weightLocalY,
    required this.weightValues,
  }) : super(name);
}

/// Rigid textured quad attachment bound to a single bone (e.g. eyes/mouth).
class OpenBoneRegionAttachment extends OpenBoneAttachment {
  final String imageId;
  final String? pageId;

  /// Precomputed 4 corners `[x0,y0, x1,y1, x2,y2, x3,y3]` in bone-local Y-up space.
  final Float32List localCorners;

  /// Precomputed 4 atlas pixel texture coords matching [localCorners].
  final Float32List atlasTexCoords;
  final Float32List color;

  static final Uint16List quadTriangles = Uint16List.fromList(const [0, 1, 2, 0, 2, 3]);

  const OpenBoneRegionAttachment({
    required String name,
    required this.imageId,
    required this.pageId,
    required this.localCorners,
    required this.atlasTexCoords,
    required this.color,
  }) : super(name);
}

/// Polygon hitbox attachment (e.g. `face_touch` on the `touch` slot).
class OpenBoneBoundingBoxAttachment extends OpenBoneAttachment {
  final Float32List vertices;
  final Float32List color;

  const OpenBoneBoundingBoxAttachment({
    required String name,
    required this.vertices,
    required this.color,
  }) : super(name);
}

enum OpenBoneCurveKind { linear, stepped, bezier }

/// Keyframe curve descriptor (`linear`, `stepped`, or cubic bezier `[cx1, cy1, cx2, cy2]`).
class OpenBoneCurve {
  final OpenBoneCurveKind kind;
  final double cx1;
  final double cy1;
  final double cx2;
  final double cy2;

  const OpenBoneCurve.linear()
      : kind = OpenBoneCurveKind.linear,
        cx1 = 0,
        cy1 = 0,
        cx2 = 1,
        cy2 = 1;

  const OpenBoneCurve.stepped()
      : kind = OpenBoneCurveKind.stepped,
        cx1 = 0,
        cy1 = 0,
        cx2 = 1,
        cy2 = 1;

  const OpenBoneCurve.bezier(this.cx1, this.cy1, this.cx2, this.cy2)
      : kind = OpenBoneCurveKind.bezier;

  double evaluate(double t) {
    if (kind == OpenBoneCurveKind.linear) return t;
    if (kind == OpenBoneCurveKind.stepped) return 0.0;
    // Exact 24-iteration bisection matching OpenBone 0.4.8 reference `on(o, e)`.
    double lo = 0.0;
    double hi = 1.0;
    double u = t;
    for (int i = 0; i < 24; i++) {
      final inv = 1.0 - u;
      final x = 3.0 * inv * inv * u * cx1 + 3.0 * inv * u * u * cx2 + u * u * u;
      final diff = x - t;
      if (diff.abs() < 1e-6) break;
      if (diff > 0) {
        hi = u;
      } else {
        lo = u;
      }
      u = (lo + hi) * 0.5;
    }
    final inv = 1.0 - u;
    return 3.0 * inv * inv * u * cy1 + 3.0 * inv * u * u * cy2 + u * u * u;
  }

  static OpenBoneCurve parse(dynamic raw) {
    if (raw == 'stepped') return const OpenBoneCurve.stepped();
    if (raw is List && raw.length >= 4) {
      return OpenBoneCurve.bezier(
        (raw[0] as num).toDouble(),
        (raw[1] as num).toDouble(),
        (raw[2] as num).toDouble(),
        (raw[3] as num).toDouble(),
      );
    }
    return const OpenBoneCurve.linear();
  }
}

enum OpenBoneBoneProperty { x, y, rotation, scaleX, scaleY, shearX, shearY }

/// Numeric keyframe timeline for a bone property.
class OpenBoneBoneTimeline {
  final int boneIndex;
  final String boneId;
  final OpenBoneBoneProperty property;
  final Float64List times;
  final Float64List values;
  final List<OpenBoneCurve> curves;

  const OpenBoneBoneTimeline({
    required this.boneIndex,
    required this.boneId,
    required this.property,
    required this.times,
    required this.values,
    required this.curves,
  });

  double evaluate(double time) {
    final len = times.length;
    if (len == 0) return 0.0;
    if (time <= times[0]) return values[0];
    if (time >= times[len - 1]) return values[len - 1];

    int lo = 0;
    int hi = len - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (times[mid] <= time) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final curve = curves[lo];
    if (curve.kind == OpenBoneCurveKind.stepped) return values[lo];
    final span = times[hi] - times[lo];
    final frac = span > 0 ? (time - times[lo]) / span : 0.0;
    final eased = curve.evaluate(frac);
    return values[lo] + (values[hi] - values[lo]) * eased;
  }
}

/// Attachment swap keyframe timeline for a slot (e.g. blinking eyes, chewing mouth).
class OpenBoneSlotAttachmentTimeline {
  final int slotIndex;
  final String slotId;
  final Float64List times;
  final List<String?> attachmentNames;

  const OpenBoneSlotAttachmentTimeline({
    required this.slotIndex,
    required this.slotId,
    required this.times,
    required this.attachmentNames,
  });

  String? evaluate(double time) {
    final len = times.length;
    if (len == 0) return null;
    if (time <= times[0]) return attachmentNames[0];
    if (time >= times[len - 1]) return attachmentNames[len - 1];

    int lo = 0;
    int hi = len - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (times[mid] <= time) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return attachmentNames[lo];
  }
}

/// Slot RGBA tint timeline.
class OpenBoneSlotColorTimeline {
  final int slotIndex;
  final String slotId;
  final Float64List times;
  final List<Float32List> colors;
  final List<OpenBoneCurve> curves;

  const OpenBoneSlotColorTimeline({
    required this.slotIndex,
    required this.slotId,
    required this.times,
    required this.colors,
    required this.curves,
  });

  Float32List evaluate(double time) {
    final len = times.length;
    if (len == 0) return Float32List.fromList(const [1, 1, 1, 1]);
    if (time <= times[0]) return colors[0];
    if (time >= times[len - 1]) return colors[len - 1];

    int lo = 0;
    int hi = len - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (times[mid] <= time) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final curve = curves[lo];
    if (curve.kind == OpenBoneCurveKind.stepped) return colors[lo];
    final span = times[hi] - times[lo];
    final frac = span > 0 ? (time - times[lo]) / span : 0.0;
    final t = curve.evaluate(frac);
    final a = colors[lo];
    final b = colors[hi];
    return Float32List.fromList([
      a[0] + (b[0] - a[0]) * t,
      a[1] + (b[1] - a[1]) * t,
      a[2] + (b[2] - a[2]) * t,
      a[3] + (b[3] - a[3]) * t,
    ]);
  }
}

/// Named animation clip containing bone and slot timelines.
class OpenBoneAnimation {
  final String id;
  final String name;
  final double duration;
  final List<OpenBoneBoneTimeline> boneTimelines;
  final List<OpenBoneSlotAttachmentTimeline> slotAttachmentTimelines;
  final List<OpenBoneSlotColorTimeline> slotColorTimelines;

  /// Fast lookup bitset/set of animated bone property keys (`boneIndex * 8 + prop.index`)
  /// used during OpenBone cross-fade blending.
  final Set<int> animatedBonePropKeys;
  final Set<int> animatedSlotColorIndices;

  OpenBoneAnimation({
    required this.id,
    required this.name,
    required this.duration,
    required this.boneTimelines,
    required this.slotAttachmentTimelines,
    required this.slotColorTimelines,
  })  : animatedBonePropKeys = {
          for (final tl in boneTimelines) tl.boneIndex * 8 + tl.property.index,
        },
        animatedSlotColorIndices = {
          for (final tl in slotColorTimelines) tl.slotIndex,
        };

  double sampleTime(double rawTime, bool loop) {
    if (duration <= 0) return 0.0;
    if (loop) {
      final m = rawTime % duration;
      return m < 0 ? m + duration : m;
    }
    return rawTime.clamp(0.0, duration);
  }
}

class OpenBoneSmInput {
  final String id;
  final String name;
  final String type;
  final dynamic defaultValue;

  const OpenBoneSmInput({
    required this.id,
    required this.name,
    required this.type,
    required this.defaultValue,
  });
}

class OpenBoneSmState {
  final String id;
  final String name;
  final String type;
  final String? animationId;
  final bool loop;
  final double speed;
  final String? onComplete;

  const OpenBoneSmState({
    required this.id,
    required this.name,
    required this.type,
    this.animationId,
    required this.loop,
    required this.speed,
    this.onComplete,
  });
}

class OpenBoneSmCondition {
  final String inputId;
  final String op;
  final dynamic value;

  const OpenBoneSmCondition({
    required this.inputId,
    required this.op,
    required this.value,
  });
}

class OpenBoneSmTransition {
  final String id;
  final String from;
  final String to;
  final List<OpenBoneSmCondition> conditions;
  final double duration;
  final double? exitTime;

  const OpenBoneSmTransition({
    required this.id,
    required this.from,
    required this.to,
    required this.conditions,
    required this.duration,
    this.exitTime,
  });
}

class OpenBoneSmLayer {
  final String id;
  final String name;
  final String entryStateId;
  final List<OpenBoneSmState> states;
  final List<OpenBoneSmTransition> transitions;

  const OpenBoneSmLayer({
    required this.id,
    required this.name,
    required this.entryStateId,
    required this.states,
    required this.transitions,
  });

  OpenBoneSmState? stateById(String id) {
    for (final s in states) {
      if (s.id == id) return s;
    }
    return null;
  }

  OpenBoneSmState? stateByName(String name) {
    for (final s in states) {
      if (s.name == name) return s;
    }
    return null;
  }
}

class OpenBoneSmAction {
  final String type;
  final String? inputId;
  final dynamic value;

  const OpenBoneSmAction({
    required this.type,
    this.inputId,
    this.value,
  });
}

class OpenBoneSmListener {
  final String id;
  final String name;
  final String? slotId;
  final String event;
  final List<OpenBoneSmAction> actions;

  const OpenBoneSmListener({
    required this.id,
    required this.name,
    this.slotId,
    required this.event,
    required this.actions,
  });
}

class OpenBoneStateMachine {
  final String id;
  final String name;
  final List<OpenBoneSmInput> inputs;
  final List<OpenBoneSmLayer> layers;
  final List<OpenBoneSmListener> listeners;

  const OpenBoneStateMachine({
    required this.id,
    required this.name,
    required this.inputs,
    required this.layers,
    required this.listeners,
  });

  OpenBoneSmInput? findInput(String idOrName) {
    for (final i in inputs) {
      if (i.id == idOrName || i.name == idOrName) return i;
    }
    return null;
  }
}

/// Complete parsed OpenBone 0.4.8 document decoded from `.obonb` (or `.obone` JSON).
class OpenBoneDocument {
  final String name;
  final double width;
  final double height;
  final double originX;
  final double originY;
  final double fps;
  final List<OpenBoneBoneData> bones;
  final List<OpenBoneSlotData> slots;

  /// `attachments[slotIndex][attachmentName]` for the default skin.
  final List<Map<String, OpenBoneAttachment>> slotAttachments;
  final List<OpenBoneAnimation> animations;
  final Map<String, OpenBoneAnimation> animationByIdOrName;
  final List<OpenBoneStateMachine> stateMachines;
  final List<OpenBoneAtlasPage> atlasPages;
  final Map<String, OpenBoneAtlasPage> atlasPageById;

  OpenBoneDocument({
    required this.name,
    required this.width,
    required this.height,
    required this.originX,
    required this.originY,
    required this.fps,
    required this.bones,
    required this.slots,
    required this.slotAttachments,
    required this.animations,
    required this.stateMachines,
    required this.atlasPages,
  })  : animationByIdOrName = {
          for (final a in animations) a.id: a,
          for (final a in animations) a.name: a,
        },
        atlasPageById = {for (final p in atlasPages) p.id: p};

  int get totalMeshVertices {
    int count = 0;
    for (final slotMap in slotAttachments) {
      for (final att in slotMap.values) {
        if (att is OpenBoneMeshAttachment) count += att.vertexCount;
      }
    }
    return count;
  }

  int get totalMeshTriangles {
    int count = 0;
    for (final slotMap in slotAttachments) {
      for (final att in slotMap.values) {
        if (att is OpenBoneMeshAttachment) count += att.triangles.length ~/ 3;
      }
    }
    return count;
  }

  /// Parses either a packed binary `.obonb` buffer (`OBNB` magic header) or a UTF-8 `.obone` JSON buffer.
  factory OpenBoneDocument.fromBytes(Uint8List bytes) {
    if (_isObonb(bytes)) {
      final raw = _decodeObonb(bytes);
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Root OpenBone binary value is not an object');
      }
      return OpenBoneDocument.fromRawMap(raw);
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Root OpenBone JSON value is not an object');
    }
    return OpenBoneDocument.fromRawMap(decoded);
  }

  factory OpenBoneDocument.fromRawMap(Map<String, dynamic> doc) {
    if (doc['format'] != 'openbone') {
      throw FormatException('Not an OpenBone document (format=${doc['format']})');
    }
    final version = (doc['version'] as num?)?.toInt() ?? 1;
    if (version > 1) {
      throw FormatException('Unsupported OpenBone document version $version');
    }

    final width = (doc['width'] as num?)?.toDouble() ?? 1024.0;
    final height = (doc['height'] as num?)?.toDouble() ?? 1024.0;
    final originX = (doc['originX'] as num?)?.toDouble() ?? (width * 0.5);
    final originY = (doc['originY'] as num?)?.toDouble() ?? (height * 0.85);
    final fps = (doc['fps'] as num?)?.toDouble() ?? 30.0;

    // 1. Parse embedded atlas pages & packed regions
    final atlas = doc['atlas'] as Map<String, dynamic>?;
    final atlasPages = <OpenBoneAtlasPage>[];
    final atlasPageIds = <String>{};
    if (atlas != null) {
      final rawPages = (atlas['pages'] as List<dynamic>?) ?? const [];
      for (final p in rawPages) {
        if (p is! Map<String, dynamic>) continue;
        final src = p['src'];
        Uint8List? pngBytes;
        if (src is OpenBoneBinaryBlob) {
          pngBytes = src.bytes;
        } else if (src is String && src.startsWith('data:')) {
          final comma = src.indexOf(',');
          if (comma > 0) {
            pngBytes = base64Decode(src.substring(comma + 1));
          }
        }
        if (pngBytes == null || pngBytes.isEmpty) continue;
        final id = (p['id'] ?? '').toString();
        atlasPageIds.add(id);
        atlasPages.add(
          OpenBoneAtlasPage(
            id: id,
            name: (p['name'] ?? id).toString(),
            width: (p['width'] as num?)?.toInt() ?? 512,
            height: (p['height'] as num?)?.toInt() ?? 512,
            imageBytes: pngBytes,
          ),
        );
      }
    }

    final regionByImageId = <String, OpenBoneAtlasRegion>{};
    if (atlas != null) {
      final rawRegions = (atlas['regions'] as List<dynamic>?) ?? const [];
      for (final r in rawRegions) {
        if (r is! Map<String, dynamic>) continue;
        final pageId = (r['page'] ?? '').toString();
        if (!atlasPageIds.contains(pageId)) continue;
        final imageId = (r['image'] ?? '').toString();
        final rw = (r['width'] as num?)?.toDouble() ?? 0.0;
        final rh = (r['height'] as num?)?.toDouble() ?? 0.0;
        regionByImageId[imageId] = OpenBoneAtlasRegion(
          imageId: imageId,
          pageId: pageId,
          x: (r['x'] as num?)?.toDouble() ?? 0.0,
          y: (r['y'] as num?)?.toDouble() ?? 0.0,
          width: rw,
          height: rh,
          offsetX: (r['offsetX'] as num?)?.toDouble() ?? 0.0,
          offsetY: (r['offsetY'] as num?)?.toDouble() ?? 0.0,
          originalWidth: (r['originalWidth'] as num?)?.toDouble() ?? rw,
          originalHeight: (r['originalHeight'] as num?)?.toDouble() ?? rh,
          rotated: (r['rotated'] as bool?) ?? false,
        );
      }
    }

    // 2. Parse bones (resolving parent indices cleanly)
    final skeleton = (doc['skeleton'] as Map<String, dynamic>?) ?? const {};
    final rawBones = (skeleton['bones'] as List<dynamic>?) ?? const [];
    final boneIndexById = <String, int>{};
    for (int i = 0; i < rawBones.length; i++) {
      final b = rawBones[i] as Map<String, dynamic>;
      boneIndexById[(b['id'] ?? '').toString()] = i;
    }

    final bones = <OpenBoneBoneData>[];
    for (int i = 0; i < rawBones.length; i++) {
      final b = rawBones[i] as Map<String, dynamic>;
      final parentId = b['parent'] as String?;
      bones.add(
        OpenBoneBoneData(
          index: i,
          id: (b['id'] ?? '').toString(),
          name: (b['name'] ?? '').toString(),
          parentId: parentId,
          parentIndex: parentId != null ? (boneIndexById[parentId] ?? -1) : -1,
          length: (b['length'] as num?)?.toDouble() ?? 0.0,
          x: (b['x'] as num?)?.toDouble() ?? 0.0,
          y: (b['y'] as num?)?.toDouble() ?? 0.0,
          rotation: (b['rotation'] as num?)?.toDouble() ?? 0.0,
          scaleX: (b['scaleX'] as num?)?.toDouble() ?? 1.0,
          scaleY: (b['scaleY'] as num?)?.toDouble() ?? 1.0,
          shearX: (b['shearX'] as num?)?.toDouble() ?? 0.0,
          shearY: (b['shearY'] as num?)?.toDouble() ?? 0.0,
          inherit: (b['inherit'] ?? 'normal').toString(),
        ),
      );
    }

    // 3. Parse slots
    final rawSlots = (skeleton['slots'] as List<dynamic>?) ?? const [];
    final slots = <OpenBoneSlotData>[];
    final slotIndexById = <String, int>{};
    for (int i = 0; i < rawSlots.length; i++) {
      final s = rawSlots[i] as Map<String, dynamic>;
      final id = (s['id'] ?? '').toString();
      final boneId = (s['bone'] ?? '').toString();
      final boneIdx = boneIndexById[boneId] ?? 0;
      slotIndexById[id] = slots.length;
      slots.add(
        OpenBoneSlotData(
          index: slots.length,
          id: id,
          name: (s['name'] ?? id).toString(),
          boneId: boneId,
          boneIndex: boneIdx,
          color: parseHexColor((s['color'] as String?) ?? '#ffffff'),
          attachment: s['attachment'] as String?,
          blend: (s['blend'] ?? 'normal').toString(),
        ),
      );
    }

    // 4. Parse default skin attachments
    final slotAttachments = List<Map<String, OpenBoneAttachment>>.generate(
      slots.length,
      (_) => <String, OpenBoneAttachment>{},
      growable: false,
    );
    final rawSkins = (skeleton['skins'] as List<dynamic>?) ?? const [];
    if (rawSkins.isNotEmpty) {
      final skin0 = rawSkins.first as Map<String, dynamic>;
      final attsBySlot = (skin0['attachments'] as Map<String, dynamic>?) ?? const {};
      attsBySlot.forEach((slotId, slotMap) {
        final slotIdx = slotIndexById[slotId];
        if (slotIdx == null || slotMap is! Map<String, dynamic>) return;
        slotMap.forEach((attName, rawAtt) {
          if (rawAtt is! Map<String, dynamic>) return;
          final parsed = _parseAttachment(
            attName,
            rawAtt,
            boneIndexById,
            regionByImageId,
          );
          if (parsed != null) {
            slotAttachments[slotIdx][attName] = parsed;
          }
        });
      });
    }

    // 5. Parse animations
    final rawAnims = (doc['animations'] as List<dynamic>?) ?? const [];
    final animations = <OpenBoneAnimation>[];
    for (final rawA in rawAnims) {
      if (rawA is! Map<String, dynamic>) continue;
      animations.add(
        _parseAnimation(rawA, boneIndexById, slotIndexById),
      );
    }

    // 6. Parse state machines
    final rawSms = (doc['stateMachines'] as List<dynamic>?) ?? const [];
    final stateMachines = <OpenBoneStateMachine>[];
    for (final rawSm in rawSms) {
      if (rawSm is! Map<String, dynamic>) continue;
      stateMachines.add(_parseStateMachine(rawSm));
    }

    return OpenBoneDocument(
      name: (doc['name'] ?? 'OpenBone Character').toString(),
      width: width,
      height: height,
      originX: originX,
      originY: originY,
      fps: fps,
      bones: bones,
      slots: slots,
      slotAttachments: slotAttachments,
      animations: animations,
      stateMachines: stateMachines,
      atlasPages: atlasPages,
    );
  }

  static OpenBoneAttachment? _parseAttachment(
    String name,
    Map<String, dynamic> raw,
    Map<String, int> boneIndexById,
    Map<String, OpenBoneAtlasRegion> regionByImageId,
  ) {
    final type = (raw['type'] ?? '').toString();
    switch (type) {
      case 'mesh':
        final imageId = (raw['image'] ?? '').toString();
        final region = regionByImageId[imageId];
        final rawVerts = (raw['vertices'] as List<dynamic>?) ?? const [];
        final rawUvs = (raw['uvs'] as List<dynamic>?) ?? const [];
        final rawTris = (raw['triangles'] as List<dynamic>?) ?? const [];
        final vertexCount = rawVerts.length ~/ 2;

        final setupVerts = Float32List(vertexCount * 2);
        for (int i = 0; i < vertexCount * 2; i++) {
          setupVerts[i] = (rawVerts[i] as num).toDouble();
        }

        final uvDoubles = List<double>.generate(
          rawUvs.length,
          (i) => (rawUvs[i] as num).toDouble(),
          growable: false,
        );
        final atlasTexCoords = region != null
            ? region.mapUvsToAtlasPixels(uvDoubles)
            : Float32List.fromList(uvDoubles);

        final triangles = Uint16List(rawTris.length);
        for (int i = 0; i < rawTris.length; i++) {
          triangles[i] = (rawTris[i] as num).toInt();
        }

        final rawWeights = raw['weights'] as List<dynamic>?;
        final hasWeights = rawWeights != null && rawWeights.length == vertexCount;
        final wOffsets = Int32List(hasWeights ? vertexCount : 0);
        final wCounts = Int32List(hasWeights ? vertexCount : 0);

        int totalWeights = 0;
        if (hasWeights) {
          for (int v = 0; v < vertexCount; v++) {
            final list = rawWeights[v] as List<dynamic>;
            wOffsets[v] = totalWeights;
            wCounts[v] = list.length;
            totalWeights += list.length;
          }
        }

        final wBoneIndices = Int32List(totalWeights);
        final wLocalX = Float32List(totalWeights);
        final wLocalY = Float32List(totalWeights);
        final wVals = Float32List(totalWeights);

        if (hasWeights) {
          int cursor = 0;
          for (int v = 0; v < vertexCount; v++) {
            final list = rawWeights[v] as List<dynamic>;
            for (final item in list) {
              final m = item as Map<String, dynamic>;
              wBoneIndices[cursor] = boneIndexById[(m['bone'] ?? '').toString()] ?? -1;
              wLocalX[cursor] = (m['x'] as num).toDouble();
              wLocalY[cursor] = (m['y'] as num).toDouble();
              wVals[cursor] = (m['weight'] as num).toDouble();
              cursor++;
            }
          }
        }

        return OpenBoneMeshAttachment(
          name: (raw['name'] as String?) ?? name,
          imageId: imageId,
          pageId: region?.pageId,
          vertexCount: vertexCount,
          setupVertices: setupVerts,
          atlasTexCoords: atlasTexCoords,
          triangles: triangles,
          color: parseHexColor((raw['color'] as String?) ?? '#ffffff'),
          hasWeights: hasWeights,
          weightOffsets: wOffsets,
          weightCounts: wCounts,
          weightBoneIndices: wBoneIndices,
          weightLocalX: wLocalX,
          weightLocalY: wLocalY,
          weightValues: wVals,
        );

      case 'region':
        final imageId = (raw['image'] ?? '').toString();
        final region = regionByImageId[imageId];
        final rx = (raw['x'] as num?)?.toDouble() ?? 0.0;
        final ry = (raw['y'] as num?)?.toDouble() ?? 0.0;
        final rotRad = ((raw['rotation'] as num?)?.toDouble() ?? 0.0) * math.pi / 180.0;
        final sx = (raw['scaleX'] as num?)?.toDouble() ?? 1.0;
        final sy = (raw['scaleY'] as num?)?.toDouble() ?? 1.0;
        final hw = ((raw['width'] as num?)?.toDouble() ?? 0.0) * 0.5 * sx;
        final hh = ((raw['height'] as num?)?.toDouble() ?? 0.0) * 0.5 * sy;
        final skewX = (raw['skewX'] as num?)?.toDouble() ?? 0.0;
        final skewY = (raw['skewY'] as num?)?.toDouble() ?? 0.0;

        // OpenBone region quad order in bone-local Y-up space: TL, TR, BR, BL.
        final local = <double>[-hw, hh, hw, hh, hw, -hh, -hw, -hh];
        if (skewX != 0 || skewY != 0) {
          final tx = skewX != 0 ? math.tan(skewX * math.pi / 180.0) : 0.0;
          final ty = skewY != 0 ? math.tan(skewY * math.pi / 180.0) : 0.0;
          for (int i = 0; i < 8; i += 2) {
            final px = local[i];
            final py = local[i + 1];
            local[i] = px + tx * py;
            local[i + 1] = py + ty * px;
          }
        }

        final cosR = math.cos(rotRad);
        final sinR = math.sin(rotRad);
        var corners = Float32List(8);
        for (int i = 0; i < 8; i += 2) {
          final lx = local[i];
          final ly = local[i + 1];
          corners[i] = rx + lx * cosR - ly * sinR;
          corners[i + 1] = ry + lx * sinR + ly * cosR;
        }

        List<double> baseUvs = const [0, 0, 1, 0, 1, 1, 0, 1];
        if (region != null && region.isTrimmed && region.originalWidth > 0 && region.originalHeight > 0) {
          final u0 = region.offsetX / region.originalWidth;
          final v0 = region.offsetY / region.originalHeight;
          final u1 = (region.offsetX + region.width) / region.originalWidth;
          final v1 = (region.offsetY + region.height) / region.originalHeight;
          baseUvs = [u0, v0, u1, v0, u1, v1, u0, v1];
          final ux = corners[2] - corners[0];
          final uy = corners[3] - corners[1];
          final vx = corners[6] - corners[0];
          final vy = corners[7] - corners[1];
          final ox = corners[0];
          final oy = corners[1];
          corners = Float32List.fromList([
            ox + ux * u0 + vx * v0,
            oy + uy * u0 + vy * v0,
            ox + ux * u1 + vx * v0,
            oy + uy * u1 + vy * v0,
            ox + ux * u1 + vx * v1,
            oy + uy * u1 + vy * v1,
            ox + ux * u0 + vx * v1,
            oy + uy * u0 + vy * v1,
          ]);
        }

        final atlasTexCoords = region != null
            ? region.mapUvsToAtlasPixels(baseUvs)
            : Float32List.fromList(baseUvs);

        return OpenBoneRegionAttachment(
          name: (raw['name'] as String?) ?? name,
          imageId: imageId,
          pageId: region?.pageId,
          localCorners: corners,
          atlasTexCoords: atlasTexCoords,
          color: parseHexColor((raw['color'] as String?) ?? '#ffffff'),
        );

      case 'boundingBox':
        final rawVerts = (raw['vertices'] as List<dynamic>?) ?? const [];
        final verts = Float32List(rawVerts.length);
        for (int i = 0; i < rawVerts.length; i++) {
          verts[i] = (rawVerts[i] as num).toDouble();
        }
        return OpenBoneBoundingBoxAttachment(
          name: (raw['name'] as String?) ?? name,
          vertices: verts,
          color: parseHexColor((raw['color'] as String?) ?? '#ffb400'),
        );

      default:
        return null;
    }
  }

  static OpenBoneAnimation _parseAnimation(
    Map<String, dynamic> raw,
    Map<String, int> boneIndexById,
    Map<String, int> slotIndexById,
  ) {
    final boneTimelines = <OpenBoneBoneTimeline>[];
    final slotAttachmentTimelines = <OpenBoneSlotAttachmentTimeline>[];
    final slotColorTimelines = <OpenBoneSlotColorTimeline>[];
    double maxKeyTime = 0.0;

    final rawTls = (raw['timelines'] as List<dynamic>?) ?? const [];
    for (final item in rawTls) {
      if (item is! Map<String, dynamic>) continue;
      final keys = (item['keys'] as List<dynamic>?) ?? const [];
      if (keys.isEmpty) continue;
      final target = (item['target'] ?? '').toString();
      final id = (item['id'] ?? '').toString();
      final prop = (item['property'] ?? '').toString();

      if (target == 'bone') {
        final boneIdx = boneIndexById[id];
        final boneProp = _parseBoneProperty(prop);
        if (boneIdx == null || boneProp == null) continue;
        final times = Float64List(keys.length);
        final vals = Float64List(keys.length);
        final curves = <OpenBoneCurve>[];
        for (int i = 0; i < keys.length; i++) {
          final k = keys[i] as Map<String, dynamic>;
          final t = (k['time'] as num).toDouble();
          if (t > maxKeyTime) maxKeyTime = t;
          times[i] = t;
          vals[i] = (k['value'] as num).toDouble();
          curves.add(OpenBoneCurve.parse(k['curve']));
        }
        boneTimelines.add(
          OpenBoneBoneTimeline(
            boneIndex: boneIdx,
            boneId: id,
            property: boneProp,
            times: times,
            values: vals,
            curves: curves,
          ),
        );
      } else if (target == 'slot') {
        final slotIdx = slotIndexById[id];
        if (slotIdx == null) continue;
        if (prop == 'attachment') {
          final times = Float64List(keys.length);
          final names = <String?>[];
          for (int i = 0; i < keys.length; i++) {
            final k = keys[i] as Map<String, dynamic>;
            final t = (k['time'] as num).toDouble();
            if (t > maxKeyTime) maxKeyTime = t;
            times[i] = t;
            names.add(k['value'] as String?);
          }
          slotAttachmentTimelines.add(
            OpenBoneSlotAttachmentTimeline(
              slotIndex: slotIdx,
              slotId: id,
              times: times,
              attachmentNames: names,
            ),
          );
        } else if (prop == 'color') {
          final times = Float64List(keys.length);
          final colors = <Float32List>[];
          final curves = <OpenBoneCurve>[];
          for (int i = 0; i < keys.length; i++) {
            final k = keys[i] as Map<String, dynamic>;
            final t = (k['time'] as num).toDouble();
            if (t > maxKeyTime) maxKeyTime = t;
            times[i] = t;
            colors.add(parseHexColor((k['value'] as String?) ?? '#ffffff'));
            curves.add(OpenBoneCurve.parse(k['curve']));
          }
          slotColorTimelines.add(
            OpenBoneSlotColorTimeline(
              slotIndex: slotIdx,
              slotId: id,
              times: times,
              colors: colors,
              curves: curves,
            ),
          );
        }
      }
    }

    final declaredDuration = (raw['duration'] as num?)?.toDouble() ?? 0.0;
    final duration = declaredDuration > 0 ? declaredDuration : maxKeyTime;

    return OpenBoneAnimation(
      id: (raw['id'] ?? '').toString(),
      name: (raw['name'] ?? '').toString(),
      duration: duration,
      boneTimelines: boneTimelines,
      slotAttachmentTimelines: slotAttachmentTimelines,
      slotColorTimelines: slotColorTimelines,
    );
  }

  static OpenBoneStateMachine _parseStateMachine(Map<String, dynamic> raw) {
    final inputs = <OpenBoneSmInput>[];
    for (final inp in (raw['inputs'] as List<dynamic>?) ?? const []) {
      if (inp is! Map<String, dynamic>) continue;
      inputs.add(
        OpenBoneSmInput(
          id: (inp['id'] ?? '').toString(),
          name: (inp['name'] ?? '').toString(),
          type: (inp['type'] ?? 'trigger').toString(),
          defaultValue: inp['default'],
        ),
      );
    }

    final layers = <OpenBoneSmLayer>[];
    for (final lay in (raw['layers'] as List<dynamic>?) ?? const []) {
      if (lay is! Map<String, dynamic>) continue;
      final states = <OpenBoneSmState>[];
      for (final st in (lay['states'] as List<dynamic>?) ?? const []) {
        if (st is! Map<String, dynamic>) continue;
        states.add(
          OpenBoneSmState(
            id: (st['id'] ?? '').toString(),
            name: (st['name'] ?? '').toString(),
            type: (st['type'] ?? 'animation').toString(),
            animationId: st['animation'] as String?,
            loop: (st['loop'] as bool?) ?? false,
            speed: (st['speed'] as num?)?.toDouble() ?? 1.0,
            onComplete: st['onComplete'] as String?,
          ),
        );
      }
      final transitions = <OpenBoneSmTransition>[];
      for (final tr in (lay['transitions'] as List<dynamic>?) ?? const []) {
        if (tr is! Map<String, dynamic>) continue;
        final conds = <OpenBoneSmCondition>[];
        for (final c in (tr['conditions'] as List<dynamic>?) ?? const []) {
          if (c is! Map<String, dynamic>) continue;
          conds.add(
            OpenBoneSmCondition(
              inputId: (c['input'] ?? '').toString(),
              op: (c['op'] ?? '==').toString(),
              value: c['value'],
            ),
          );
        }
        transitions.add(
          OpenBoneSmTransition(
            id: (tr['id'] ?? '').toString(),
            from: (tr['from'] ?? '').toString(),
            to: (tr['to'] ?? '').toString(),
            conditions: conds,
            duration: (tr['duration'] as num?)?.toDouble() ?? 0.1,
            exitTime: (tr['exitTime'] as num?)?.toDouble(),
          ),
        );
      }
      layers.add(
        OpenBoneSmLayer(
          id: (lay['id'] ?? '').toString(),
          name: (lay['name'] ?? 'Motion').toString(),
          entryStateId: (lay['entry'] ?? '').toString(),
          states: states,
          transitions: transitions,
        ),
      );
    }

    final listeners = <OpenBoneSmListener>[];
    for (final lis in (raw['listeners'] as List<dynamic>?) ?? const []) {
      if (lis is! Map<String, dynamic>) continue;
      final actions = <OpenBoneSmAction>[];
      for (final a in (lis['actions'] as List<dynamic>?) ?? const []) {
        if (a is! Map<String, dynamic>) continue;
        actions.add(
          OpenBoneSmAction(
            type: (a['type'] ?? '').toString(),
            inputId: a['input'] as String?,
            value: a['value'],
          ),
        );
      }
      listeners.add(
        OpenBoneSmListener(
          id: (lis['id'] ?? '').toString(),
          name: (lis['name'] ?? '').toString(),
          slotId: lis['slot'] as String?,
          event: (lis['event'] ?? 'click').toString(),
          actions: actions,
        ),
      );
    }

    return OpenBoneStateMachine(
      id: (raw['id'] ?? '').toString(),
      name: (raw['name'] ?? '').toString(),
      inputs: inputs,
      layers: layers,
      listeners: listeners,
    );
  }

  static OpenBoneBoneProperty? _parseBoneProperty(String prop) {
    return switch (prop) {
      'x' => OpenBoneBoneProperty.x,
      'y' => OpenBoneBoneProperty.y,
      'rotation' => OpenBoneBoneProperty.rotation,
      'scaleX' => OpenBoneBoneProperty.scaleX,
      'scaleY' => OpenBoneBoneProperty.scaleY,
      'shearX' => OpenBoneBoneProperty.shearX,
      'shearY' => OpenBoneBoneProperty.shearY,
      _ => null,
    };
  }

  static Float32List parseHexColor(String hex) {
    var clean = hex.startsWith('#') ? hex.substring(1) : hex;
    if (clean.length == 3 || clean.length == 4) {
      final sb = StringBuffer();
      for (int i = 0; i < clean.length; i++) {
        sb
          ..write(clean[i])
          ..write(clean[i]);
      }
      clean = sb.toString();
    }
    if (clean.length < 6) {
      return Float32List.fromList(const [1, 1, 1, 1]);
    }
    final r = int.tryParse(clean.substring(0, 2), radix: 16) ?? 255;
    final g = int.tryParse(clean.substring(2, 4), radix: 16) ?? 255;
    final b = int.tryParse(clean.substring(4, 6), radix: 16) ?? 255;
    final a = clean.length >= 8
        ? (int.tryParse(clean.substring(6, 8), radix: 16) ?? 255)
        : 255;
    return Float32List.fromList([r / 255.0, g / 255.0, b / 255.0, a / 255.0]);
  }

  static bool _isObonb(Uint8List bytes) {
    return bytes.length >= 5 &&
        bytes[0] == 79 && // O
        bytes[1] == 66 && // B
        bytes[2] == 78 && // N
        bytes[3] == 66; // B
  }

  /// Pure-Dart OpenBone 0.4.8 binary (`OBNB`) deserializer matching `Ni(o)`.
  static dynamic _decodeObonb(Uint8List bytes) {
    final version = bytes[4];
    if (version > 1) {
      throw FormatException('OpenBone binary version $version is newer than supported 1');
    }

    final view = ByteData.sublistView(bytes);
    int offset = 5;

    Never corrupt() => throw const FormatException('Corrupt OpenBone binary document');

    int readVarint() {
      int value = 0;
      int mult = 1;
      while (true) {
        if (offset >= bytes.length) corrupt();
        final b = bytes[offset++];
        value += (b & 127) * mult;
        if (b < 128) return value;
        mult *= 128;
        if (mult > 0x100000000000000) corrupt();
      }
    }

    final strCount = readVarint();
    final strings = List<String>.filled(strCount, '', growable: false);
    for (int i = 0; i < strCount; i++) {
      final len = readVarint();
      if (offset + len > bytes.length) corrupt();
      strings[i] = utf8.decode(Uint8List.sublistView(bytes, offset, offset + len));
      offset += len;
    }

    String readStr() {
      final idx = readVarint();
      if (idx < 0 || idx >= strings.length) corrupt();
      return strings[idx];
    }

    dynamic readValue() {
      if (offset >= bytes.length) corrupt();
      final tag = bytes[offset++];
      switch (tag) {
        case 0:
          return null;
        case 1:
          return false;
        case 2:
          return true;
        case 3:
          return readVarint();
        case 4:
          return -readVarint() - 1;
        case 5:
          if (offset + 4 > bytes.length) corrupt();
          final v = view.getFloat32(offset, Endian.little);
          offset += 4;
          return v;
        case 6:
          if (offset + 8 > bytes.length) corrupt();
          final v = view.getFloat64(offset, Endian.little);
          offset += 8;
          return v;
        case 7:
          return readStr();
        case 8:
          final len = readVarint();
          return List<dynamic>.generate(len, (_) => readValue(), growable: false);
        case 9:
          final len = readVarint();
          final map = <String, dynamic>{};
          for (int i = 0; i < len; i++) {
            final k = readStr();
            map[k] = readValue();
          }
          return map;
        case 10:
          final mime = readStr();
          final len = readVarint();
          if (offset + len > bytes.length) corrupt();
          final slice = Uint8List.sublistView(bytes, offset, offset + len);
          offset += len;
          return OpenBoneBinaryBlob(mime, slice);
        default:
          corrupt();
      }
    }

    return readValue();
  }
}
