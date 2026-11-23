import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/domain/enums.dart';
import '../../core/domain/game_rules.dart';
import '../../core/domain/models.dart';
import '../../core/providers/app_providers.dart';
import '../../core/widgets/egg_sprite.dart';
import '../../core/widgets/element_chip.dart';
import '../../core/widgets/game_ui.dart';

class NurseryScreen extends ConsumerStatefulWidget {
  const NurseryScreen({super.key});

  @override
  ConsumerState<NurseryScreen> createState() => _NurseryScreenState();
}

class _NurseryScreenState extends ConsumerState<NurseryScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rayCtrl;

  @override
  void initState() {
    super.initState();
    _rayCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _rayCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allEggs = ref.watch(allEggsProvider).valueOrNull ?? const [];
    final allMonsters = ref.watch(allMonstersProvider).valueOrNull ?? const [];
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final reduceMotion =
        ref.watch(appSettingsProvider).valueOrNull?.reduceMotion ?? false;

    final activeEgg =
        allEggs.where((e) => e.status.isActiveInIncubator).firstOrNull;
    final queuedEggs =
        allEggs.where((e) => e.status == EggStatus.queued).toList();
    final hatchedEggs =
        allEggs.where((e) => e.status == EggStatus.hatched).toList();

    final speciesMap = {for (final m in allMonsters) m.species.id: m.species};
    final catMap = {for (final c in categories) c.id: c.name};

    return Scaffold(
      appBar: AppBar(title: const Text('Nursery & Inkubator')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        children: [
          const Text(
            'Inkubator Aktif (Maks. 1)',
            style: TextStyle(
              fontFamily: 'Fredoka',
              fontWeight: FontWeight.w700,
              fontSize: 16.5,
            ),
          ),
          const SizedBox(height: 10),
          if (activeEgg != null)
            _buildActiveIncubatorCard(
              context,
              activeEgg,
              speciesMap[activeEgg.speciesId],
              catMap,
              reduceMotion,
            )
          else
            GamePanel(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: MamPetColors.skySoft,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: MamPetColors.skyAccent.withValues(alpha: 0.4),
                        width: 2.2,
                      ),
                    ),
                    child: const Icon(
                      Icons.egg_outlined,
                      size: 42,
                      color: MamPetColors.skyAccent,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Inkubator Kosong',
                    style: TextStyle(
                      fontFamily: 'Fredoka',
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    queuedEggs.isNotEmpty
                        ? 'Pilih salah satu telur di antrean di bawah untuk mulai menetaskan!'
                        : 'Telur baru muncul setelah kamu menjelajahi makanan dalam kategori.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: MamPetColors.cocoaMuted,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 22),

          Text(
            'Antrean Telur (${queuedEggs.length})',
            style: const TextStyle(
              fontFamily: 'Fredoka',
              fontWeight: FontWeight.w700,
              fontSize: 16.5,
            ),
          ),
          const SizedBox(height: 10),
          if (queuedEggs.isEmpty)
            GamePanel(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text(
                    'Telur baru muncul setelah kamu menjelajahi makanan dalam kategori.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: MamPetColors.cocoaMuted),
                  ),
                  const SizedBox(height: 12),
                  GameButton.secondary(
                    label: 'Lihat Target di FoodDex',
                    icon: Icons.menu_book_rounded,
                    compact: true,
                    height: 44,
                    onPressed: () => context.go('/fooddex'),
                  ),
                ],
              ),
            )
          else
            ...queuedEggs.map((egg) {
              final sp = speciesMap[egg.speciesId];
              final catName = sp != null ? catMap[sp.categoryId] ?? '' : '';
              final incubatorBusy = activeEgg != null;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GamePanel(
                  borderColor: egg.element.color.withValues(alpha: 0.55),
                  lipColor: egg.element.color.withValues(alpha: 0.45),
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      EggSpriteWidget(
                        element: egg.element,
                        status: EggStatus.queued,
                        size: 66,
                        reduceMotion: reduceMotion,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Telur ${egg.element.label}',
                              style: const TextStyle(
                                fontFamily: 'Fredoka',
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Dari kategori $catName',
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: MamPetColors.cocoaMuted,
                              ),
                            ),
                            if (incubatorBusy)
                              const Padding(
                                padding: EdgeInsets.only(top: 4),
                                child: Text(
                                  'Menunggu inkubator kosong',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: MamPetColors.cocoaMuted,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      GameButton(
                        label: 'Inkubasi',
                        color: egg.element.color,
                        compact: true,
                        height: 42,
                        onPressed: incubatorBusy
                            ? null
                            : () async {
                                HapticFeedback.mediumImpact();
                                final ok = await ref
                                    .read(databaseProvider)
                                    .startEggIncubation(egg.id);
                                if (ok && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Telur ${egg.element.label} masuk inkubator! Catat 3 sesi makan valid untuk menetaskannya.',
                                      ),
                                    ),
                                  );
                                }
                              },
                      ),
                    ],
                  ),
                ),
              );
            }),

          if (hatchedEggs.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text(
              'Riwayat Menetas (${hatchedEggs.length})',
              style: const TextStyle(
                fontFamily: 'Fredoka',
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: MamPetColors.cocoaMuted,
              ),
            ),
            const SizedBox(height: 8),
            ...hatchedEggs.map((egg) {
              final sp = speciesMap[egg.speciesId];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GamePanel(
                  radius: 18,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  onTap: sp != null
                      ? () => context.push('/monster/${sp.id}')
                      : null,
                  child: Row(
                    children: [
                      Icon(egg.element.icon, color: egg.element.color),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sp?.displayName ?? 'Monster Menetas',
                              style: const TextStyle(
                                fontFamily: 'Fredoka',
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              'Telur ${egg.element.label} • Sudah menetas',
                              style: const TextStyle(
                                fontSize: 12,
                                color: MamPetColors.cocoaMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          color: MamPetColors.cocoaMuted),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildActiveIncubatorCard(
    BuildContext context,
    MonsterEgg egg,
    MonsterSpecies? species,
    Map<String, String> catMap,
    bool reduceMotion,
  ) {
    final isReady = egg.status == EggStatus.ready;
    final catName = species != null ? catMap[species.categoryId] ?? '' : '';
    const stepLabels = ['Sesi 1', 'Retak!', 'Siap!'];

    return GamePanel(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [egg.element.softColor, Colors.white],
      ),
      borderColor: egg.element.color,
      lipColor: egg.element.color.withValues(alpha: 0.78),
      borderWidth: isReady ? 2.8 : 2.0,
      radius: 26,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ElementChip(element: egg.element),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                decoration: BoxDecoration(
                  color: isReady
                      ? MamPetColors.sageAccent
                      : egg.element.color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  egg.status.label,
                  style: TextStyle(
                    fontFamily: 'Fredoka',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isReady ? Colors.white : egg.element.color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: 210,
            height: 196,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Rotating sunburst rays behind Ready egg!
                if (isReady && !reduceMotion)
                  AnimatedBuilder(
                    animation: _rayCtrl,
                    builder: (_, _) => CustomPaint(
                      size: const Size(210, 210),
                      painter: SunburstRaysPainter(
                        color: egg.element.color,
                        rotation: _rayCtrl.value * 2 * math.pi,
                      ),
                    ),
                  ),
                // Cozy straw nest oval beneath egg
                Positioned(
                  bottom: 14,
                  child: Container(
                    width: 136,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD9A05B),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: const Color(0xFF925E28),
                        width: 2.2,
                      ),
                    ),
                  ),
                ),
                EggSpriteWidget(
                  element: egg.element,
                  status: egg.status,
                  size: 164,
                  reduceMotion: reduceMotion,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Telur ${egg.element.label} ($catName)',
            style: const TextStyle(
              fontFamily: 'Fredoka',
              fontWeight: FontWeight.w700,
              fontSize: 19,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isReady
                ? '3/3 sesi makan valid selesai! Telur siap ditetaskan!'
                : '${egg.hatchProgress}/${GameRules.sessionsToHatch} sesi makan valid menuju penetasan.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              color: MamPetColors.cocoaMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: List.generate(GameRules.sessionsToHatch, (i) {
              final done = i < egg.hatchProgress;
              return Expanded(
                child: Column(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: done ? egg.element.color : Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: done
                              ? MamPetColors.espresso.withValues(alpha: 0.7)
                              : MamPetColors.warmOutline,
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: done
                          ? const Icon(Icons.check_rounded,
                              color: Colors.white, size: 19)
                          : Text(
                              '${i + 1}',
                              style: const TextStyle(
                                fontFamily: 'Fredoka',
                                fontWeight: FontWeight.w700,
                                color: MamPetColors.cocoaMuted,
                              ),
                            ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      stepLabels[i],
                      style: TextStyle(
                        fontFamily: 'Fredoka',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: done
                            ? egg.element.color
                            : MamPetColors.cocoaMuted,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 18),
          if (isReady)
            SizedBox(
              width: double.infinity,
              child: GameButton.sage(
                label: 'Tetaskan Sekarang!',
                icon: Icons.auto_awesome_rounded,
                onPressed: () {
                  HapticFeedback.heavyImpact();
                  context.push('/nursery/hatch/${egg.id}');
                },
              ),
            )
          else
            const Text(
              'Tips: Setiap sesi makan valid hari ini yang memberi XP akan menambah +1 progres inkubasi.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: MamPetColors.cocoaMuted),
            ),
        ],
      ),
    );
  }
}
