import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/domain/enums.dart';
import '../../core/domain/models.dart';
import '../../core/providers/app_providers.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/game_ui.dart';
import '../../core/widgets/grade_badge.dart';
import '../../core/widgets/monster_sprite.dart';
import '../../core/widgets/rarity_badge.dart';

class MonsterDexScreen extends ConsumerStatefulWidget {
  const MonsterDexScreen({super.key});

  @override
  ConsumerState<MonsterDexScreen> createState() => _MonsterDexScreenState();
}

class _MonsterDexScreenState extends ConsumerState<MonsterDexScreen> {
  String _statusFilter = 'all'; // all | unlocked | locked
  MonsterElement? _elementFilter;
  MonsterRarity? _rarityFilter; // only matches unlocked!
  String? _categoryFilter;
  EvolutionPhase? _phaseFilter;
  String _sortBy = 'number'; // number | alpha | level

  void _openFilterSheet(List<FoodCategory> categories) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            void updateParent(VoidCallback fn) {
              fn();
              setLocal(() {});
              setState(() {});
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Filter & Urutkan',
                            style: Theme.of(ctx).textTheme.titleLarge,
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => updateParent(() {
                              _statusFilter = 'all';
                              _elementFilter = null;
                              _rarityFilter = null;
                              _categoryFilter = null;
                              _phaseFilter = null;
                              _sortBy = 'number';
                            }),
                            child: const Text('Reset'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text('Urutkan',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Nomor (#001–#020)'),
                            selected: _sortBy == 'number',
                            onSelected: (_) =>
                                updateParent(() => _sortBy = 'number'),
                          ),
                          ChoiceChip(
                            label: const Text('Abjad'),
                            selected: _sortBy == 'alpha',
                            onSelected: (_) =>
                                updateParent(() => _sortBy = 'alpha'),
                          ),
                          ChoiceChip(
                            label: const Text('Level'),
                            selected: _sortBy == 'level',
                            onSelected: (_) =>
                                updateParent(() => _sortBy = 'level'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Text('Elemen',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: MonsterElement.values.map((el) {
                          final sel = _elementFilter == el;
                          return FilterChip(
                            selected: sel,
                            avatar: Icon(el.icon, size: 16, color: el.color),
                            label: Text(el.label),
                            onSelected: (_) => updateParent(
                              () => _elementFilter = sel ? null : el,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
                      const Text('Rarity (Hanya Monster Terbuka)',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: MonsterRarity.values.map((r) {
                          final sel = _rarityFilter == r;
                          return FilterChip(
                            selected: sel,
                            avatar:
                                Icon(r.shapeIcon, size: 15, color: r.textColor),
                            label: Text(r.displayName),
                            onSelected: (_) => updateParent(
                              () => _rarityFilter = sel ? null : r,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
                      const Text('Fase Evolusi (Hanya Terbuka)',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: EvolutionPhase.values.map((ph) {
                          final sel = _phaseFilter == ph;
                          return FilterChip(
                            selected: sel,
                            label: Text(ph.label),
                            onSelected: (_) => updateParent(
                              () => _phaseFilter = sel ? null : ph,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
                      const Text('Kategori Makanan',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String?>(
                        initialValue: _categoryFilter,
                        decoration: const InputDecoration(
                          hintText: 'Semua kategori',
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Semua Kategori'),
                          ),
                          ...categories.map(
                            (c) => DropdownMenuItem<String?>(
                              value: c.id,
                              child: Text(c.name),
                            ),
                          ),
                        ],
                        onChanged: (v) =>
                            updateParent(() => _categoryFilter = v),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: GameButton(
                          label: 'Terapkan Filter',
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final allMonsters = ref.watch(allMonstersProvider).valueOrNull ?? const [];
    final allEggs = ref.watch(allEggsProvider).valueOrNull ?? const [];
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final reduceMotion =
        ref.watch(appSettingsProvider).valueOrNull?.reduceMotion ?? false;

    final unlockedCount = allMonsters.where((m) => m.isUnlocked).length;
    final totalCount = allMonsters.isEmpty ? 20 : allMonsters.length;
    final pendingEggsCount = allEggs
        .where((e) =>
            e.status != EggStatus.hatched && e.status != EggStatus.archived)
        .length;
    final readyEgg =
        allEggs.where((e) => e.status == EggStatus.ready).firstOrNull;

    var list = allMonsters.where((m) {
      if (_statusFilter == 'unlocked' && !m.isUnlocked) return false;
      if (_statusFilter == 'locked' && m.isUnlocked) return false;
      if (_elementFilter != null && m.species.element != _elementFilter) {
        return false;
      }
      if (_rarityFilter != null) {
        if (!m.isUnlocked || m.species.rarity != _rarityFilter) return false;
      }
      if (_phaseFilter != null) {
        if (!m.isUnlocked || m.currentPhase != _phaseFilter) return false;
      }
      if (_categoryFilter != null && m.species.categoryId != _categoryFilter) {
        return false;
      }
      return true;
    }).toList();

    switch (_sortBy) {
      case 'alpha':
        list.sort((a, b) {
          final na =
              a.isUnlocked ? a.species.displayName : 'zzz_${a.species.id}';
          final nb =
              b.isUnlocked ? b.species.displayName : 'zzz_${b.species.id}';
          return na.compareTo(nb);
        });
        break;
      case 'level':
        list.sort((a, b) {
          final la = a.owned?.level ?? -1;
          final lb = b.owned?.level ?? -1;
          if (lb != la) return lb.compareTo(la);
          return a.species.sortOrder.compareTo(b.species.sortOrder);
        });
        break;
      default:
        list.sort((a, b) => a.species.sortOrder.compareTo(b.species.sortOrder));
    }

    final hasAdvancedFilters = _elementFilter != null ||
        _rarityFilter != null ||
        _categoryFilter != null ||
        _phaseFilter != null ||
        _sortBy != 'number';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('MonsterDex'),
            Text(
              '$unlockedCount/$totalCount dikoleksi',
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: MamPetColors.cocoaMuted,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GameButton(
              label: readyEgg != null
                  ? 'Tetaskan!'
                  : 'Nursery${pendingEggsCount > 0 ? ' ($pendingEggsCount)' : ''}',
              icon: Icons.egg_alt_rounded,
              color: readyEgg != null
                  ? MamPetColors.sageAccent
                  : MamPetColors.skyAccent,
              compact: true,
              height: 40,
              onPressed: () => context.push('/nursery'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: GameProgressBar(
              progress: totalCount > 0 ? unlockedCount / totalCount : 0,
              fillColor: const Color(0xFF8B5CF6),
              height: 12,
              reduceMotion: reduceMotion,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const Text('Semua'),
                          selected: _statusFilter == 'all',
                          onSelected: (_) =>
                              setState(() => _statusFilter = 'all'),
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: Text('Terbuka ($unlockedCount)'),
                          selected: _statusFilter == 'unlocked',
                          onSelected: (_) =>
                              setState(() => _statusFilter = 'unlocked'),
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label:
                              Text('Terkunci (${totalCount - unlockedCount})'),
                          selected: _statusFilter == 'locked',
                          onSelected: (_) =>
                              setState(() => _statusFilter = 'locked'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Filter lanjutan & urutkan',
                  onPressed: () => _openFilterSheet(categories),
                  icon: Badge(
                    isLabelVisible: hasAdvancedFilters,
                    child: const Icon(Icons.tune_rounded),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(
                    child: Text(
                      'Tidak ada monster yang cocok dengan filter ini.',
                      style: TextStyle(color: MamPetColors.cocoaMuted),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
                    itemCount: list.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 14,
                      childAspectRatio: 0.72,
                    ),
                    itemBuilder: (context, idx) {
                      final m = list[idx];
                      Widget card = _MonsterDexGridCard(
                        monster: m,
                        reduceMotion: reduceMotion,
                        onTap: () => context.push('/monster/${m.species.id}'),
                      );
                      if (!reduceMotion && idx < 8) {
                        card = card
                            .animate()
                            .fadeIn(delay: (idx * 35).ms, duration: 280.ms)
                            .scale(
                              begin: const Offset(0.94, 0.94),
                              end: const Offset(1, 1),
                              curve: Curves.easeOutBack,
                            );
                      }
                      return card;
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _MonsterDexGridCard extends StatelessWidget {
  final MonsterWithSpecies monster;
  final bool reduceMotion;
  final VoidCallback onTap;

  const _MonsterDexGridCard({
    required this.monster,
    required this.reduceMotion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final sp = monster.species;
    final unlocked = monster.isUnlocked;
    final hasEggPending = !unlocked &&
        monster.egg != null &&
        monster.egg!.status != EggStatus.hatched;

    return RarityCardFrame(
      rarity: unlocked ? sp.rarity : null,
      reduceMotion: reduceMotion,
      padding: const EdgeInsets.all(11),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                MamPetFormatters.formatSpeciesNumber(sp.id),
                style: TextStyle(
                  fontFamily: 'Fredoka',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: unlocked
                      ? sp.rarity.textColor
                      : MamPetColors.cocoaMuted,
                ),
              ),
              const Spacer(),
              if (unlocked && monster.owned!.isActive)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: MamPetColors.coralPrimary,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Text(
                    'AKTIF',
                    style: TextStyle(
                      fontFamily: 'Fredoka',
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else if (!unlocked)
                const Icon(
                  Icons.lock_rounded,
                  size: 16,
                  color: MamPetColors.cocoaMuted,
                )
              else
                GradeBadge(grade: monster.grade, compact: true),
            ],
          ),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (unlocked)
                  Container(
                    width: 102,
                    height: 102,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.9),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                MonsterSpriteWidget(
                  assetPath: unlocked ? monster.currentAsset : sp.assetBaby,
                  size: 112,
                  isLocked: !unlocked,
                  reduceMotion: reduceMotion,
                  semanticLabel: unlocked
                      ? '${sp.displayName} ${sp.rarity.displayName} Level ${monster.owned!.level}'
                      : 'Monster terkunci ${MamPetFormatters.formatSpeciesNumber(sp.id)}',
                ),
                if (!unlocked)
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: MamPetColors.silhouetteDark.withValues(alpha: 0.78),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.55),
                        width: 1.6,
                      ),
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            unlocked ? sp.displayName : '???',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Fredoka',
              fontWeight: FontWeight.w700,
              fontSize: 15.5,
            ),
          ),
          const SizedBox(height: 5),
          if (unlocked)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RarityBadge(rarity: sp.rarity, compact: true),
                const SizedBox(width: 5),
                Text(
                  'Lv ${monster.owned!.level}',
                  style: const TextStyle(
                    fontFamily: 'Fredoka',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
              decoration: BoxDecoration(
                color: hasEggPending
                    ? MamPetColors.coralSoft
                    : Colors.black.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                hasEggPending ? 'Telur di Nursery!' : 'Terkunci',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Fredoka',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: hasEggPending
                      ? MamPetColors.coralPrimary
                      : MamPetColors.cocoaMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
