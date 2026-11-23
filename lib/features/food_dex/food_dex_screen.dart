import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/domain/enums.dart';
import '../../core/domain/models.dart';
import '../../core/providers/app_providers.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/text_normalizer.dart';
import '../../core/widgets/game_ui.dart';
import '../../core/widgets/grade_badge.dart';

class FoodDexScreen extends ConsumerStatefulWidget {
  const FoodDexScreen({super.key});

  @override
  ConsumerState<FoodDexScreen> createState() => _FoodDexScreenState();
}

class _FoodDexScreenState extends ConsumerState<FoodDexScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _filter = 'all'; // all | discovered | undiscovered

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final allFoods = ref.watch(allMasterFoodsProvider).valueOrNull ?? const [];
    final discoveredIds =
        ref.watch(discoveredFoodIdsProvider).valueOrNull ?? const {};
    final masteries =
        ref.watch(categoryMasteriesProvider).valueOrNull ?? const {};
    final customFoods = ref.watch(customFoodsProvider).valueOrNull ?? const [];
    final discoveredCustom =
        ref.watch(discoveredCustomFoodsProvider).valueOrNull ?? const [];
    final stats = ref.watch(personalStatsProvider).valueOrNull;
    final reduceMotion =
        ref.watch(appSettingsProvider).valueOrNull?.reduceMotion ?? false;

    final queryNorm = normalizeFoodText(_searchCtrl.text);
    final isSearching = queryNorm.isNotEmpty || _filter != 'all';

    final filteredFoods = isSearching
        ? allFoods.where((f) {
            final isDisc = discoveredIds.contains(f.id);
            if (_filter == 'discovered' && !isDisc) return false;
            if (_filter == 'undiscovered' && isDisc) return false;
            if (queryNorm.isEmpty) return true;
            if (f.normalizedName.contains(queryNorm)) return true;
            return f.aliases
                .any((a) => normalizeFoodText(a).contains(queryNorm));
          }).toList()
        : const <MasterFood>[];

    final filteredCustom = (isSearching && _filter != 'undiscovered')
        ? discoveredCustom.where((cf) {
            if (queryNorm.isEmpty) return true;
            return cf.normalizedName.contains(queryNorm);
          }).toList()
        : const <CustomFood>[];

    final catMap = {for (final c in categories) c.id: c};
    final unmappedCustomCount =
        customFoods.where((c) => c.mappedFoodId == null).length;
    final totalDiscoveredAll = discoveredIds.length + discoveredCustom.length;
    final totalCatalogAll = allFoods.length + discoveredCustom.length;
    final pct =
        totalCatalogAll == 0 ? 0.0 : totalDiscoveredAll / totalCatalogAll;

    return Scaffold(
      appBar: AppBar(
        title: const Text('FoodDex'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: GameButton.secondary(
              label:
                  'Custom${unmappedCustomCount > 0 ? ' ($unmappedCustomCount)' : ''}',
              icon: Icons.edit_note_rounded,
              compact: true,
              height: 40,
              onPressed: () => context.push('/fooddex/custom'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 36),
        children: [
          // Tactile Cozy Encyclopedia Banner
          GamePanel(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFEFE6), Color(0xFFFFF8EE)],
            ),
            borderColor: MamPetColors.coralPrimary,
            lipColor: MamPetColors.coralDeep,
            child: Row(
              children: [
                SizedBox(
                  width: 70,
                  height: 70,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: pct,
                        strokeWidth: 8,
                        backgroundColor: Colors.white,
                        color: MamPetColors.coralPrimary,
                        strokeCap: StrokeCap.round,
                      ),
                      Text(
                        '${(pct * 100).round()}%',
                        style: const TextStyle(
                          fontFamily: 'Fredoka',
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: MamPetColors.espresso,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$totalDiscoveredAll / ${allFoods.length} Hidangan',
                        style: const TextStyle(
                          fontFamily: 'Fredoka',
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: MamPetColors.espresso,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${discoveredIds.length} Master${discoveredCustom.isNotEmpty ? ' + ${discoveredCustom.length} Kustom' : ''} • ${stats?.totalItemsLogged ?? 0} catatan',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: MamPetColors.cocoaMuted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Buka menu unik untuk naik Grade & raih telur monster!',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: MamPetColors.cocoaMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (discoveredIds.isEmpty) ...[
            const SizedBox(height: 12),
            GamePanel(
              child: Row(
                children: [
                  const Icon(Icons.explore_rounded,
                      size: 30, color: MamPetColors.coralPrimary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Belum ada makanan yang kamu temukan',
                          style: TextStyle(
                              fontFamily: 'Fredoka',
                              fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Catat makanan dari katalog untuk mulai membuka FoodDex & telur monster.',
                          style: TextStyle(
                            fontSize: 12,
                            color: MamPetColors.cocoaMuted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        GameButton(
                          label: 'Catat Makanan',
                          compact: true,
                          height: 40,
                          onPressed: () => context.go('/log'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Cari 600+ makanan atau alias (nasgor, bakso, kopsu)...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close_rounded),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('12 Kategori'),
                selected: _filter == 'all' && queryNorm.isEmpty,
                onSelected: (_) {
                  _searchCtrl.clear();
                  setState(() => _filter = 'all');
                },
              ),
              ChoiceChip(
                label: Text('Ditemukan ($totalDiscoveredAll)'),
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

          const SizedBox(height: 14),

          if (isSearching) ...[
            Text(
              'Hasil Pencarian (${filteredFoods.length + filteredCustom.length})',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
                color: MamPetColors.cocoaMuted,
              ),
            ),
            const SizedBox(height: 8),
            if (filteredFoods.isEmpty && filteredCustom.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'Tidak ada hidangan yang cocok dengan filter ini.',
                    style: TextStyle(color: MamPetColors.cocoaMuted),
                  ),
                ),
              )
            else ...[
              ...filteredCustom.map((cf) {
                final cat = catMap[cf.categoryId];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GamePanel(
                    radius: 18,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    onTap: () => context.push('/fooddex/custom'),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          backgroundColor: MamPetColors.skySoft,
                          child: Icon(
                            Icons.auto_awesome_rounded,
                            color: MamPetColors.skyAccent,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cf.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900, fontSize: 14.5),
                              ),
                              Text(
                                '${cat?.name ?? ''} • Menu Kustom Koleksi Pribadi',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: MamPetColors.cocoaMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
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
                      ],
                    ),
                  ),
                );
              }),
              ...filteredFoods.take(100).map((f) {
                final disc = discoveredIds.contains(f.id);
                final cat = catMap[f.categoryId];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GamePanel(
                    radius: 18,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    onTap: () => context.push('/fooddex/food/${f.id}'),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: disc
                              ? MamPetColors.sageSoft
                              : MamPetColors.warmSurfaceAlt,
                          child: Icon(
                            disc
                                ? Icons.check_circle_rounded
                                : Icons.lock_outline_rounded,
                            color: disc
                                ? MamPetColors.sageAccent
                                : MamPetColors.cocoaMuted,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                f.canonicalName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900, fontSize: 14.5),
                              ),
                              Text(
                                '${cat?.name ?? ''}${f.aliases.isNotEmpty ? ' • ${f.aliases.take(2).join(', ')}' : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
          ] else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: categories.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 11,
                mainAxisSpacing: 13,
                childAspectRatio: 0.90,
              ),
              itemBuilder: (context, idx) {
                final cat = categories[idx];
                final mastery = masteries[cat.id];
                final color = MamPetFormatters.parseHexColor(cat.colorHex);
                final unique = mastery?.uniqueDiscoveredFoods ?? 0;
                final total = mastery?.totalMasterFoods ?? 50;
                final grade = mastery?.grade ?? CategoryGrade.c;

                Widget tile = GamePanel(
                  radius: 22,
                  borderColor: unique > 0
                      ? color.withValues(alpha: 0.65)
                      : MamPetColors.warmOutline,
                  lipColor: unique > 0
                      ? color.withValues(alpha: 0.55)
                      : const Color(0xFFE0CEBA),
                  padding: const EdgeInsets.all(13),
                  onTap: () => context.push('/fooddex/category/${cat.id}'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: color.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Icon(
                              MamPetFormatters.categoryIcon(cat.icon),
                              color: color,
                              size: 22,
                            ),
                          ),
                          GradeBadge(grade: grade, compact: true),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        cat.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Fredoka',
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '$unique/$total unik • ${mastery?.categoryDays ?? 0} hari',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: MamPetColors.cocoaMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 7),
                      GameProgressBar(
                        progress: total > 0 ? unique / total : 0,
                        fillColor: color,
                        height: 10,
                        shimmer: false,
                        reduceMotion: reduceMotion,
                      ),
                    ],
                  ),
                );

                if (!reduceMotion && idx < 8) {
                  tile = tile
                      .animate()
                      .fadeIn(delay: (idx * 35).ms, duration: 280.ms)
                      .slideY(begin: 0.08, end: 0, curve: Curves.easeOutBack);
                }
                return tile;
              },
            ),
        ],
      ),
    );
  }
}
