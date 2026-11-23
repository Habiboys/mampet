import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'monster_animation_config.dart';
import 'monster_animation_state.dart';

/// Single-source-of-truth animation controller for an interactive MamPet monster.
///
/// Handles:
/// - Smooth cross-pose blending between animation states (zero jarring snaps)
/// - Automatic natural eye blinking during [MonsterAnimation.idle]
/// - Chewing mouth alternation during [MonsterAnimation.eat]
/// - Persistent [MonsterAnimation.sleep] until [wakeUp] or tap interaction
/// - Playback speed adjustment (for Developer Animation Preview QA)
/// - Clean pause/resume when off-screen or backgrounded
class MonsterAnimationController extends ChangeNotifier {
  MonsterAnimation _state;
  MonsterAnimationConfig _config;
  final math.Random _rng;

  double _stateElapsedMs = 0.0;
  double _speed = 1.0;
  bool _paused = false;

  // Cross-pose blending snapshot captured on state transition
  Map<String, LayerTransform> _blendFromPose = const {};
  double _blendElapsedMs = 999.0;
  static const double _blendDurationMs = 180.0;

  // Natural blink scheduler
  double _blinkCountdownMs = 3000.0;
  double _blinkActiveRemainingMs = 0.0;

  // Recent interaction telemetry (for UI badges & Dev Preview)
  String? _lastTappedPart;
  int _reactionCounter = 0;

  // Monotonic command channel so external runtimes (OpenBone state machine)
  // observe every host trigger cleanly without duplicate polling.
  int _commandSeq = 0;
  MonsterAnimation _lastCommandState = MonsterAnimation.idle;
  bool _lastCommandForceRestart = false;
  double? _externalProgress;

  MonsterAnimationController({
    MonsterAnimation initialState = MonsterAnimation.idle,
    MonsterAnimationConfig? config,
    int? randomSeed,
  })  : _state = initialState,
        _lastCommandState = initialState,
        _config = config ??
            MonsterAnimationConfig.fallback(slug: 'generic', stage: 'baby'),
        _rng = math.Random(randomSeed) {
    _scheduleNextBlink();
  }

  MonsterAnimation get state => _state;
  MonsterAnimationConfig get config => _config;
  double get speed => _speed;
  bool get isPaused => _paused;
  bool get isSleeping => _state == MonsterAnimation.sleep;
  bool get isBlinking => _blinkActiveRemainingMs > 0.0;
  String? get lastTappedPart => _lastTappedPart;
  int get reactionCounter => _reactionCounter;
  int get commandSeq => _commandSeq;
  MonsterAnimation get lastCommandState => _lastCommandState;
  bool get lastCommandForceRestart => _lastCommandForceRestart;

  /// Normalized progress `[0.0 .. 1.0]` within the active state's cycle.
  double get normalizedProgress {
    final ext = _externalProgress;
    if (ext != null) return ext.clamp(0.0, 1.0);
    final dur = _config.stateConfig(_state).durationMs;
    if (dur <= 0) return 0.0;
    return (_stateElapsedMs / dur).clamp(0.0, 1.0);
  }

  /// Synchronizes state reported by an external runtime (e.g. OpenBone state machine
  /// returning automatically to `idle` at the end of a reaction clip).
  void syncExternalState(
    MonsterAnimation nextState, {
    String? tappedPart,
    double? progress,
    bool notify = true,
  }) {
    final changed = _state != nextState ||
        (tappedPart != null && _lastTappedPart != tappedPart);
    _state = nextState;
    if (tappedPart != null) {
      _lastTappedPart = tappedPart;
      _reactionCounter++;
    }
    _externalProgress = progress;
    if (changed && notify) {
      notifyListeners();
    }
  }

  /// Updates the active [MonsterAnimationConfig] when a rig loads or evolves.
  void attachConfig(MonsterAnimationConfig newConfig, {bool notify = true}) {
    if (identical(_config, newConfig)) return;
    _config = newConfig;
    _scheduleNextBlink();
    if (notify) notifyListeners();
  }

  /// Transitions smoothly into [nextState].
  void play(MonsterAnimation nextState, {bool forceRestart = true}) {
    if (!forceRestart && _state == nextState) return;
    _blendFromPose = evaluateCurrentPose();
    _blendElapsedMs = 0.0;
    _state = nextState;
    _stateElapsedMs = 0.0;
    _externalProgress = null;
    if (nextState != MonsterAnimation.idle) {
      _blinkActiveRemainingMs = 0.0;
    }
    _commandSeq++;
    _lastCommandState = nextState;
    _lastCommandForceRestart = forceRestart;
    notifyListeners();
  }

  /// Puts the monster into a peaceful looping sleep state until [wakeUp] is called.
  void sleep() {
    play(MonsterAnimation.sleep, forceRestart: false);
  }

  /// Gently wakes a sleeping monster with a cheerful reaction before settling into idle.
  void wakeUp() {
    if (_state == MonsterAnimation.sleep) {
      play(MonsterAnimation.happy);
    } else {
      play(MonsterAnimation.idle, forceRestart: false);
    }
  }

  /// Fires the dedicated OpenBone `wake` trigger directly back into `idle`.
  void wakeToIdle() {
    play(MonsterAnimation.idle, forceRestart: true);
  }

  /// Triggers an immediate natural eye blink (effective during awake open-eye states).
  void triggerBlink() {
    if (_state == MonsterAnimation.sleep) return;
    _blinkActiveRemainingMs = _config.blinkDurationMs.toDouble();
    _scheduleNextBlink();
    notifyListeners();
  }

  /// Responds to tapping a specific anatomical body part hitbox.
  MonsterAnimation reactToPart(String part, {String? preferredReaction}) {
    _lastTappedPart = part;
    _reactionCounter++;

    if (_state == MonsterAnimation.sleep) {
      wakeUp();
      return MonsterAnimation.happy;
    }

    final target = preferredReaction != null
        ? MonsterAnimation.fromCode(preferredReaction)
        : switch (part) {
            'head' || 'ears' || 'cap' || 'leaves' => MonsterAnimation.pet,
            'wing_left' ||
            'wing_right' ||
            'arm_left' ||
            'arm_right' ||
            'accessory' =>
              MonsterAnimation.play,
            _ => MonsterAnimation.happy,
          };

    play(target);
    return target;
  }

  /// Adjusts playback speed multiplier (clamped to `[0.25 .. 2.5]`).
  void setSpeed(double value) {
    final clamped = value.clamp(0.25, 2.5);
    if ((clamped - _speed).abs() < 0.001) return;
    _speed = clamped;
    notifyListeners();
  }

  void pause() {
    if (_paused) return;
    _paused = true;
    notifyListeners();
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    notifyListeners();
  }

  /// Advances internal animation clock by [delta]. Called by the widget [Ticker]
  /// or directly in unit tests.
  void tick(Duration delta) {
    if (_paused) return;
    // Cap large frame spikes (e.g. after returning from background) at 60ms.
    final dtMs = math.min(delta.inMicroseconds / 1000.0, 60.0) * _speed;
    if (dtMs <= 0.0) return;

    if (_blendElapsedMs < _blendDurationMs) {
      _blendElapsedMs = math.min(_blendElapsedMs + dtMs, _blendDurationMs);
    }

    final activeCfg = _config.stateConfig(_state);
    _stateElapsedMs += dtMs;

    if (_stateElapsedMs >= activeCfg.durationMs) {
      if (activeCfg.loop) {
        _stateElapsedMs = _stateElapsedMs % activeCfg.durationMs;
      } else {
        // Non-looping reaction completed -> smoothly blend back into idle!
        _blendFromPose = _evaluateRawPose(_state, 1.0);
        _blendElapsedMs = 0.0;
        _state = MonsterAnimation.idle;
        _stateElapsedMs = 0.0;
        _scheduleNextBlink();
      }
    }

    // Natural blinking during idle (when eyes are open)
    if (_state == MonsterAnimation.idle) {
      if (_blinkActiveRemainingMs > 0.0) {
        _blinkActiveRemainingMs = math.max(0.0, _blinkActiveRemainingMs - dtMs);
      } else {
        _blinkCountdownMs -= dtMs;
        if (_blinkCountdownMs <= 0.0) {
          _blinkActiveRemainingMs = _config.blinkDurationMs.toDouble();
          _scheduleNextBlink();
        }
      }
    } else {
      _blinkActiveRemainingMs = 0.0;
    }

    notifyListeners();
  }

  void _scheduleNextBlink() {
    final minMs = _config.blinkIntervalMinMs;
    final maxMs = math.max(minMs + 200, _config.blinkIntervalMaxMs);
    _blinkCountdownMs = (minMs + _rng.nextInt(maxMs - minMs)).toDouble();
  }

  /// Returns the active eye layer ID for the current frame (handling blink & sleep).
  String activeEyesLayerId() {
    final cfg = _config.stateConfig(_state);
    if (_state == MonsterAnimation.idle && _blinkActiveRemainingMs > 0.0) {
      return 'eyes_closed';
    }
    return cfg.eyes ?? 'eyes_open';
  }

  /// Returns the active mouth layer ID for the current frame (handling chew alternation).
  String activeMouthLayerId() {
    final cfg = _config.stateConfig(_state);
    final base = cfg.mouth ?? 'mouth_happy';
    final alt = cfg.mouthAlternate;
    if (alt == null) return base;
    // Alternate chewing rhythm 6 times across the eat cycle
    final step = (normalizedProgress * 6.0).floor();
    return step.isEven ? base : alt;
  }

  Map<String, LayerTransform> _evaluateRawPose(
    MonsterAnimation animState,
    double t,
  ) {
    final cfg = _config.stateConfig(animState);
    final result = <String, LayerTransform>{};
    cfg.tracks.forEach((layerId, track) {
      result[layerId] = track.evaluate(t);
    });
    return result;
  }

  /// Evaluates blended local transforms for every animated layer at the current tick.
  Map<String, LayerTransform> evaluateCurrentPose() {
    final current = _evaluateRawPose(_state, normalizedProgress);
    if (_blendElapsedMs >= _blendDurationMs || _blendFromPose.isEmpty) {
      return current;
    }
    final alpha = (_blendElapsedMs / _blendDurationMs).clamp(0.0, 1.0);
    // Smooth ease-out curve for seamless transition
    final eased = 1.0 - math.pow(1.0 - alpha, 3.0);
    final allKeys = <String>{..._blendFromPose.keys, ...current.keys};
    final blended = <String, LayerTransform>{};
    for (final k in allKeys) {
      final from = _blendFromPose[k] ?? LayerTransform.identity;
      final to = current[k] ?? LayerTransform.identity;
      blended[k] = LayerTransform.lerp(from, to, eased);
    }
    return blended;
  }
}
