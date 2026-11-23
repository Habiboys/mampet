import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/domain/enums.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/widgets/game_ui.dart';
import '../animation/monster_animation_config.dart';
import '../animation/monster_animation_controller.dart';
import '../animation/monster_animation_state.dart';
import '../models/monster_rig.dart';
import '../openbone/openbone_repository.dart';
import '../widgets/interactive_monster.dart';

enum _PreviewBg {
  checkerboard('Transparan', Icons.grid_on_rounded),
  neutral('Netral', Icons.crop_square_rounded),
  meadow('Habitat', Icons.park_rounded);

  const _PreviewBg(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Developer Animation Preview & QA Lab (Section 12).
/// Allows inspecting any of the 20 MamPet species across Baby/Young/Adult stages,
/// triggering all 7 animation states, testing body-part hitboxes, checking
/// transparent seams, adjusting speed, toggling pivot/hitbox overlays, and
/// monitoring real-time FPS/frame timing.
class AnimationPreviewScreen extends ConsumerStatefulWidget {
  final String? initialMonsterId;
  final EvolutionPhase initialStage;

  const AnimationPreviewScreen({
    super.key,
    this.initialMonsterId,
    this.initialStage = EvolutionPhase.baby,
  });

  @override
  ConsumerState<AnimationPreviewScreen> createState() =>
      _AnimationPreviewScreenState();
}

class _AnimationPreviewScreenState
    extends ConsumerState<AnimationPreviewScreen> {
  late String _selectedSlug;
  late EvolutionPhase _selectedStage;
  late final MonsterAnimationController _controller;

  _PreviewBg _bgMode = _PreviewBg.checkerboard;
  bool _showPivots = false;
  bool _showHitboxes = false;
  MonsterRig? _currentRig;
  MonsterAnimationConfig? _currentAnimConfig;
  OpenBoneLoadResult? _openBoneResult;
  String? _lastInteractionText;

  // Lightweight live frame-timing telemetry
  double _avgFrameMs = 16.6;
  double _fps = 60.0;

  @override
  void initState() {
    super.initState();
    _selectedSlug = MonsterRig.resolveSlug(
      widget.initialMonsterId ?? 'fire_dragon',
    );
    _selectedStage = widget.initialStage;
    _controller = MonsterAnimationController();
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    _controller.dispose();
    super.dispose();
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    if (!mounted || timings.isEmpty) return;
    double sumUs = 0;
    for (final t in timings) {
      sumUs += t.totalSpan.inMicroseconds;
    }
    final avgMs = (sumUs / timings.length) / 1000.0;
    final fps = avgMs > 0 ? (1000.0 / avgMs).clamp(1.0, 120.0) : 60.0;
    // Exponential moving average to avoid jittery flicker
    _avgFrameMs = _avgFrameMs * 0.8 + avgMs * 0.2;
    _fps = _fps * 0.8 + fps * 0.2;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final allMonsters = ref.watch(allMonstersProvider).valueOrNull ?? const [];
    final speciesBySlug = {
      for (final m in allMonsters) m.species.slug: m.species,
    };

    final obEntry = _openBoneResult?.formEntry;
    final isObReady = _openBoneResult?.isReady == true;
    final String statusLabel;
    final Color tierColor;
    if (isObReady) {
      statusLabel = 'OpenBone Ready';
      tierColor = const Color(0xFF16A34A);
    } else if (obEntry?.isReviewOnly == true) {
      statusLabel = 'Review Only (Fallback)';
      tierColor = const Color(0xFFD97706);
    } else if (obEntry?.isSourceBlocked == true) {
      statusLabel = 'Source Blocked';
      tierColor = const Color(0xFFDC2626);
    } else {
      statusLabel = _currentRig?.rigTier.label ?? 'Memuat...';
      tierColor = switch (_currentRig?.rigTier) {
        RigTier.fullLayered => const Color(0xFF16A34A),
        RigTier.partialRig => const Color(0xFF0EA5E9),
        RigTier.wholeBody => const Color(0xFFD97706),
        RigTier.needsManualArt => const Color(0xFFDC2626),
        null => MamPetColors.cocoaMuted,
      };
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Animation Preview Lab'),
        actions: [
          AnimatedBuilder(
            animation: _controller,
            builder: (_, _) => IconButton(
              tooltip: _controller.isPaused ? 'Lanjutkan' : 'Jeda',
              icon: Icon(
                _controller.isPaused
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded,
              ),
              onPressed: () {
                if (_controller.isPaused) {
                  _controller.resume();
                } else {
                  _controller.pause();
                }
              },
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        children: [
          // 1. Species & Stage selector
          GamePanel(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.pets_rounded,
                        size: 18, color: MamPetColors.coralPrimary),
                    const SizedBox(width: 6),
                    const Text(
                      'Pilih Monster & Fase Evolusi',
                      style: TextStyle(
                        fontFamily: 'Fredoka',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: tierColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                            color: tierColor.withValues(alpha: 0.45)),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          color: tierColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _selectedSlug,
                  decoration: const InputDecoration(
                    labelText: 'Spesies (20 Monster)',
                    isDense: true,
                  ),
                  items: MonsterRig.allSlugs.map((slug) {
                    final sp = speciesBySlug[slug];
                    final label = sp != null
                        ? '#${sp.id} ${sp.displayName} ($slug)'
                        : slug;
                    return DropdownMenuItem(
                      value: slug,
                      child: Text(label, overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _selectedSlug = v;
                      _lastInteractionText = null;
                    });
                    _controller.play(MonsterAnimation.idle);
                  },
                ),
                const SizedBox(height: 10),
                SegmentedButton<EvolutionPhase>(
                  segments: const [
                    ButtonSegment(
                      value: EvolutionPhase.baby,
                      label: Text('Baby'),
                    ),
                    ButtonSegment(
                      value: EvolutionPhase.young,
                      label: Text('Young'),
                    ),
                    ButtonSegment(
                      value: EvolutionPhase.adult,
                      label: Text('Adult'),
                    ),
                  ],
                  selected: {_selectedStage},
                  onSelectionChanged: (s) {
                    setState(() {
                      _selectedStage = s.first;
                      _lastInteractionText = null;
                    });
                    _controller.play(MonsterAnimation.idle);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 2. Interactive Preview Canvas Stage
          GamePanel(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                // Top telemetry strip: State + FPS + Background Switcher
                Row(
                  children: [
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (_, _) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: MamPetColors.coralSoft,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          'State: ${_controller.state.label}${_controller.isBlinking ? ' • Blink' : ''}',
                          style: const TextStyle(
                            fontFamily: 'Fredoka',
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: MamPetColors.coralPrimary,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_fps.toStringAsFixed(0)} FPS • ${_avgFrameMs.toStringAsFixed(1)} ms',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: MamPetColors.cocoaMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(
                    height: 270,
                    width: double.infinity,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: _PreviewBackgroundLayer(mode: _bgMode),
                        ),
                        InteractiveMonster(
                          key: ValueKey('$_selectedSlug/${_selectedStage.code}'),
                          monsterId: _selectedSlug,
                          evolutionStage: _selectedStage,
                          controller: _controller,
                          size: 235,
                          showDebugPivots: _showPivots,
                          showDebugHitboxes: _showHitboxes,
                          onPartTap: (part, reaction) {
                            setState(() {
                              _lastInteractionText =
                                  'Tap "$part" → ${reaction.label}';
                            });
                          },
                          onOpenBoneLoaded: (res) {
                            if (!mounted) return;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                setState(() {
                                  _openBoneResult = res;
                                  if (res.isReady) {
                                    _currentRig = null;
                                    _currentAnimConfig = null;
                                  }
                                });
                              }
                            });
                          },
                          onRigLoaded: (rig, anims) {
                            if (!mounted) return;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                setState(() {
                                  _currentRig = rig;
                                  _currentAnimConfig = anims;
                                });
                              }
                            });
                          },
                        ),
                        if (_lastInteractionText != null)
                          Positioned(
                            top: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: MamPetColors.espresso
                                    .withValues(alpha: 0.82),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                _lastInteractionText!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        if (obEntry != null && !obEntry.isExported)
                          Positioned(
                            bottom: 8,
                            left: 12,
                            right: 12,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: (obEntry.isSourceBlocked
                                        ? const Color(0xFFDC2626)
                                        : const Color(0xFFD97706))
                                    .withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                obEntry.reason ??
                                    'Paket OpenBone belum tersedia untuk produksi; memakai sprite fallback.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          )
                        else if (_currentRig?.rigTier == RigTier.needsManualArt)
                          Positioned(
                            bottom: 8,
                            left: 12,
                            right: 12,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDC2626)
                                    .withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _currentRig!.notes ??
                                    'Aset sumber perlu digambar manual oleh ilustrator.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Background & Debug Overlay Controls
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final mode in _PreviewBg.values)
                      ChoiceChip(
                        avatar: Icon(mode.icon, size: 15),
                        label: Text(mode.label, style: const TextStyle(fontSize: 12)),
                        selected: _bgMode == mode,
                        onSelected: (_) => setState(() => _bgMode = mode),
                      ),
                    FilterChip(
                      label: const Text('Pivots', style: TextStyle(fontSize: 12)),
                      selected: _showPivots,
                      onSelected: (v) => setState(() => _showPivots = v),
                    ),
                    FilterChip(
                      label: const Text('Hitboxes', style: TextStyle(fontSize: 12)),
                      selected: _showHitboxes,
                      onSelected: (v) => setState(() => _showHitboxes = v),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 3. Trigger Animation States + Speed Slider
          GamePanel(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Trigger State & Interaksi',
                  style: TextStyle(
                    fontFamily: 'Fredoka',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 10),
                AnimatedBuilder(
                  animation: _controller,
                  builder: (_, _) => Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final st in MonsterAnimation.values)
                        ChoiceChip(
                          label: Text(st.label),
                          selected: _controller.state == st,
                          onSelected: (_) {
                            if (st == MonsterAnimation.sleep) {
                              _controller.sleep();
                            } else {
                              _controller.play(st);
                            }
                          },
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.visibility_off_rounded, size: 16),
                        label: const Text('Blink'),
                        onPressed: _controller.triggerBlink,
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.wb_sunny_rounded, size: 16),
                        label: const Text('Wake Up'),
                        onPressed: _controller.wakeToIdle,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                AnimatedBuilder(
                  animation: _controller,
                  builder: (_, _) => Row(
                    children: [
                      const Text(
                        'Kecepatan:',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                      ),
                      Expanded(
                        child: Slider(
                          value: _controller.speed,
                          min: 0.25,
                          max: 2.0,
                          divisions: 7,
                          label: '${_controller.speed.toStringAsFixed(2)}×',
                          onChanged: _controller.setSpeed,
                        ),
                      ),
                      Text(
                        '${_controller.speed.toStringAsFixed(2)}×',
                        style: const TextStyle(
                          fontFamily: 'Fredoka',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 4. OpenBone / Rig Metadata Inspector
          if (isObReady)
            GamePanel(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'OpenBone 0.4.8 Metadata',
                    style: TextStyle(
                      fontFamily: 'Fredoka',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _metaRow(
                    'Monster / Stage',
                    '${obEntry!.monsterName} (${obEntry.monsterSlug} / ${obEntry.stage})',
                  ),
                  _metaRow(
                    'Runtime',
                    'OpenBone 0.4.8 Weighted Mesh (GPU drawVertices)',
                  ),
                  _metaRow(
                    'State Machine',
                    _openBoneResult!.package!.packageManifest.stateMachineName ??
                        _openBoneResult!.package!.document.stateMachines.firstOrNull?.name ??
                        '-',
                  ),
                  _metaRow(
                    'Geometri Mesh',
                    '${_openBoneResult!.package!.document.totalMeshVertices} vertices • '
                        '${_openBoneResult!.package!.document.totalMeshTriangles} triangles • '
                        '${_openBoneResult!.package!.document.bones.length} bones',
                  ),
                  _metaRow(
                    'Ekspresi Wajah',
                    'Mata: ${obEntry.eyesAttachment ? 'Aktif' : 'Statis'} • '
                        'Mulut: ${obEntry.mouthAttachment ? 'Aktif' : 'Statis'}',
                  ),
                  if (_openBoneResult!.package!.packageManifest.expressionRevision
                      case final rev?)
                    _metaRow(
                      'Revisi Ekspresi',
                      'v${rev.version} • '
                          '${rev.defaultEyes ?? 'eyes_open'} + ${rev.defaultMouth ?? 'mouth_relaxed'}'
                          '${rev.eyesRedrawnOpen ? ' (mata baru)' : ''}'
                          '${rev.beakPreserved ? ' • paruh asli' : ''}',
                    ),
                  _metaRow(
                    'Klip (${_openBoneResult!.package!.document.animations.length})',
                    _openBoneResult!.package!.document.animations
                        .map((a) => '${a.name} (${a.duration.toStringAsFixed(1)}s)')
                        .join(', '),
                  ),
                ],
              ),
            )
          else if (_currentRig != null)
            GamePanel(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Rig & Asset Metadata',
                    style: TextStyle(
                      fontFamily: 'Fredoka',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _metaRow('Monster / Stage',
                      '${_currentRig!.monsterId} / ${_currentRig!.stage}'),
                  _metaRow('Rig Tier', _currentRig!.rigTier.label),
                  _metaRow('Archetype', _currentRig!.archetype),
                  _metaRow(
                    'Layers (${_currentRig!.layers.length})',
                    _currentRig!.layers.isEmpty
                        ? 'Tidak ada (needs manual art)'
                        : _currentRig!.layers.map((l) => l.id).join(', '),
                  ),
                  _metaRow(
                    'Hitboxes (${_currentRig!.hitboxes.length})',
                    _currentRig!.hitboxes
                        .map((h) => '${h.part}→${h.reaction}')
                        .join(', '),
                  ),
                  if (_currentAnimConfig != null)
                    _metaRow(
                      'Blink Interval',
                      '${_currentAnimConfig!.blinkIntervalMinMs}–${_currentAnimConfig!.blinkIntervalMaxMs} ms',
                    ),
                  if (_currentRig!.notes != null &&
                      _currentRig!.notes!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      _currentRig!.notes!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: MamPetColors.cocoaMuted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _metaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: MamPetColors.cocoaMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewBackgroundLayer extends StatelessWidget {
  final _PreviewBg mode;
  const _PreviewBackgroundLayer({required this.mode});

  @override
  Widget build(BuildContext context) {
    switch (mode) {
      case _PreviewBg.checkerboard:
        return CustomPaint(painter: _CheckerboardPainter());
      case _PreviewBg.neutral:
        return Container(color: const Color(0xFFFAF5EC));
      case _PreviewBg.meadow:
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFCFF2FF),
                Color(0xFFF3FDF7),
                Color(0xFFA7E8B8),
              ],
              stops: [0.0, 0.65, 1.0],
            ),
          ),
        );
    }
  }
}

class _CheckerboardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const tile = 16.0;
    final light = Paint()..color = const Color(0xFFF3F4F6);
    final dark = Paint()..color = const Color(0xFFDCDFE5);
    for (double y = 0; y < size.height; y += tile) {
      for (double x = 0; x < size.width; x += tile) {
        final isEven = ((x / tile).floor() + (y / tile).floor()).isEven;
        canvas.drawRect(Rect.fromLTWH(x, y, tile, tile), isEven ? light : dark);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerboardPainter oldDelegate) => false;
}
