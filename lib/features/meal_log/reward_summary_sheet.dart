import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/domain/enums.dart';
import '../../core/domain/game_rules.dart';
import '../../core/domain/models.dart';
import '../../core/widgets/egg_sprite.dart';
import '../../core/widgets/game_ui.dart';
import '../../core/widgets/grade_badge.dart';
import '../../core/widgets/monster_sprite.dart';

Future<void> showRewardSummarySheet(
  BuildContext context, {
  required SaveMealResult result,
  required bool reduceMotion,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => _RewardSummaryBody(
      result: result,
      reduceMotion: reduceMotion,
    ),
  );
}

class _RewardSummaryBody extends StatelessWidget {
  final SaveMealResult result;
  final bool reduceMotion;

  const _RewardSummaryBody({
    required this.result,
    required this.reduceMotion,
  });

  @override
  Widget build(BuildContext context) {
    final monster = result.activeMonsterAfter;
    final species = result.activeMonsterSpecies;

    Widget xpBanner = GamePanel(
      gradient: const LinearGradient(
        colors: [Color(0xFFFFEFE6), Color(0xFFFFF8EE)],
      ),
      borderColor: MamPetColors.coralPrimary,
      lipColor: MamPetColors.coralDeep,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total XP Didapat',
                style: TextStyle(
                  fontFamily: 'Fredoka',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              Text(
                '+${result.totalXpAwarded} XP',
                style: const TextStyle(
                  fontFamily: 'Fredoka',
                  fontWeight: FontWeight.w700,
                  fontSize: 26,
                  color: MamPetColors.coralPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _xpRow('XP Sesi Makan', '+${result.sessionXpAwarded} XP'),
          _xpRow('Bonus Penemuan Master Baru',
              '+${result.discoveryXpAwarded} XP'),
          if (result.totalXpAwarded == 0 && !result.wasBackdated)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Kamu sudah punya catatan makanan ini atau slot sesi hari ini sudah terisi. Riwayatnya tetap tersimpan!',
                style: TextStyle(fontSize: 12, color: MamPetColors.cocoaMuted),
              ),
            ),
        ],
      ),
    );

    if (!reduceMotion) {
      xpBanner = xpBanner
          .animate()
          .scale(
            begin: const Offset(0.9, 0.9),
            end: const Offset(1, 1),
            duration: 380.ms,
            curve: Curves.easeOutBack,
          )
          .fadeIn(duration: 280.ms);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.celebration_rounded,
                    color: MamPetColors.coralPrimary, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Sesi Makan Tersimpan!',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            if (result.wasBackdated) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MamPetColors.warmSurfaceAlt,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Catatan tanggal lampau tersimpan ke riwayat dan FoodDex tanpa menambah XP hari ini.',
                  style:
                      TextStyle(fontSize: 12.5, color: MamPetColors.cocoaMuted),
                ),
              ),
            ],
            if (result.clockWarning) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Tanggal perangkat terdeteksi mundur dari catatan terakhir. Ledger tetap menjaga konsistensi hadiah.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
            const SizedBox(height: 16),

            xpBanner,

            if (monster != null && species != null) ...[
              const SizedBox(height: 14),
              GamePanel(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    MonsterSpriteWidget(
                      assetPath: species.assetForPhase(monster.phase),
                      size: 64,
                      animateIdle: true,
                      reduceMotion: reduceMotion,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                species.displayName,
                                style: const TextStyle(
                                  fontFamily: 'Fredoka',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Lv ${monster.level}',
                                style: const TextStyle(
                                  fontFamily: 'Fredoka',
                                  fontWeight: FontWeight.w700,
                                  color: MamPetColors.coralPrimary,
                                ),
                              ),
                              if (result.leveledUp) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: MamPetColors.sageAccent,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: const Text(
                                    'LEVEL UP!',
                                    style: TextStyle(
                                      fontFamily: 'Fredoka',
                                      color: Colors.white,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          GameProgressBar(
                            progress: GameRules.xpProgress(monster.xpTotal).progress,
                            fillColor: species.element.color,
                            height: 12,
                            reduceMotion: reduceMotion,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (result.newlyDiscoveredFoods.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'Makanan baru ditemukan! +5 XP',
                style: TextStyle(
                  fontFamily: 'Fredoka',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: MamPetColors.sageAccent,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: result.newlyDiscoveredFoods
                    .map(
                      (f) => Chip(
                        avatar: const Icon(Icons.auto_awesome_rounded,
                            size: 16, color: MamPetColors.sageAccent),
                        label: Text(
                          f.canonicalName,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],

            if (result.gradeUpgrades.isNotEmpty) ...[
              const SizedBox(height: 14),
              ...result.gradeUpgrades.map(
                (up) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GamePanel(
                    color: up.newGrade.surfaceColor,
                    borderColor: up.newGrade.color,
                    lipColor: up.newGrade.color,
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        GradeBadge(grade: up.newGrade, compact: true),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Penguasaan ${up.categoryName} naik ke Grade ${up.newGrade.code}!',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],

            if (result.eggProgressed && result.updatedIncubatingEgg != null) ...[
              const SizedBox(height: 14),
              GamePanel(
                color: result.updatedIncubatingEgg!.element.softColor,
                borderColor: result.updatedIncubatingEgg!.element.color,
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    EggSpriteWidget(
                      element: result.updatedIncubatingEgg!.element,
                      status: result.updatedIncubatingEgg!.status,
                      size: 54,
                      reduceMotion: reduceMotion,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        result.updatedIncubatingEgg!.status == EggStatus.ready
                            ? '3/3 sesi tercapai! Telur siap ditetaskan di Nursery!'
                            : '${result.updatedIncubatingEgg!.hatchProgress}/${GameRules.sessionsToHatch} sesi makan valid menuju penetasan.',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (result.newlyGrantedEggs.isNotEmpty) ...[
              const SizedBox(height: 14),
              ...result.newlyGrantedEggs.map(
                (egg) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GamePanel(
                    color: egg.element.softColor,
                    borderColor: egg.element.color,
                    lipColor: egg.element.color,
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        EggSpriteWidget(
                          element: egg.element,
                          status: egg.status,
                          size: 58,
                          reduceMotion: reduceMotion,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Telur ${egg.element.label} ditemukan. Masukkan ke inkubator untuk mulai menetaskan.',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],

            if (result.starterMasteryBonusSpeciesIds.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Milestone starter tercapai! Kamu mendapat +25 Poin Mastery kosmetik pengganti telur duplikat.',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                ),
              ),
            ],

            const SizedBox(height: 20),
            if (result.newlyGrantedEggs.isNotEmpty ||
                result.updatedIncubatingEgg?.status == EggStatus.ready)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GameButton.sky(
                  label: 'Buka Nursery Telur',
                  icon: Icons.egg_alt_rounded,
                  onPressed: () {
                    Navigator.pop(context);
                    context.push('/nursery');
                  },
                ),
              ),
            GameButton(
              label: 'Selesai',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _xpRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style:
                  const TextStyle(fontSize: 13, color: MamPetColors.cocoaMuted)),
          Text(value,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
