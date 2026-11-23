import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/domain/models.dart';
import '../../core/providers/app_providers.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/confetti_overlay.dart';
import '../../core/widgets/element_chip.dart';
import '../../core/widgets/game_ui.dart';
import '../../core/widgets/monster_sprite.dart';
import '../../core/widgets/rarity_badge.dart';

/// Full hatching animation screen per PRD Section 9.3:
/// Fast shake 0.6s -> white flash 0.25s -> egg fade out -> Baby scale 0.7->1.07->1.0 + confetti 1s.
/// Supports Reduce Motion and "Lewati" button without ever losing the unlocked monster!
class HatchAnimationScreen extends ConsumerStatefulWidget {
  final String eggId;
  const HatchAnimationScreen({super.key, required this.eggId});

  @override
  ConsumerState<HatchAnimationScreen> createState() => _HatchAnimationScreenState();
}

class _HatchAnimationScreenState extends ConsumerState<HatchAnimationScreen>
    with TickerProviderStateMixin {
  late final AnimationController _shakeCtrl;
  late final AnimationController _flashCtrl;
  late final AnimationController _revealCtrl;
  late final Animation<double> _revealScale;

  UserMonster? _unlockedMonster;
  MonsterSpecies? _species;
  bool _loading = true;
  bool _revealed = false;
  bool _error = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _flashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _revealCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _revealScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.7, end: 1.07), weight: 65),
      TweenSequenceItem(tween: Tween(begin: 1.07, end: 1.0), weight: 35),
    ]).animate(CurvedAnimation(parent: _revealCtrl, curve: Curves.easeOut));

    _startHatchSequence();
  }

  Future<void> _startHatchSequence() async {
    final settings = ref.read(appSettingsProvider).valueOrNull;
    _reduceMotion = settings?.reduceMotion ?? false;

    // Crash-safe commit FIRST so reward is never lost even if user exits mid-animation!
    final result = await ref.read(databaseProvider).hatchEgg(widget.eggId);
    if (!mounted) return;

    if (result == null) {
      setState(() {
        _loading = false;
        _error = true;
      });
      return;
    }

    setState(() {
      _unlockedMonster = result.monster;
      _species = result.species;
      _loading = false;
    });

    if (_reduceMotion) {
      setState(() => _revealed = true);
      _revealCtrl.value = 1.0;
      return;
    }

    await _shakeCtrl.forward();
    if (!mounted || _revealed) return;

    await _flashCtrl.forward();
    if (!mounted || _revealed) return;

    setState(() => _revealed = true);
    _flashCtrl.reverse();
    _revealCtrl.forward();
  }

  void _skipAnimation() {
    _shakeCtrl.stop();
    _flashCtrl.value = 0;
    _revealCtrl.value = 1.0;
    setState(() => _revealed = true);
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    _flashCtrl.dispose();
    _revealCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveReduce =
        _reduceMotion || MediaQuery.disableAnimationsOf(context);

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error || _species == null || _unlockedMonster == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Penetasan')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Telur belum siap ditetaskan atau tidak ditemukan.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => context.pop(),
                child: const Text('Kembali'),
              ),
            ],
          ),
        ),
      );
    }

    final sp = _species!;
    final monster = _unlockedMonster!;

    return Scaffold(
      backgroundColor: _revealed ? sp.element.softColor : MamPetColors.creamBg,
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: !_revealed
                        ? TextButton(
                            onPressed: _skipAnimation,
                            child: const Text(
                              'Lewati',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          )
                        : IconButton(
                            onPressed: () => context.pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                  const Spacer(),
                  if (!_revealed)
                    AnimatedBuilder(
                      animation: _shakeCtrl,
                      builder: (context, child) {
                        final angle =
                            math.sin(_shakeCtrl.value * 12 * math.pi) * 0.14;
                        final dx =
                            math.sin(_shakeCtrl.value * 16 * math.pi) * 8;
                        return Transform.translate(
                          offset: Offset(dx, 0),
                          child: Transform.rotate(angle: angle, child: child),
                        );
                      },
                      child: Image.asset(
                        sp.element.crackedEggAsset,
                        width: 210,
                        height: 210,
                        cacheWidth: 420,
                      ),
                    )
                  else
                    AnimatedBuilder(
                      animation: _revealCtrl,
                      builder: (context, child) => Transform.scale(
                        scale: effectiveReduce ? 1.0 : _revealScale.value,
                        child: child,
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: sp.rarity.borderColor,
                                width: 1.5,
                              ),
                            ),
                            child: const Text(
                              'MONSTER BARU TERBUKA!',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.7,
                                color: MamPetColors.coralPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          MonsterSpriteWidget(
                            assetPath: sp.assetBaby,
                            size: 220,
                            animateIdle: true,
                            reduceMotion: effectiveReduce,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '${MamPetFormatters.formatSpeciesNumber(sp.id)} • ${sp.displayName}',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              RarityBadge(rarity: sp.rarity),
                              ElementChip(element: sp.element, compact: true),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            sp.flavorText,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13.5,
                              color: MamPetColors.cocoaMuted,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Spacer(),
                  if (_revealed) ...[
                    SizedBox(
                      width: double.infinity,
                      child: GameButton(
                        label: 'Jadikan Monster Aktif',
                        icon: Icons.star_rounded,
                        onPressed: () async {
                          await ref
                              .read(databaseProvider)
                              .setActiveMonster(monster.id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    '${sp.displayName} sekarang menjadi monster aktif!'),
                              ),
                            );
                            context.go('/home');
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: GameButton.secondary(
                        label: 'Lihat di MonsterDex',
                        onPressed: () {
                          context.pop();
                          context.push('/monster/${sp.id}');
                        },
                      ),
                    ),
                  ] else
                    const Text(
                      'Telur sedang menetas...',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: MamPetColors.cocoaMuted,
                      ),
                    ),
                ],
              ),
            ),
          ),

          // White flash layer
          if (!effectiveReduce)
            AnimatedBuilder(
              animation: _flashCtrl,
              builder: (_, _) {
                if (_flashCtrl.value <= 0.01) return const SizedBox.shrink();
                return IgnorePointer(
                  child: Container(
                    color: Colors.white.withValues(alpha: _flashCtrl.value),
                  ),
                );
              },
            ),

          // Confetti burst layer
          Positioned.fill(
            child: ConfettiBurstOverlay(
              active: _revealed,
              reduceMotion: effectiveReduce,
            ),
          ),
        ],
      ),
    );
  }
}
