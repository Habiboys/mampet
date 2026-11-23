import 'dart:math' as math;
import 'dart:typed_data';

import 'openbone_document.dart';

const double _degToRad = math.pi / 180.0;
const String _anyStateId = '@any';

double _normalizeAngleDeg(double deg) {
  var a = deg % 360.0;
  if (a > 180.0) {
    a -= 360.0;
  } else if (a <= -180.0) {
    a += 360.0;
  }
  return a;
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

double _lerpAngleDeg(double a, double b, double t) =>
    a + _normalizeAngleDeg(b - a) * t;

/// 2D affine matrix matching OpenBone (`a, b, c, d, x, y` in Y-up skeleton space).
class OpenBoneMatrix {
  double a;
  double b;
  double c;
  double d;
  double x;
  double y;

  OpenBoneMatrix([
    this.a = 1.0,
    this.b = 0.0,
    this.c = 0.0,
    this.d = 1.0,
    this.x = 0.0,
    this.y = 0.0,
  ]);

  void setIdentity() {
    a = 1.0;
    b = 0.0;
    c = 0.0;
    d = 1.0;
    x = 0.0;
    y = 0.0;
  }

  void setFromLocal({
    required double lx,
    required double ly,
    required double rotationDeg,
    required double scaleX,
    required double scaleY,
    required double shearX,
    required double shearY,
  }) {
    final rx = (rotationDeg + shearX) * _degToRad;
    final ry = (rotationDeg + 90.0 + shearY) * _degToRad;
    a = math.cos(rx) * scaleX;
    b = math.cos(ry) * scaleY;
    c = math.sin(rx) * scaleX;
    d = math.sin(ry) * scaleY;
    x = lx;
    y = ly;
  }

  void setComposed(OpenBoneMatrix parent, OpenBoneMatrix local, String inherit) {
    final wx = parent.a * local.x + parent.b * local.y + parent.x;
    final wy = parent.c * local.x + parent.d * local.y + parent.y;

    switch (inherit) {
      case 'onlyTranslation':
        a = local.a;
        b = local.b;
        c = local.c;
        d = local.d;
        x = wx;
        y = wy;
        return;
      case 'noRotation':
        final sx = math.sqrt(parent.a * parent.a + parent.c * parent.c);
        final sy = math.sqrt(parent.b * parent.b + parent.d * parent.d);
        a = local.a * sx;
        b = local.b * sy;
        c = local.c * sx;
        d = local.d * sy;
        x = wx;
        y = wy;
        return;
      case 'noScale':
        final sx = math.sqrt(parent.a * parent.a + parent.c * parent.c);
        final sy = math.sqrt(parent.b * parent.b + parent.d * parent.d);
        final invX = sx > 1e-9 ? 1.0 / sx : 1.0;
        final invY = sy > 1e-9 ? 1.0 / sy : 1.0;
        final pa = parent.a * invX;
        final pc = parent.c * invX;
        final pb = parent.b * invY;
        final pd = parent.d * invY;
        a = pa * local.a + pb * local.c;
        b = pa * local.b + pb * local.d;
        c = pc * local.a + pd * local.c;
        d = pc * local.b + pd * local.d;
        x = wx;
        y = wy;
        return;
      default:
        a = parent.a * local.a + parent.b * local.c;
        b = parent.a * local.b + parent.b * local.d;
        c = parent.c * local.a + parent.d * local.c;
        d = parent.c * local.b + parent.d * local.d;
        x = wx;
        y = wy;
    }
  }
}

/// Mutable runtime bone pose evaluated per frame.
class OpenBoneBoneState {
  final OpenBoneBoneData data;
  double x = 0;
  double y = 0;
  double rotation = 0;
  double scaleX = 1;
  double scaleY = 1;
  double shearX = 0;
  double shearY = 0;

  final OpenBoneMatrix _local = OpenBoneMatrix();
  final OpenBoneMatrix world = OpenBoneMatrix();

  OpenBoneBoneState(this.data) {
    setToSetupPose();
  }

  void setToSetupPose() {
    x = data.x;
    y = data.y;
    rotation = data.rotation;
    scaleX = data.scaleX;
    scaleY = data.scaleY;
    shearX = data.shearX;
    shearY = data.shearY;
  }

  void updateWorld(OpenBoneBoneState? parent) {
    _local.setFromLocal(
      lx: x,
      ly: y,
      rotationDeg: rotation,
      scaleX: scaleX,
      scaleY: scaleY,
      shearX: shearX,
      shearY: shearY,
    );
    if (parent == null) {
      world.a = _local.a;
      world.b = _local.b;
      world.c = _local.c;
      world.d = _local.d;
      world.x = _local.x;
      world.y = _local.y;
    } else {
      world.setComposed(parent.world, _local, data.inherit);
    }
  }
}

/// Mutable runtime slot state evaluated per frame.
class OpenBoneSlotState {
  final OpenBoneSlotData data;
  String? attachmentName;
  final Float32List color = Float32List(4);

  OpenBoneSlotState(this.data) {
    setToSetupPose();
  }

  void setToSetupPose() {
    attachmentName = data.attachment;
    color[0] = data.color[0];
    color[1] = data.color[1];
    color[2] = data.color[2];
    color[3] = data.color[3];
  }
}

/// Drawable item produced by [OpenBoneSkeleton.buildDrawList] for the renderer.
class OpenBoneDrawItem {
  final int slotIndex;
  final String slotName;
  final String pageId;
  final Float32List worldVertices;
  final Float32List atlasTexCoords;
  final Uint16List triangles;
  final double alpha;

  const OpenBoneDrawItem({
    required this.slotIndex,
    required this.slotName,
    required this.pageId,
    required this.worldVertices,
    required this.atlasTexCoords,
    required this.triangles,
    required this.alpha,
  });
}

/// Evaluatable OpenBone skeleton with zero-allocation vertex buffers.
class OpenBoneSkeleton {
  final OpenBoneDocument doc;
  final List<OpenBoneBoneState> bones;
  final List<OpenBoneSlotState> slots;

  // Reusable per-slot vertex buffers to avoid frame-by-frame Float32List churn.
  final List<Float32List?> _slotVertexBuffers;

  OpenBoneSkeleton(this.doc)
      : bones = doc.bones.map(OpenBoneBoneState.new).toList(growable: false),
        slots = doc.slots.map(OpenBoneSlotState.new).toList(growable: false),
        _slotVertexBuffers = List<Float32List?>.filled(doc.slots.length, null) {
    setToSetupPose();
    updateWorldTransform();
  }

  void setToSetupPose() {
    for (final b in bones) {
      b.setToSetupPose();
    }
    for (final s in slots) {
      s.setToSetupPose();
    }
  }

  void updateWorldTransform() {
    for (final b in bones) {
      final parentIdx = b.data.parentIndex;
      b.updateWorld(parentIdx >= 0 ? bones[parentIdx] : null);
    }
  }

  OpenBoneAttachment? activeAttachment(int slotIndex) {
    final name = slots[slotIndex].attachmentName;
    if (name == null) return null;
    return doc.slotAttachments[slotIndex][name];
  }

  /// Applies [animation] at [time] with blend weight [alpha].
  ///
  /// When [fadeInto] is provided, matches OpenBone's exact cross-fade blending:
  /// timelines also targeted by [fadeInto] keep full weight [alpha] (so the
  /// incoming clip smoothly blends over them), while timelines NOT targeted by
  /// [fadeInto] fade cleanly back toward setup pose using [fadeAlpha].
  void applyAnimation(
    OpenBoneAnimation animation,
    double time, {
    double alpha = 1.0,
    OpenBoneAnimation? fadeInto,
    double fadeAlpha = 0.0,
  }) {
    if (alpha <= 0.0) return;

    for (final tl in animation.boneTimelines) {
      final propKey = tl.boneIndex * 8 + tl.property.index;
      final w = (fadeInto != null && !fadeInto.animatedBonePropKeys.contains(propKey))
          ? fadeAlpha
          : alpha;
      if (w <= 0.0) continue;

      final bone = bones[tl.boneIndex];
      final v = tl.evaluate(time);
      if (w >= 1.0) {
        switch (tl.property) {
          case OpenBoneBoneProperty.x:
            bone.x = v;
          case OpenBoneBoneProperty.y:
            bone.y = v;
          case OpenBoneBoneProperty.rotation:
            bone.rotation = v;
          case OpenBoneBoneProperty.scaleX:
            bone.scaleX = v;
          case OpenBoneBoneProperty.scaleY:
            bone.scaleY = v;
          case OpenBoneBoneProperty.shearX:
            bone.shearX = v;
          case OpenBoneBoneProperty.shearY:
            bone.shearY = v;
        }
      } else {
        switch (tl.property) {
          case OpenBoneBoneProperty.x:
            bone.x = _lerp(bone.x, v, w);
          case OpenBoneBoneProperty.y:
            bone.y = _lerp(bone.y, v, w);
          case OpenBoneBoneProperty.rotation:
            bone.rotation = _lerpAngleDeg(bone.rotation, v, w);
          case OpenBoneBoneProperty.scaleX:
            bone.scaleX = _lerp(bone.scaleX, v, w);
          case OpenBoneBoneProperty.scaleY:
            bone.scaleY = _lerp(bone.scaleY, v, w);
          case OpenBoneBoneProperty.shearX:
            bone.shearX = _lerp(bone.shearX, v, w);
          case OpenBoneBoneProperty.shearY:
            bone.shearY = _lerp(bone.shearY, v, w);
        }
      }
    }

    if (alpha >= 0.5) {
      for (final tl in animation.slotAttachmentTimelines) {
        slots[tl.slotIndex].attachmentName = tl.evaluate(time);
      }
    }

    for (final tl in animation.slotColorTimelines) {
      final w = (fadeInto != null && !fadeInto.animatedSlotColorIndices.contains(tl.slotIndex))
          ? fadeAlpha
          : alpha;
      if (w <= 0.0) continue;
      final slot = slots[tl.slotIndex];
      final c = tl.evaluate(time);
      if (w >= 1.0) {
        slot.color[0] = c[0];
        slot.color[1] = c[1];
        slot.color[2] = c[2];
        slot.color[3] = c[3];
      } else {
        slot.color[0] = _lerp(slot.color[0], c[0], w);
        slot.color[1] = _lerp(slot.color[1], c[1], w);
        slot.color[2] = _lerp(slot.color[2], c[2], w);
        slot.color[3] = _lerp(slot.color[3], c[3], w);
      }
    }
  }

  Float32List _ensureBuffer(int slotIndex, int length) {
    final existing = _slotVertexBuffers[slotIndex];
    if (existing != null && existing.length == length) return existing;
    final fresh = Float32List(length);
    _slotVertexBuffers[slotIndex] = fresh;
    return fresh;
  }

  /// Evaluates world-space vertices for all visible mesh/region slots in draw order.
  List<OpenBoneDrawItem> buildDrawList() {
    final items = <OpenBoneDrawItem>[];
    for (int i = 0; i < slots.length; i++) {
      final slot = slots[i];
      final att = activeAttachment(i);
      if (att == null) continue;

      if (att is OpenBoneMeshAttachment) {
        final pageId = att.pageId;
        if (pageId == null) continue;
        final alpha = slot.color[3] * att.color[3];
        if (alpha <= 0.001) continue;

        final vCount = att.vertexCount;
        final out = _ensureBuffer(i, vCount * 2);
        final fallbackM = bones[slot.data.boneIndex].world;

        if (att.hasWeights) {
          final offsets = att.weightOffsets;
          final counts = att.weightCounts;
          final boneIds = att.weightBoneIndices;
          final lx = att.weightLocalX;
          final ly = att.weightLocalY;
          final wv = att.weightValues;
          for (int v = 0; v < vCount; v++) {
            double wx = 0.0;
            double wy = 0.0;
            final start = offsets[v];
            final end = start + counts[v];
            for (int k = start; k < end; k++) {
              final bIdx = boneIds[k];
              final m = bIdx >= 0 ? bones[bIdx].world : fallbackM;
              final x = lx[k];
              final y = ly[k];
              final weight = wv[k];
              wx += (m.a * x + m.b * y + m.x) * weight;
              wy += (m.c * x + m.d * y + m.y) * weight;
            }
            out[v * 2] = wx;
            out[v * 2 + 1] = wy;
          }
        } else {
          final src = att.setupVertices;
          for (int v = 0; v < vCount; v++) {
            final sx = src[v * 2];
            final sy = src[v * 2 + 1];
            out[v * 2] = fallbackM.a * sx + fallbackM.b * sy + fallbackM.x;
            out[v * 2 + 1] = fallbackM.c * sx + fallbackM.d * sy + fallbackM.y;
          }
        }

        items.add(
          OpenBoneDrawItem(
            slotIndex: i,
            slotName: slot.data.name,
            pageId: pageId,
            worldVertices: out,
            atlasTexCoords: att.atlasTexCoords,
            triangles: att.triangles,
            alpha: alpha,
          ),
        );
      } else if (att is OpenBoneRegionAttachment) {
        final pageId = att.pageId;
        if (pageId == null) continue;
        final alpha = slot.color[3] * att.color[3];
        if (alpha <= 0.001) continue;

        final out = _ensureBuffer(i, 8);
        final m = bones[slot.data.boneIndex].world;
        final c = att.localCorners;
        for (int p = 0; p < 8; p += 2) {
          final lx = c[p];
          final ly = c[p + 1];
          out[p] = m.a * lx + m.b * ly + m.x;
          out[p + 1] = m.c * lx + m.d * ly + m.y;
        }

        items.add(
          OpenBoneDrawItem(
            slotIndex: i,
            slotName: slot.data.name,
            pageId: pageId,
            worldVertices: out,
            atlasTexCoords: att.atlasTexCoords,
            triangles: OpenBoneRegionAttachment.quadTriangles,
            alpha: alpha,
          ),
        );
      }
    }
    return items;
  }

  /// Evaluates world-space polygon vertices for any boundingBox slot (e.g. `face_touch`).
  Float32List? boundingBoxWorldVertices(int slotIndex) {
    final slotMap = doc.slotAttachments[slotIndex];
    OpenBoneBoundingBoxAttachment? box;
    final active = activeAttachment(slotIndex);
    if (active is OpenBoneBoundingBoxAttachment) {
      box = active;
    } else {
      for (final att in slotMap.values) {
        if (att is OpenBoneBoundingBoxAttachment) {
          box = att;
          break;
        }
      }
    }
    if (box == null || box.vertices.length < 6) return null;
    final m = bones[slots[slotIndex].data.boneIndex].world;
    final src = box.vertices;
    final out = Float32List(src.length);
    for (int i = 0; i < src.length; i += 2) {
      final lx = src[i];
      final ly = src[i + 1];
      out[i] = m.a * lx + m.b * ly + m.x;
      out[i + 1] = m.c * lx + m.d * ly + m.y;
    }
    return out;
  }

  /// Ray-casting point-in-polygon check matching OpenBone `nt(x, y, poly)`.
  static bool pointInPolygon(double px, double py, Float32List poly) {
    bool inside = false;
    final count = poly.length ~/ 2;
    for (int i = 0, j = count - 1; i < count; j = i++) {
      final xi = poly[i * 2];
      final yi = poly[i * 2 + 1];
      final xj = poly[j * 2];
      final yj = poly[j * 2 + 1];
      final intersects = ((yi > py) != (yj > py)) &&
          (px < (xj - xi) * (py - yi) / (yj - yi) + xi);
      if (intersects) inside = !inside;
    }
    return inside;
  }

  bool hitTestSlot(String slotIdOrName, double skelX, double skelY) {
    for (int i = 0; i < slots.length; i++) {
      final data = slots[i].data;
      if (data.id != slotIdOrName && data.name != slotIdOrName) continue;
      final poly = boundingBoxWorldVertices(i);
      if (poly != null && pointInPolygon(skelX, skelY, poly)) {
        return true;
      }
    }
    return false;
  }
}

class _ActiveSmState {
  final OpenBoneSmState data;
  double time = 0.0;

  _ActiveSmState(this.data);
}

class _ActiveSmLayer {
  final OpenBoneSmLayer data;
  _ActiveSmState? current;
  _ActiveSmState? from;
  double mixTime = 0.0;
  double mixDuration = 0.0;

  _ActiveSmLayer(this.data);
}

/// Full OpenBone 0.4.8 state machine runner with smooth cross-fades and click hit-testing.
class OpenBonePlayer {
  final OpenBoneDocument doc;
  final OpenBoneSkeleton skeleton;
  final OpenBoneStateMachine? stateMachine;
  final void Function(String stateName)? onStateChanged;

  final List<_ActiveSmLayer> _layers = [];
  final Set<String> _firedTriggerIds = <String>{};
  bool _started = false;
  String _activeStateName = 'idle';

  OpenBonePlayer(
    this.doc, {
    String? stateMachineName,
    this.onStateChanged,
  })  : skeleton = OpenBoneSkeleton(doc),
        stateMachine = _resolveStateMachine(doc, stateMachineName) {
    final sm = stateMachine;
    if (sm != null) {
      for (final lay in sm.layers) {
        _layers.add(_ActiveSmLayer(lay));
      }
    }
    start();
  }

  static OpenBoneStateMachine? _resolveStateMachine(
    OpenBoneDocument doc,
    String? preferredName,
  ) {
    if (doc.stateMachines.isEmpty) return null;
    if (preferredName != null) {
      for (final sm in doc.stateMachines) {
        if (sm.name == preferredName || sm.id == preferredName) return sm;
      }
    }
    return doc.stateMachines.first;
  }

  String get activeStateName => _activeStateName;

  /// Normalized `[0..1]` cycle progress of the primary layer's active clip.
  double get normalizedProgress {
    if (_layers.isEmpty) return 0.0;
    final cur = _layers.first.current;
    if (cur == null) return 0.0;
    final anim = _animForState(cur.data);
    if (anim == null || anim.duration <= 0) return 0.0;
    return (anim.sampleTime(cur.time, cur.data.loop) / anim.duration).clamp(0.0, 1.0);
  }

  void start() {
    if (_started) return;
    _started = true;
    for (final layer in _layers) {
      final entry = layer.data.stateById(layer.data.entryStateId) ??
          layer.data.stateByName('idle') ??
          (layer.data.states.isNotEmpty ? layer.data.states.first : null);
      if (entry != null) {
        _enter(layer, entry, 0.0, notify: false);
      }
    }
    _applyAndSolve();
  }

  /// Fires a named OpenBone trigger input (e.g. `'pet'`, `'happy'`, `'eat'`,
  /// `'sleep'`, `'play'`, `'special'`, `'wake'`).
  ///
  /// When [forceRestart] is true and the character is already in the target
  /// state, cleanly restarts that state with a gentle `0.07s` cross-fade.
  bool fireTrigger(String triggerName, {bool forceRestart = false}) {
    final sm = stateMachine;
    if (sm == null) return false;
    final input = sm.findInput(triggerName);
    if (input == null) return false;

    if (forceRestart && _layers.isNotEmpty) {
      final layer = _layers.first;
      final targetStateName = triggerName == 'wake' ? 'idle' : triggerName;
      if (layer.current?.data.name == targetStateName) {
        final target = layer.data.stateByName(targetStateName);
        if (target != null) {
          _enter(layer, target, 0.07);
          _applyAndSolve();
          return true;
        }
      }
    }

    _firedTriggerIds.add(input.id);
    for (final layer in _layers) {
      _settle(layer);
    }
    _firedTriggerIds.clear();
    _applyAndSolve();
    return true;
  }

  /// Handles a tap in artboard pixel space `(0..doc.width, 0..doc.height)`.
  /// Returns the triggered input name (typically `'pet'` when clicking `face_touch`),
  /// or `null` if no OpenBone listener matched.
  String? handleArtboardTap(double artboardX, double artboardY) {
    final sm = stateMachine;
    if (sm == null) return null;
    final skelX = artboardX - doc.originX;
    final skelY = doc.originY - artboardY;

    for (final listener in sm.listeners) {
      if (listener.event != 'click') continue;
      final hit = listener.slotId == null ||
          skeleton.hitTestSlot(listener.slotId!, skelX, skelY);
      if (!hit) continue;
      for (final action in listener.actions) {
        if (action.type == 'fireTrigger' && action.inputId != null) {
          final inp = sm.findInput(action.inputId!);
          if (inp != null) {
            fireTrigger(inp.name, forceRestart: true);
            return inp.name;
          }
        }
      }
    }
    return null;
  }

  /// Advances state machine clocks, resolves auto-return transitions (e.g. back to `idle`),
  /// blends cross-fade poses, and updates bone world matrices.
  void advance(double dtSeconds) {
    if (!_started) start();
    final dt = dtSeconds.clamp(0.0, 0.06);

    for (final layer in _layers) {
      _settle(layer);
    }
    _firedTriggerIds.clear();

    for (final layer in _layers) {
      final cur = layer.current;
      if (cur != null) {
        cur.time += dt * cur.data.speed;
      }
      final prev = layer.from;
      if (prev != null) {
        prev.time += dt * prev.data.speed;
        layer.mixTime += dt;
        if (layer.mixTime >= layer.mixDuration) {
          layer.from = null;
        }
      }
      // Check exitTime transitions immediately after advancing clip clock so
      // completed one-shots begin their 0.12s cross-fade back to `idle` promptly.
      _settle(layer);
    }

    _applyAndSolve();
  }

  /// Resets directly to calm `idle` resting pose at `t = 0` (used for `reduceMotion`).
  void resetToSetupPose() {
    skeleton.setToSetupPose();
    final idle = doc.animationByIdOrName['idle'];
    if (idle != null) {
      skeleton.applyAnimation(idle, 0.0, alpha: 1.0);
    }
    skeleton.updateWorldTransform();
  }

  void _applyAndSolve() {
    skeleton.setToSetupPose();
    for (final layer in _layers) {
      final mix = layer.mixDuration > 0
          ? (layer.mixTime / layer.mixDuration).clamp(0.0, 1.0)
          : 1.0;
      final prev = layer.from;
      final cur = layer.current;
      if (prev != null) {
        final prevAnim = _animForState(prev.data);
        final curAnim = cur != null ? _animForState(cur.data) : null;
        if (prevAnim != null) {
          skeleton.applyAnimation(
            prevAnim,
            prevAnim.sampleTime(prev.time, prev.data.loop),
            alpha: 1.0,
            fadeInto: curAnim,
            fadeAlpha: 1.0 - mix,
          );
        }
      }
      if (cur != null) {
        final curAnim = _animForState(cur.data);
        if (curAnim != null) {
          skeleton.applyAnimation(
            curAnim,
            curAnim.sampleTime(cur.time, cur.data.loop),
            alpha: prev != null ? mix : 1.0,
          );
        }
      }
    }
    skeleton.updateWorldTransform();
  }

  OpenBoneAnimation? _animForState(OpenBoneSmState state) {
    final id = state.animationId;
    if (id == null) return null;
    return doc.animationByIdOrName[id];
  }

  double _progress(_ActiveSmState st) {
    final anim = _animForState(st.data);
    if (anim == null || anim.duration <= 0) return 1.0;
    return st.time / anim.duration;
  }

  bool _canTake(OpenBoneSmTransition tr, _ActiveSmState? cur) {
    if (tr.from != _anyStateId &&
        tr.to == cur?.data.id &&
        tr.conditions.isEmpty) {
      return false;
    }
    if (tr.from == _anyStateId && tr.to == cur?.data.id) {
      return false;
    }
    final exitTime = tr.exitTime ?? (tr.conditions.isEmpty ? 1.0 : null);
    if (exitTime != null && cur != null && _progress(cur) < exitTime) {
      return false;
    }
    for (final cond in tr.conditions) {
      if (!_firedTriggerIds.contains(cond.inputId)) return false;
    }
    return true;
  }

  OpenBoneSmTransition? _evaluateLayer(_ActiveSmLayer layer) {
    final cur = layer.current;
    final candidates = <OpenBoneSmTransition>[];
    for (final tr in layer.data.transitions) {
      if (tr.from == _anyStateId || tr.from == cur?.data.id) {
        candidates.add(tr);
      }
    }
    // Specific-state transitions take priority over `@any` (matching OpenBone).
    candidates.sort(
      (a, b) => (a.from == _anyStateId ? 1 : 0) - (b.from == _anyStateId ? 1 : 0),
    );
    for (final tr in candidates) {
      if (!_canTake(tr, cur)) continue;
      final next = layer.data.stateById(tr.to);
      if (next != null) {
        _enter(layer, next, tr.duration);
        return tr;
      }
    }
    final onComplete = cur?.data.onComplete;
    if (cur != null && onComplete != null && _progress(cur) >= 1.0) {
      final next = layer.data.stateById(onComplete);
      if (next != null) {
        _enter(layer, next, 0.1);
      }
    }
    return null;
  }

  void _settle(_ActiveSmLayer layer) {
    for (int step = 0; step < 4; step++) {
      final taken = _evaluateLayer(layer);
      if (taken == null) return;
      for (final cond in taken.conditions) {
        _firedTriggerIds.remove(cond.inputId);
      }
    }
  }

  void _enter(
    _ActiveSmLayer layer,
    OpenBoneSmState nextState,
    double mixDuration, {
    bool notify = true,
  }) {
    final prev = layer.current;
    layer.from = mixDuration > 0 ? prev : null;
    layer.current = _ActiveSmState(nextState);
    layer.mixTime = 0.0;
    layer.mixDuration = mixDuration;

    if (layer == _layers.first) {
      final changed = _activeStateName != nextState.name;
      _activeStateName = nextState.name;
      if (notify && changed) {
        onStateChanged?.call(_activeStateName);
      }
    }
  }
}
