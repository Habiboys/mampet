import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/domain/enums.dart';
import '../../core/providers/app_providers.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/grade_badge.dart';
import '../../core/widgets/monster_sprite.dart';

class FoodCategoryDetailScreen extends ConsumerStatefulWidget {
  final String categoryId;
  const FoodCategoryDetailScreen({super.key, required this.categoryId});

  @override
  ConsumerState<FoodCategoryDetailScreen> createState() =>
      _FoodCategoryDetailScreenState();
}

class _FoodCategoryDetailScreenState
    extends ConsumerState<FoodCategoryDetailScreen> {
  String _filter = 'all'; // all | discovered | undiscovered

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final allFoods = ref.watch(allMasterFoodsProvider).valueOrNull ?? const [];
    final discoveredIds = ref.watch(discoveredFoodIdsProvider).valueOrNull ?? const {};
    final discoveredCustom =
        ref.watch(discoveredCustomFoodsProvider).valueOrNull ?? const [];
    final masteries = ref.watch(categoryMasteriesProvider).valueOrNull ?? const {};
    final allMonsters = ref.watch(allMonstersProvider).valueOrNull ?? const [];

    final cat = categories.where((c) => c.id == widget.categoryId).firstOrNull;
    if (cat == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Kategori')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final mastery = masteries[cat.id];
    final color = MamPetFormatters.parseHexColor(cat.colorHex);
    final catCustomFoods = _filter == 'undiscovered'
        ? const []
        : discoveredCustom.where((cf) => cf.categoryId == cat.id).toList();
    final catFoods = allFoods.where((f) => f.categoryId == cat.id).where((f) {
      final d = discoveredIds.contains(f.id);
      if (_filter == 'discovered') return d;
      if (_filter == 'undiscovered') return !d;
      return true;
    }).toList();

    final linkedMonsters =
        allMonsters.where((m) => m.species.categoryId == cat.id).toList();

    return Scaffold(
      appBar: AppBar(title: Text(cat.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // Mastery & Grade Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(MamPetFormatters.categoryIcon(cat.icon),
                        color: color, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${mastery?.uniqueDiscoveredFoods ?? 0} / ${mastery?.totalMasterFoods ?? 30} Jenis Unik',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                            ),
                          ),
                          Text(
                            '${mastery?.categoryDays ?? 0} hari kategori • ${mastery?.distinctPlaces ?? 0} tempat berbeda • ${mastery?.totalLogs ?? 0} log',
                            style: const TextStyle(
                              fontSize: 12,
                              color: MamPetColors.cocoaMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GradeBadge(grade: mastery?.grade ?? CategoryGrade.c),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _nextGradeHint(
                    mastery?.grade ?? CategoryGrade.c,
                    mastery?.uniqueDiscoveredFoods ?? 0,
                    mastery?.distinctPlaces ?? 0,
                    mastery?.categoryDays ?? 0,
                  ),
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),

          if (linkedMonsters.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Monster Terkait Kategori Ini',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Row(
              children: linkedMonsters.map((m) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Card(
                      child: InkWell(
                        onTap: () => context.push('/monster/${m.species.id}'),
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              MonsterSpriteWidget(
                                assetPath: m.isUnlocked
                                    ? m.currentAsset
                                    : m.species.assetBaby,
                                size: 46,
                                isLocked: !m.isUnlocked,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      m.isUnlocked ? m.species.displayName : '???',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      m.isUnlocked
                                          ? 'Lv ${m.owned!.level}'
                                          : '${m.species.unlockUniqueFoods} unik • ${m.species.unlockCategoryDays} hari',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: MamPetColors.cocoaMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Semua'),
                selected: _filter == 'all',
                onSelected: (_) => setState(() => _filter = 'all'),
              ),
              ChoiceChip(
                label: const Text('Ditemukan'),
                selected: _filter == 'discovered',
                onSelected: (_) => setState(() => _filter = 'discovered'),
              ),
              ChoiceChip(
                label: const Text('Belum Ditemukan'),
                selected: _filter == 'undiscovered',
                onSelected: (_) => setState(() => _filter = 'undiscovered'),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (catCustomFoods.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text(
                'Menu Kustom Koleksi Pribadimu (Masuk FoodDex)',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: MamPetColors.skyAccent,
                ),
              ),
            ),
            ...catCustomFoods.map((cf) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: MamPetColors.skySoft,
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        color: MamPetColors.skyAccent,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      cf.name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: const Text(
                      'Tercatat otomatis di FoodDex • Menu Kustom',
                      style: TextStyle(fontSize: 12),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: MamPetColors.skySoft,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: const Text(
                        'KUSTOM',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: MamPetColors.skyAccent,
                        ),
                      ),
                    ),
                    onTap: () => context.push('/fooddex/custom'),
                  ),
                )),
            const SizedBox(height: 8),
          ],

          ...catFoods.map((food) {
            final disc = discoveredIds.contains(food.id);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: disc
                      ? MamPetColors.sageAccent.withValues(alpha: 0.16)
                      : MamPetColors.warmSurfaceAlt,
                  child: Icon(
                    disc ? Icons.check_circle_rounded : Icons.restaurant_rounded,
                    color: disc ? MamPetColors.sageAccent : MamPetColors.cocoaMuted,
                    size: 20,
                  ),
                ),
                title: Text(
                  food.canonicalName,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  food.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/fooddex/food/${food.id}'),
              ),
            );
          }),
        ],
      ),
    );
  }

  String _nextGradeHint(
    CategoryGrade current,
    int unique,
    int places,
    int days,
  ) {
    switch (current) {
      case CategoryGrade.c:
        return 'Target Grade B: $unique/3 jenis makanan unik.';
      case CategoryGrade.b:
        return 'Target Grade A: $unique/6 jenis makanan unik.';
      case CategoryGrade.a:
        return 'Target Grade S: $unique/10 unik + ($places/2 tempat ATAU $days/5 hari kategori).';
      case CategoryGrade.s:
        return 'Target Grade SS: $unique/18 unik + ($places/4 tempat ATAU $days/10 hari kategori).';
      case CategoryGrade.ss:
        return 'Luar biasa! Kamu telah mencapai penguasaan tertinggi Grade SS!';
    }
  }
}
