import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/domain/enums.dart';
import '../../core/domain/game_rules.dart';
import '../../core/domain/models.dart';
import '../../core/providers/app_providers.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/element_chip.dart';
import '../../core/widgets/grade_badge.dart';
import '../../core/widgets/monster_sprite.dart';
import '../../core/widgets/rarity_badge.dart';
import '../monsters/animation/monster_animation_controller.dart';
import '../monsters/animation/monster_animation_state.dart';
import '../monsters/widgets/interactive_monster.dart';

class MonsterDetailScreen extends ConsumerStatefulWidget {
  final String speciesId;
  const MonsterDetailScreen({super.key, required this.speciesId});

  @override
  ConsumerState<MonsterDetailScreen> createState() => _MonsterDetailScreenState();
}

class _MonsterDetailScreenState extends ConsumerState<MonsterDetailScreen> {
  String? _bondToast;
  late final MonsterAnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = MonsterAnimationController();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _tapBond(UserMonster owned) async {
    final res = await ref.read(databaseProvider).tapMonsterBond(owned.id);
    if (!mounted) return;
    setState(() {
      _bondToast = res.gained
          ? 'Bond +${GameRules.bondTapGain}! (${res.newBond}/100)'
          : 'Monster senang berinteraksi! ♥';
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _bondToast = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final allMonsters = ref.watch(allMonstersProvider).valueOrNull ?? const [];
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final reduceMotion =
        ref.watch(appSettingsProvider).valueOrNull?.reduceMotion ?? false;

    final monster =
        allMonsters.where((m) => m.species.id == widget.speciesId).firstOrNull;
    if (monster == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final cat =
        categories.where((c) => c.id == monster.species.categoryId).firstOrNull;

    return monster.isUnlocked
        ? _buildUnlockedDetail(context, monster, cat, reduceMotion)
        : _buildLockedDetail(context, monster, cat, reduceMotion);
  }

  Widget _buildLockedDetail(
    BuildContext context,
    MonsterWithSpecies monster,
    FoodCategory? cat,
    bool reduceMotion,
  ) {
    final sp = monster.species;
    final mastery = monster.categoryMastery;
    final uniqueNow = mastery?.uniqueDiscoveredFoods ?? 0;
    final daysNow = mastery?.categoryDays ?? 0;
    final hasEgg = monster.egg != null && monster.egg!.status != EggStatus.hatched;

    return Scaffold(
      appBar: AppBar(
        title: Text('${MamPetFormatters.formatSpeciesNumber(sp.id)} • ???'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          RarityCardFrame(
            rarity: null,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    MonsterSpriteWidget(
                      assetPath: sp.assetBaby,
                      size: 190,
                      isLocked: true,
                      reduceMotion: reduceMotion,
                    ),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  '${MamPetFormatters.formatSpeciesNumber(sp.id)} • ???',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '??? — Temukan lebih banyak hidangan untuk mengungkap monster ini.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: MamPetColors.cocoaMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Syarat Membuka Telur',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${cat?.name ?? sp.categoryId}: $uniqueNow/${sp.unlockUniqueFoods} makanan unik • $daysNow/${sp.unlockCategoryDays} hari',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: MamPetColors.coralPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _progressRow(
                    'Makanan unik kategori',
                    uniqueNow,
                    sp.unlockUniqueFoods,
                  ),
                  const SizedBox(height: 10),
                  _progressRow(
                    'Hari makan kategori (sesi valid)',
                    daysNow,
                    sp.unlockCategoryDays,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Setelah syarat tercapai, telur otomatis masuk ke Nursery. Tetaskan dengan 3 sesi makan valid untuk membuka identitas monster ini!',
                    style: TextStyle(fontSize: 12, color: MamPetColors.cocoaMuted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          if (hasEgg)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: FilledButton.icon(
                onPressed: () => context.push('/nursery'),
                icon: const Icon(Icons.egg_alt_rounded),
                label: const Text('Telur Tersedia — Buka Nursery'),
              ),
            ),
          FilledButton.tonalIcon(
            onPressed: () => context.push('/fooddex/category/${sp.categoryId}'),
            icon: const Icon(Icons.explore_rounded),
            label: Text('Jelajahi Makanan ${cat?.name ?? "Kategori"}'),
          ),
        ],
      ),
    );
  }

  Widget _buildUnlockedDetail(
    BuildContext context,
    MonsterWithSpecies monster,
    FoodCategory? cat,
    bool reduceMotion,
  ) {
    final sp = monster.species;
    final owned = monster.owned!;
    final xpProg = GameRules.xpProgress(owned.xpTotal);
    final mastery = monster.categoryMastery;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${MamPetFormatters.formatSpeciesNumber(sp.id)} • ${sp.displayName}',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        children: [
          RarityCardFrame(
            rarity: sp.rarity,
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Row(
                  children: [
                    RarityBadge(rarity: sp.rarity),
                    const SizedBox(width: 8),
                    ElementChip(element: sp.element, compact: true),
                    const Spacer(),
                    GradeBadge(grade: monster.grade),
                  ],
                ),
                const SizedBox(height: 12),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    InteractiveMonster(
                      monsterId: sp.slug,
                      evolutionStage: owned.phase,
                      controller: _animCtrl,
                      size: 204,
                      reduceMotion: reduceMotion,
                      onPartTap: (_, _) => _tapBond(owned),
                    ),
                    if (_bondToast != null)
                      Positioned(
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: MamPetColors.coralPrimary,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            _bondToast!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                AnimatedBuilder(
                  animation: _animCtrl,
                  builder: (_, _) => Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.favorite_rounded, size: 15),
                        label: const Text('Elus', style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          _animCtrl.play(MonsterAnimation.pet);
                          _tapBond(owned);
                        },
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.celebration_rounded, size: 15),
                        label: const Text('Main', style: TextStyle(fontSize: 12)),
                        onPressed: () => _animCtrl.play(MonsterAnimation.play),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.restaurant_rounded, size: 15),
                        label: const Text('Makan', style: TextStyle(fontSize: 12)),
                        onPressed: () => _animCtrl.play(MonsterAnimation.eat),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.auto_awesome_rounded, size: 15),
                        label: const Text('Spesial', style: TextStyle(fontSize: 12)),
                        onPressed: () => _animCtrl.play(MonsterAnimation.special),
                      ),
                      ActionChip(
                        avatar: Icon(
                          _animCtrl.isSleeping
                              ? Icons.wb_sunny_rounded
                              : Icons.bedtime_rounded,
                          size: 15,
                        ),
                        label: Text(
                          _animCtrl.isSleeping ? 'Bangun' : 'Tidur',
                          style: const TextStyle(fontSize: 12),
                        ),
                        onPressed: () {
                          if (_animCtrl.isSleeping) {
                            _animCtrl.wakeToIdle();
                          } else {
                            _animCtrl.sleep();
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  sp.displayName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Fase ${owned.phase.label} • Level ${owned.level} • ${cat?.name ?? sp.categoryId}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: MamPetColors.cocoaMuted,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  sp.flavorText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13.5, height: 1.45),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      owned.level >= GameRules.maxLevel
                          ? 'Level Maksimal (30)'
                          : 'XP ke Lv ${owned.level + 1}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 12.5),
                    ),
                    Text(
                      owned.level >= GameRules.maxLevel
                          ? '${owned.xpTotal} XP'
                          : '${xpProg.current}/${xpProg.required} XP',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                        color: MamPetColors.coralPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: xpProg.progress,
                    minHeight: 9,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: owned.isActive
                      ? FilledButton.tonalIcon(
                          onPressed: null,
                          icon: const Icon(Icons.star_rounded),
                          label: const Text('Sedang Menjadi Monster Aktif'),
                        )
                      : FilledButton.icon(
                          onPressed: () async {
                            await ref
                                .read(databaseProvider)
                                .setActiveMonster(owned.id);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${sp.displayName} sekarang menjadi monster aktif!',
                                  ),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.star_outline_rounded),
                          label: const Text('Jadikan Monster Aktif'),
                        ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Bond Card (Cosmetic, zero pressure)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.favorite_rounded, color: Colors.pinkAccent),
                      const SizedBox(width: 8),
                      Text(
                        'Bond: ${owned.bond}/100',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                      const Spacer(),
                      Text(
                        GameRules.bondTierTitle(owned.bond),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          color: Colors.pinkAccent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: owned.bond / GameRules.maxBond,
                      minHeight: 8,
                      color: Colors.pinkAccent,
                      backgroundColor: Colors.pinkAccent.withValues(alpha: 0.15),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ketuk gambar monster di atas untuk menambah Bond (+5 setiap 4 jam). Bond bersifat kosmetik dan tidak pernah berkurang.'
                    '${owned.masteryPoints > 0 ? '\nPoin Mastery Starter: +${owned.masteryPoints}' : ''}',
                    style: const TextStyle(
                        fontSize: 12, color: MamPetColors.cocoaMuted),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Evolution Timeline — unreached phases remain silhouettes with Lv 10 / Lv 25 labels!
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Timeline Evolusi',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _evoStageCard(
                        phase: EvolutionPhase.baby,
                        asset: sp.assetBaby,
                        reached: true,
                        isCurrent: owned.phase == EvolutionPhase.baby,
                        reduceMotion: reduceMotion,
                      ),
                      const Icon(Icons.arrow_forward_rounded,
                          size: 16, color: MamPetColors.cocoaMuted),
                      _evoStageCard(
                        phase: EvolutionPhase.young,
                        asset: sp.assetYoung,
                        reached: owned.level >= GameRules.youngEvolutionLevel,
                        isCurrent: owned.phase == EvolutionPhase.young,
                        reduceMotion: reduceMotion,
                      ),
                      const Icon(Icons.arrow_forward_rounded,
                          size: 16, color: MamPetColors.cocoaMuted),
                      _evoStageCard(
                        phase: EvolutionPhase.adult,
                        asset: sp.assetAdult,
                        reached: owned.level >= GameRules.adultEvolutionLevel,
                        isCurrent: owned.phase == EvolutionPhase.adult,
                        reduceMotion: reduceMotion,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Category Discovery Mastery Card
          if (mastery != null)
            Card(
              child: ListTile(
                title: Text(
                  'Penguasaan ${cat?.name ?? sp.categoryId}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${mastery.uniqueDiscoveredFoods}/${mastery.totalMasterFoods} jenis unik • ${mastery.categoryDays} hari • ${mastery.distinctPlaces} tempat',
                ),
                trailing: GradeBadge(grade: mastery.grade),
                onTap: () => context.push('/fooddex/category/${sp.categoryId}'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _evoStageCard({
    required EvolutionPhase phase,
    required String asset,
    required bool reached,
    required bool isCurrent,
    required bool reduceMotion,
  }) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: isCurrent
              ? MamPetColors.coralSoft
              : MamPetColors.warmSurfaceAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isCurrent
                ? MamPetColors.coralPrimary
                : MamPetColors.warmOutline,
            width: isCurrent ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            MonsterSpriteWidget(
              assetPath: asset,
              size: 66,
              isLocked: !reached,
              reduceMotion: reduceMotion,
            ),
            const SizedBox(height: 6),
            Text(
              phase.label,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
            Text(
              reached ? 'Terbuka' : 'Lv ${phase.minLevel}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: reached
                    ? MamPetColors.sageAccent
                    : MamPetColors.cocoaMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressRow(String label, int current, int target) {
    final pct = target > 0 ? (current / target).clamp(0.0, 1.0) : 1.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12.5)),
            Text('$current / $target',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 12.5)),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(value: pct, minHeight: 8),
        ),
      ],
    );
  }
}
