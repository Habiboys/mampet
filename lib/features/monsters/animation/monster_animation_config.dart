import 'dart:math' as math;

import 'monster_animation_state.dart';

/// Evaluated local transform for a single layer at a given moment in time.
class LayerTransform {
  final double dx;
  final double dy;
  final double rotDeg;
  final double scaleX;
  final double scaleY;
  final double opacity;

  const LayerTransform({
    this.dx = 0.0,
    this.dy = 0.0,
    this.rotDeg = 0.0,
    this.scaleX = 1.0,
    this.scaleY = 1.0,
    this.opacity = 1.0,
  });

  static const LayerTransform identity = LayerTransform();

  static LayerTransform lerp(LayerTransform a, LayerTransform b, double t) {
    final k = t.clamp(0.0, 1.0);
    return LayerTransform(
      dx: a.dx + (b.dx - a.dx) * k,
      dy: a.dy + (b.dy - a.dy) * k,
      rotDeg: a.rotDeg + (b.rotDeg - a.rotDeg) * k,
      scaleX: a.scaleX + (b.scaleX - a.scaleX) * k,
      scaleY: a.scaleY + (b.scaleY - a.scaleY) * k,
      opacity: a.opacity + (b.opacity - a.opacity) * k,
    );
  }
}

/// Smooth keyframe arrays for a single rig layer inside an animation state.
class KeyframeTrack {
  final List<double>? dx;
  final List<double>? dy;
  final List<double>? rotDeg;
  final List<double>? scaleX;
  final List<double>? scaleY;
  final List<double>? opacity;

  const KeyframeTrack({
    this.dx,
    this.dy,
    this.rotDeg,
    this.scaleX,
    this.scaleY,
    this.opacity,
  });

  factory KeyframeTrack.fromJson(Map<String, dynamic> json) {
    List<double>? parseList(String key) {
      final raw = json[key] as List<dynamic>?;
      if (raw == null || raw.isEmpty) return null;
      return raw.map((e) => (e as num).toDouble()).toList(growable: false);
    }

    return KeyframeTrack(
      dx: parseList('dx'),
      dy: parseList('dy'),
      rotDeg: parseList('rot_deg'),
      scaleX: parseList('scale_x'),
      scaleY: parseList('scale_y'),
      opacity: parseList('opacity'),
    );
  }

  /// Evaluates smooth cosine-eased interpolation between evenly-spaced keyframes
  /// at normalized cycle time `t ∈ [0.0 .. 1.0]`.
  static double _sample(List<double>? values, double t, double fallback) {
    if (values == null || values.isEmpty) return fallback;
    if (values.length == 1) return values.first;
    final clamped = t.clamp(0.0, 1.0);
    final scaled = clamped * (values.length - 1);
    final idx0 = scaled.floor().clamp(0, values.length - 1);
    final idx1 = math.min(idx0 + 1, values.length - 1);
    final frac = scaled - idx0;
    // Smooth cosine ease between keyframes so motion feels organic & bouncy, never robotic!
    final eased = 0.5 - 0.5 * math.cos(frac * math.pi);
    return values[idx0] + (values[idx1] - values[idx0]) * eased;
  }

  LayerTransform evaluate(double t) {
    return LayerTransform(
      dx: _sample(dx, t, 0.0),
      dy: _sample(dy, t, 0.0),
      rotDeg: _sample(rotDeg, t, 0.0),
      scaleX: _sample(scaleX, t, 1.0),
      scaleY: _sample(scaleY, t, 1.0),
      opacity: _sample(opacity, t, 1.0),
    );
  }
}

/// Complete keyframe & facial expression configuration for one [MonsterAnimation].
class AnimationStateConfig {
  final MonsterAnimation state;
  final bool loop;
  final int durationMs;
  final String? eyes;
  final String? mouth;
  final String? mouthAlternate;
  final Map<String, KeyframeTrack> tracks;

  const AnimationStateConfig({
    required this.state,
    required this.loop,
    required this.durationMs,
    this.eyes,
    this.mouth,
    this.mouthAlternate,
    required this.tracks,
  });

  factory AnimationStateConfig.fromJson(
    MonsterAnimation state,
    Map<String, dynamic> json,
  ) {
    final rawTracks = (json['tracks'] as Map<String, dynamic>?) ?? const {};
    final parsed = <String, KeyframeTrack>{};
    rawTracks.forEach((layerId, trackData) {
      if (trackData is Map<String, dynamic>) {
        parsed[layerId] = KeyframeTrack.fromJson(trackData);
      }
    });
    return AnimationStateConfig(
      state: state,
      loop: (json['loop'] as bool?) ?? state.isPersistentLoop,
      durationMs: ((json['duration_ms'] as num?)?.toInt() ?? 1400).clamp(200, 12000),
      eyes: json['eyes'] as String?,
      mouth: json['mouth'] as String?,
      mouthAlternate: json['mouth_alternate'] as String?,
      tracks: parsed,
    );
  }
}

/// Data-driven animation config parsed from `assets/monsters/<slug>/<stage>/animations.json`.
class MonsterAnimationConfig {
  final String monsterId;
  final String stage;
  final int blinkIntervalMinMs;
  final int blinkIntervalMaxMs;
  final int blinkDurationMs;
  final Map<MonsterAnimation, AnimationStateConfig> states;

  const MonsterAnimationConfig({
    required this.monsterId,
    required this.stage,
    required this.blinkIntervalMinMs,
    required this.blinkIntervalMaxMs,
    required this.blinkDurationMs,
    required this.states,
  });

  AnimationStateConfig stateConfig(MonsterAnimation state) {
    return states[state] ??
        states[MonsterAnimation.idle] ??
        _defaultFallbackStates[state]!;
  }

  factory MonsterAnimationConfig.fromJson(Map<String, dynamic> json) {
    final interval =
        (json['blink_interval_ms'] as List<dynamic>?) ?? const [2600, 4800];
    final minBlink = interval.isNotEmpty ? (interval[0] as num).toInt() : 2600;
    final maxBlink = interval.length > 1 ? (interval[1] as num).toInt() : 4800;
    final blinkDur = ((json['blink_duration_ms'] as num?)?.toInt() ?? 140).clamp(80, 300);

    final rawStates = (json['states'] as Map<String, dynamic>?) ?? const {};
    final parsed = <MonsterAnimation, AnimationStateConfig>{};
    for (final state in MonsterAnimation.values) {
      final raw = rawStates[state.code];
      if (raw is Map<String, dynamic>) {
        parsed[state] = AnimationStateConfig.fromJson(state, raw);
      } else {
        parsed[state] = _defaultFallbackStates[state]!;
      }
    }

    return MonsterAnimationConfig(
      monsterId: (json['monster_id'] as String?) ?? 'unknown',
      stage: (json['stage'] as String?) ?? 'baby',
      blinkIntervalMinMs: math.min(minBlink, maxBlink).clamp(1200, 9000),
      blinkIntervalMaxMs: math.max(minBlink, maxBlink).clamp(1500, 12000),
      blinkDurationMs: blinkDur,
      states: parsed,
    );
  }

  /// Safe fallback config for whole-body animated characters without JSON files.
  factory MonsterAnimationConfig.fallback({
    required String slug,
    required String stage,
  }) {
    return MonsterAnimationConfig(
      monsterId: slug,
      stage: stage,
      blinkIntervalMinMs: 2800,
      blinkIntervalMaxMs: 4800,
      blinkDurationMs: 140,
      states: _defaultFallbackStates,
    );
  }

  static const Map<MonsterAnimation, AnimationStateConfig> _defaultFallbackStates = {
    MonsterAnimation.idle: AnimationStateConfig(
      state: MonsterAnimation.idle,
      loop: true,
      durationMs: 2600,
      eyes: 'eyes_open',
      mouth: 'mouth_happy',
      tracks: {
        'body': KeyframeTrack(
          scaleY: [1.0, 1.032, 1.0],
          scaleX: [1.0, 0.985, 1.0],
          dy: [0.0, -5.0, 0.0],
          rotDeg: [-1.2, 1.2, -1.2],
        ),
      },
    ),
    MonsterAnimation.happy: AnimationStateConfig(
      state: MonsterAnimation.happy,
      loop: false,
      durationMs: 1200,
      eyes: 'eyes_closed',
      mouth: 'mouth_happy',
      tracks: {
        'body': KeyframeTrack(
          dy: [0.0, -34.0, 0.0, -22.0, 0.0],
          scaleY: [1.0, 1.08, 0.93, 1.06, 1.0],
          scaleX: [1.0, 0.94, 1.07, 0.96, 1.0],
          rotDeg: [0.0, -4.5, 4.5, -3.0, 0.0],
        ),
      },
    ),
    MonsterAnimation.pet: AnimationStateConfig(
      state: MonsterAnimation.pet,
      loop: false,
      durationMs: 1350,
      eyes: 'eyes_closed',
      mouth: 'mouth_happy',
      tracks: {
        'body': KeyframeTrack(
          scaleY: [1.0, 0.93, 1.04, 0.96, 1.0],
          scaleX: [1.0, 1.06, 0.97, 1.03, 1.0],
          rotDeg: [0.0, 5.5, -5.0, 3.5, 0.0],
        ),
      },
    ),
    MonsterAnimation.eat: AnimationStateConfig(
      state: MonsterAnimation.eat,
      loop: false,
      durationMs: 1500,
      eyes: 'eyes_open',
      mouth: 'mouth_eating',
      mouthAlternate: 'mouth_neutral',
      tracks: {
        'body': KeyframeTrack(
          scaleY: [1.0, 1.05, 0.96, 1.05, 0.97, 1.0],
          scaleX: [1.0, 0.97, 1.04, 0.97, 1.03, 1.0],
          dy: [0.0, -10.0, 2.0, -10.0, 0.0],
        ),
      },
    ),
    MonsterAnimation.sleep: AnimationStateConfig(
      state: MonsterAnimation.sleep,
      loop: true,
      durationMs: 3800,
      eyes: 'eyes_sleep',
      mouth: 'mouth_neutral',
      tracks: {
        'body': KeyframeTrack(
          scaleY: [0.96, 1.01, 0.96],
          scaleX: [1.03, 0.99, 1.03],
          dy: [10.0, 6.0, 10.0],
          rotDeg: [2.5, 4.0, 2.5],
        ),
      },
    ),
    MonsterAnimation.play: AnimationStateConfig(
      state: MonsterAnimation.play,
      loop: false,
      durationMs: 1500,
      eyes: 'eyes_open',
      mouth: 'mouth_happy',
      tracks: {
        'body': KeyframeTrack(
          dy: [0.0, -44.0, -52.0, -28.0, 0.0],
          rotDeg: [0.0, -7.0, 7.0, -4.0, 0.0],
          scaleY: [1.0, 1.08, 0.95, 1.05, 1.0],
        ),
      },
    ),
    MonsterAnimation.special: AnimationStateConfig(
      state: MonsterAnimation.special,
      loop: false,
      durationMs: 1800,
      eyes: 'eyes_open',
      mouth: 'mouth_happy',
      tracks: {
        'body': KeyframeTrack(
          dy: [0.0, -32.0, -10.0, -48.0, 0.0],
          rotDeg: [0.0, -8.0, 8.0, -6.0, 0.0],
          scaleX: [1.0, 1.08, 0.94, 1.1, 1.0],
          scaleY: [1.0, 1.08, 0.94, 1.1, 1.0],
        ),
      },
    ),
    MonsterAnimation.evolve: AnimationStateConfig(
      state: MonsterAnimation.evolve,
      loop: false,
      durationMs: 1800,
      eyes: 'eyes_closed',
      mouth: 'mouth_happy',
      tracks: {
        'body': KeyframeTrack(
          scaleX: [1.0, 1.12, 0.93, 1.16, 1.0],
          scaleY: [1.0, 1.12, 0.93, 1.16, 1.0],
          dy: [0.0, -24.0, -12.0, -34.0, 0.0],
        ),
      },
    ),
  };
}
