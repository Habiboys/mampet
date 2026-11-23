import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/domain/enums.dart';
import '../../core/domain/models.dart';
import '../../core/widgets/confetti_overlay.dart';
import '../monsters/animation/monster_animation_state.dart';
import '../monsters/widgets/interactive_monster.dart';

Future<void> showEvolutionCelebrationDialog(
  BuildContext context, {
  required MonsterSpecies species,
  required EvolutionPhase fromPhase,
  required EvolutionPhase toPhase,
  required int newLevel,
  required bool reduceMotion,
}) {
  return showDialog(
    context: context,
    barrierDismissible: true,
    builder: (_) => _EvolutionDialog(
      species: species,
      fromPhase: fromPhase,
      toPhase: toPhase,
      newLevel: newLevel,
      reduceMotion: reduceMotion,
    ),
  );
}

class _EvolutionDialog extends StatefulWidget {
  final MonsterSpecies species;
  final EvolutionPhase fromPhase;
  final EvolutionPhase toPhase;
  final int newLevel;
  final bool reduceMotion;

  const _EvolutionDialog({
    required this.species,
    required this.fromPhase,
    required this.toPhase,
    required this.newLevel,
    required this.reduceMotion,
  });

  @override
  State<_EvolutionDialog> createState() => _EvolutionDialogState();
}

class _EvolutionDialogState extends State<_EvolutionDialog> {
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    if (widget.reduceMotion) {
      _revealed = true;
    } else {
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _revealed = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final asset = _revealed
        ? widget.species.assetForPhase(widget.toPhase)
        : widget.species.assetForPhase(widget.fromPhase);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Lewati'),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: widget.species.element.softColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _revealed ? 'EVOLUSI BERHASIL!' : 'BEREVOLUSI...',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      color: widget.species.element.color,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: Duration(milliseconds: widget.reduceMotion ? 150 : 600),
                  transitionBuilder: (child, anim) => ScaleTransition(
                    scale: Tween(begin: 0.75, end: 1.0).animate(
                      CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
                    ),
                    child: FadeTransition(opacity: anim, child: child),
                  ),
                  child: InteractiveMonster(
                    key: ValueKey(asset),
                    monsterId: widget.species.slug,
                    evolutionStage: _revealed ? widget.toPhase : widget.fromPhase,
                    initialAnimation: _revealed
                        ? MonsterAnimation.evolve
                        : MonsterAnimation.happy,
                    size: 186,
                    reduceMotion: widget.reduceMotion,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.species.displayName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${widget.fromPhase.label} → ${widget.toPhase.label} (Lv ${widget.newLevel})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: MamPetColors.coralPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Bentuk evolusi baru kini terbuka di MonsterDex!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: MamPetColors.cocoaMuted),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Keren! Lanjutkan'),
                  ),
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: ConfettiBurstOverlay(
              active: _revealed,
              reduceMotion: widget.reduceMotion,
            ),
          ),
        ],
      ),
    );
  }
}
