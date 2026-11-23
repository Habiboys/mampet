import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/domain/enums.dart';
import '../animation/monster_animation_config.dart';
import '../animation/monster_animation_controller.dart';
import '../animation/monster_animation_state.dart';
import '../animation/monster_interaction_handler.dart';
import '../animation/monster_rig_renderer.dart';
import '../animation/monster_rig_repository.dart';
import '../models/monster_rig.dart';
import '../openbone/openbone_renderer.dart';
import '../openbone/openbone_repository.dart';
import '../openbone/openbone_runtime.dart';

/// Reusable interactive 2D animated MamPet character widget.
///
/// Primary runtime: loads OpenBone 0.4.8 binary packages (`.obonb` with weighted
/// skeletal mesh, expression attachment swaps, state machine cross-fades, and
/// `face_touch` click hitbox) from `assets/animated_monsters/` via GPU-accelerated
/// [Canvas.drawVertices].
///
/// Fallback runtime: for forms marked `source_blocked` or `review_only` in
/// `collection_manifest.json` (excluded from production OpenBone loading), safely
/// renders the static/whole-body fallback sprite without crashing.
///
/// For list/grid previews (such as MonsterDex), use [MonsterPreview] instead so
/// 20 characters are never animated simultaneously.
class InteractiveMonster extends StatefulWidget {
  /// Accepts either canonical slug (`'fire_dragon'`) or MamPet species ID (`'01'`).
  final String monsterId;
  final EvolutionPhase evolutionStage;
  final MonsterAnimationController? controller;
  final MonsterAnimation initialAnimation;
  final double size;
  final bool reduceMotion;
  final bool enableInteractions;
  final bool showDebugPivots;
  final bool showDebugHitboxes;
  final String? semanticLabel;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final void Function(String part, MonsterAnimation reaction)? onPartTap;
  final void Function(MonsterRig rig, MonsterAnimationConfig config)? onRigLoaded;
  final void Function(OpenBoneLoadResult result)? onOpenBoneLoaded;

  const InteractiveMonster({
    super.key,
    required this.monsterId,
    required this.evolutionStage,
    this.controller,
    this.initialAnimation = MonsterAnimation.idle,
    this.size = 180,
    this.reduceMotion = false,
    this.enableInteractions = true,
    this.showDebugPivots = false,
    this.showDebugHitboxes = false,
    this.semanticLabel,
    this.onTap,
    this.onDoubleTap,
    this.onPartTap,
    this.onRigLoaded,
    this.onOpenBoneLoaded,
  });

  @override
  State<InteractiveMonster> createState() => _InteractiveMonsterState();
}

class _InteractiveMonsterState extends State<InteractiveMonster>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  MonsterAnimationController? _ownedController;
  MonsterAnimationController get _ctrl => widget.controller ?? _ownedController!;

  late Ticker _ticker;
  Duration _lastTick = Duration.zero;
  int _loadSeq = 0;
  bool _didLoadInitial = false;

  // OpenBone primary runtime state
  LoadedOpenBonePackage? _openBonePkg;
  OpenBonePlayer? _openBonePlayer;
  OpenBoneLoadResult? _openBoneResult;
  final ValueNotifier<int> _openBoneFrameTick = ValueNotifier<int>(0);
  int _lastSeenCommandSeq = 0;
  DateTime? _lastTapAt;
  static const Duration _doubleTapWindow = Duration(milliseconds: 320);

  // Legacy fallback rig state (used only when OpenBone is unavailable / blocked)
  LoadedMonsterRig? _legacyRig;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (widget.controller == null) {
      _ownedController = MonsterAnimationController(
        initialState: widget.initialAnimation,
      );
    }
    _attachControllerListener(_ctrl);

    _ticker = createTicker(_onTick);
    _syncTicker();
  }

  void _attachControllerListener(MonsterAnimationController ctrl) {
    _lastSeenCommandSeq = ctrl.commandSeq;
    ctrl.addListener(_onControllerChanged);
  }

  void _detachControllerListener(MonsterAnimationController ctrl) {
    ctrl.removeListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    final player = _openBonePlayer;
    if (player == null) return;
    if (_ctrl.commandSeq == _lastSeenCommandSeq) return;
    _lastSeenCommandSeq = _ctrl.commandSeq;

    final cmd = _ctrl.lastCommandState;
    final trigger = cmd.openBoneTrigger;
    player.fireTrigger(trigger, forceRestart: _ctrl.lastCommandForceRestart);
    _openBoneFrameTick.value++;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didLoadInitial) {
      _didLoadInitial = true;
      _loadCharacter();
    }
  }

  @override
  void didUpdateWidget(covariant InteractiveMonster oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      final oldCtrl = oldWidget.controller ?? _ownedController;
      if (oldCtrl != null) {
        _detachControllerListener(oldCtrl);
      }
      if (oldWidget.controller == null && widget.controller != null) {
        _ownedController?.dispose();
        _ownedController = null;
      } else if (oldWidget.controller != null && widget.controller == null) {
        _ownedController = MonsterAnimationController(
          initialState: widget.initialAnimation,
        );
      }
      _attachControllerListener(_ctrl);
      if (_legacyRig != null) {
        _ctrl.attachConfig(_legacyRig!.animations, notify: false);
      }
    }

    if (oldWidget.monsterId != widget.monsterId ||
        oldWidget.evolutionStage != widget.evolutionStage) {
      _loadCharacter();
    }

    if (oldWidget.reduceMotion != widget.reduceMotion) {
      _syncTicker();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _ctrl.pause();
    } else if (state == AppLifecycleState.resumed) {
      _lastTick = Duration.zero;
      _ctrl.resume();
    }
  }

  void _syncTicker() {
    if (widget.reduceMotion) {
      if (_ticker.isActive) _ticker.stop();
    } else {
      if (!_ticker.isActive) {
        _lastTick = Duration.zero;
        _ticker.start();
      }
    }
  }

  void _onTick(Duration elapsed) {
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      return;
    }
    final delta = elapsed - _lastTick;
    _lastTick = elapsed;

    final player = _openBonePlayer;
    if (player != null) {
      if (_ctrl.isPaused) return;
      final dtSec =
          math.min(delta.inMicroseconds / 1000000.0, 0.06) * _ctrl.speed;
      if (dtSec <= 0.0) return;
      player.advance(dtSec);
      _openBoneFrameTick.value++;
      return;
    }

    _ctrl.tick(delta);
  }

  void _releaseOpenBone() {
    _openBonePkg?.release();
    _openBonePkg = null;
    _openBonePlayer = null;
  }

  Future<void> _loadCharacter() async {
    final seq = ++_loadSeq;
    final cachedOb = OpenBoneRepository.getCached(
      widget.monsterId,
      widget.evolutionStage,
    );

    if (cachedOb != null) {
      if (cachedOb.isReady) {
        _applyOpenBone(cachedOb, notifyAsync: true, seq: seq);
        return;
      } else {
        // Known review_only or source_blocked -> use safe fallback right away
        _releaseOpenBone();
        _openBoneResult = cachedOb;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && seq == _loadSeq) {
            widget.onOpenBoneLoaded?.call(cachedOb);
          }
        });
        await _loadLegacyFallback(seq);
        return;
      }
    }

    final bundle = DefaultAssetBundle.of(context);
    final obRes = await OpenBoneRepository.load(
      widget.monsterId,
      widget.evolutionStage,
      bundle: bundle,
    );
    if (!mounted || seq != _loadSeq) return;

    if (obRes.isReady) {
      _applyOpenBone(obRes, notifyAsync: false, seq: seq);
      if (mounted) setState(() {});
      return;
    }

    // Excluded (`review_only` / `source_blocked`) or absent in bundle -> fallback
    _releaseOpenBone();
    _openBoneResult = obRes;
    widget.onOpenBoneLoaded?.call(obRes);
    await _loadLegacyFallback(seq, bundle: bundle);
  }

  void _applyOpenBone(
    OpenBoneLoadResult res, {
    required bool notifyAsync,
    required int seq,
  }) {
    final pkg = res.package!;
    if (!identical(_openBonePkg, pkg)) {
      _releaseOpenBone();
      pkg.retain();
      _openBonePkg = pkg;
    }
    _openBoneResult = res;
    _legacyRig = null;

    final player = OpenBonePlayer(
      pkg.document,
      stateMachineName: pkg.packageManifest.stateMachineName,
      onStateChanged: (stateName) {
        if (!mounted) return;
        final mapped = MonsterAnimation.fromOpenBoneState(stateName);
        _ctrl.syncExternalState(
          mapped,
          progress: _openBonePlayer?.normalizedProgress,
        );
      },
    );

    // Apply requested starting state (e.g. `evolve` in EvolutionDialog or `sleep`)
    final desired = _ctrl.state != MonsterAnimation.idle
        ? _ctrl.state
        : widget.initialAnimation;
    if (desired != MonsterAnimation.idle) {
      player.fireTrigger(desired.openBoneTrigger, forceRestart: true);
      _ctrl.syncExternalState(
        MonsterAnimation.fromOpenBoneState(player.activeStateName),
        notify: !notifyAsync,
      );
    }

    _openBonePlayer = player;
    _lastSeenCommandSeq = _ctrl.commandSeq;
    _openBoneFrameTick.value++;

    if (notifyAsync) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && seq == _loadSeq) {
          widget.onOpenBoneLoaded?.call(res);
        }
      });
    } else {
      widget.onOpenBoneLoaded?.call(res);
    }
  }

  Future<void> _loadLegacyFallback(int seq, {AssetBundle? bundle}) async {
    final cached = MonsterRigRepository.getCached(
      widget.monsterId,
      widget.evolutionStage,
    );
    if (cached != null) {
      _legacyRig = cached;
      _ctrl.attachConfig(cached.animations, notify: false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && seq == _loadSeq) {
          widget.onRigLoaded?.call(cached.rig, cached.animations);
        }
      });
      if (mounted) setState(() {});
      return;
    }

    final b = bundle ?? DefaultAssetBundle.of(context);
    final res = await MonsterRigRepository.load(
      widget.monsterId,
      widget.evolutionStage,
      bundle: b,
    );
    if (!mounted || seq != _loadSeq) return;
    _legacyRig = res;
    _ctrl.attachConfig(res.animations);
    widget.onRigLoaded?.call(res.rig, res.animations);
    if (mounted) setState(() {});
  }

  void _handleOpenBoneTapUp(TapUpDetails details) {
    if (!widget.enableInteractions) return;
    final player = _openBonePlayer;
    if (player == null) return;

    final now = DateTime.now();
    final isDoubleTap =
        _lastTapAt != null && now.difference(_lastTapAt!) <= _doubleTapWindow;
    _lastTapAt = isDoubleTap ? null : now;

    if (isDoubleTap) {
      if (player.activeStateName == 'sleep') {
        player.fireTrigger('happy', forceRestart: true);
        _ctrl.syncExternalState(MonsterAnimation.happy, tappedPart: 'body');
        widget.onPartTap?.call('body', MonsterAnimation.happy);
      } else {
        player.fireTrigger('play', forceRestart: true);
        _ctrl.syncExternalState(MonsterAnimation.play, tappedPart: 'double_tap');
        widget.onPartTap?.call('double_tap', MonsterAnimation.play);
      }
      _openBoneFrameTick.value++;
      widget.onDoubleTap?.call();
      return;
    }

    if (player.activeStateName == 'sleep') {
      player.fireTrigger('happy', forceRestart: true);
      _ctrl.syncExternalState(MonsterAnimation.happy, tappedPart: 'body');
      _openBoneFrameTick.value++;
      widget.onPartTap?.call('body', MonsterAnimation.happy);
      widget.onTap?.call();
      return;
    }

    final artboardPt = OpenBoneCanvasPainter.localToArtboard(
      player.doc,
      Size.square(widget.size),
      details.localPosition,
    );
    final triggered = player.handleArtboardTap(artboardPt.dx, artboardPt.dy);

    if (triggered != null) {
      final reaction = MonsterAnimation.fromOpenBoneState(triggered);
      _ctrl.syncExternalState(reaction, tappedPart: 'face');
      _openBoneFrameTick.value++;
      widget.onPartTap?.call('face', reaction);
      widget.onTap?.call();
      return;
    }

    // Outside face hitbox -> cheerful happy bounce
    player.fireTrigger('happy', forceRestart: true);
    _ctrl.syncExternalState(MonsterAnimation.happy, tappedPart: 'body');
    _openBoneFrameTick.value++;
    widget.onPartTap?.call('body', MonsterAnimation.happy);
    widget.onTap?.call();
  }

  void _handleOpenBoneLongPress() {
    if (!widget.enableInteractions) return;
    final player = _openBonePlayer;
    if (player == null) return;
    player.fireTrigger('special', forceRestart: true);
    _ctrl.syncExternalState(MonsterAnimation.special, tappedPart: 'special');
    _openBoneFrameTick.value++;
    widget.onPartTap?.call('special', MonsterAnimation.special);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detachControllerListener(_ctrl);
    _releaseOpenBone();
    _openBoneFrameTick.dispose();
    _ticker.dispose();
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveReduce =
        widget.reduceMotion || MediaQuery.disableAnimationsOf(context);
    if (effectiveReduce && _ticker.isActive) {
      _ticker.stop();
    }

    final pkg = _openBonePkg;
    final player = _openBonePlayer;

    if (pkg != null && !pkg.isDisposed && player != null) {
      if (effectiveReduce) {
        player.resetToSetupPose();
      }
      final painted = SizedBox.square(
        dimension: widget.size,
        child: ValueListenableBuilder<int>(
          valueListenable: _openBoneFrameTick,
          builder: (_, tick, _) {
            return CustomPaint(
              size: Size.square(widget.size),
              painter: OpenBoneCanvasPainter(
                player: player,
                textures: pkg.textures,
                repaintTick: tick,
                showSleepZzz:
                    !effectiveReduce && player.activeStateName == 'sleep',
                sleepPhase: player.normalizedProgress,
                showDebugBones: widget.showDebugPivots,
                showDebugHitboxes: widget.showDebugHitboxes,
              ),
            );
          },
        ),
      );

      final interactive = widget.enableInteractions
          ? GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: _handleOpenBoneTapUp,
              onLongPress: _handleOpenBoneLongPress,
              child: painted,
            )
          : painted;

      if (widget.semanticLabel != null) {
        return Semantics(
          label: widget.semanticLabel,
          button: widget.enableInteractions,
          child: interactive,
        );
      }
      return interactive;
    }

    // While OpenBone is loading OR when form is review_only/source_blocked:
    final slug = MonsterRig.resolveSlug(widget.monsterId);
    final isKnownBlocked =
        _openBoneResult?.formEntry?.isSourceBlocked == true;
    final fallbackNotes = _openBoneResult?.formEntry?.reason;

    final rig = _legacyRig?.rig ??
        MonsterRig.fallback(
          slug: slug,
          stage: widget.evolutionStage,
          notes: fallbackNotes,
        );

    final content = AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        final pose = effectiveReduce || isKnownBlocked
            ? const <String, LayerTransform>{}
            : _ctrl.evaluateCurrentPose();
        return MonsterRigRenderer(
          rig: rig,
          pose: pose,
          activeEyesLayerId:
              effectiveReduce ? 'eyes_open' : _ctrl.activeEyesLayerId(),
          activeMouthLayerId:
              effectiveReduce ? 'mouth_happy' : _ctrl.activeMouthLayerId(),
          size: widget.size,
          showSleepZzz: !effectiveReduce && _ctrl.isSleeping,
          sleepPhase: _ctrl.normalizedProgress,
          showDebugPivots: widget.showDebugPivots,
          showDebugHitboxes: widget.showDebugHitboxes,
          highlightedPart: _ctrl.lastTappedPart,
        );
      },
    );

    final interactive = MonsterInteractionHandler(
      rig: rig,
      controller: _ctrl,
      size: widget.size,
      enabled: widget.enableInteractions,
      onTap: widget.onTap,
      onDoubleTap: widget.onDoubleTap,
      onPartTap: widget.onPartTap,
      child: content,
    );

    if (widget.semanticLabel != null) {
      return Semantics(
        label: widget.semanticLabel,
        button: widget.enableInteractions,
        child: interactive,
      );
    }
    return interactive;
  }
}
