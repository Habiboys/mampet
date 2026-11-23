import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/domain/models.dart';
import '../../core/providers/app_providers.dart';
import '../../core/utils/formatters.dart';

class FoodPickResult {
  final MasterFood? masterFood;
  final CustomFood? customFood;

  const FoodPickResult.master(this.masterFood) : customFood = null;
  const FoodPickResult.custom(this.customFood) : masterFood = null;
}

Future<FoodPickResult?> showFoodSearchSheet(
  BuildContext context, {
  String? initialCategoryId,
}) {
  return showModalBottomSheet<FoodPickResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _FoodSearchSheetBody(initialCategoryId: initialCategoryId),
  );
}

class _FoodSearchSheetBody extends ConsumerStatefulWidget {
  final String? initialCategoryId;
  const _FoodSearchSheetBody({this.initialCategoryId});

  @override
  ConsumerState<_FoodSearchSheetBody> createState() => _FoodSearchSheetBodyState();
}

class _FoodSearchSheetBodyState extends ConsumerState<_FoodSearchSheetBody> {
  final TextEditingController _searchCtrl = TextEditingController();
  String? _selectedCategoryId;
  List<MasterFood> _results = [];
  List<MasterFood> _recent = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selectedCategoryId = widget.initialCategoryId;
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    final db = ref.read(databaseProvider);
    final recent = await db.getRecentMasterFoods(limit: 8);
    final res = await db.searchMasterFoods('', categoryId: _selectedCategoryId, limit: 80);
    if (!mounted) return;
    setState(() {
      _recent = recent;
      _results = res;
      _loading = false;
    });
  }

  Future<void> _runSearch() async {
    final db = ref.read(databaseProvider);
    final res = await db.searchMasterFoods(
      _searchCtrl.text,
      categoryId: _selectedCategoryId,
      limit: 80,
    );
    if (!mounted) return;
    setState(() => _results = res);
  }

  Future<void> _openAddCustomDialog(List<FoodCategory> categories) async {
    final nameCtrl = TextEditingController(text: _searchCtrl.text.trim());
    String catId = _selectedCategoryId ??
        (categories.isNotEmpty ? categories.first.id : 'nasi_serealia');

    final created = await showDialog<CustomFood>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Tambah Makanan Custom'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Makanan custom otomatis masuk ke koleksi FoodDex kategorimu, ikut menaikkan Grade & membuka telur monster, serta mendapat +5 XP penemuan pada kali pertama dicatat!',
                    style: TextStyle(fontSize: 12.5, color: MamPetColors.cocoaMuted),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nama hidangan',
                      hintText: 'Contoh: Nasi Goreng Bu Sari',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: catId,
                    decoration: const InputDecoration(labelText: 'Kategori'),
                    items: categories
                        .map(
                          (c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(c.name),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setLocal(() => catId = val);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Batal'),
                ),
                FilledButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    final cf = await ref.read(databaseProvider).createCustomFood(
                          name: name,
                          categoryId: catId,
                        );
                    if (ctx.mounted) Navigator.pop(ctx, cf);
                  },
                  child: const Text('Simpan & Pilih'),
                ),
              ],
            );
          },
        );
      },
    );

    if (created != null && mounted) {
      Navigator.pop(context, FoodPickResult.custom(created));
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final discoveredIds = ref.watch(discoveredFoodIdsProvider).valueOrNull ?? const {};
    final customFoods = ref.watch(customFoodsProvider).valueOrNull ?? const [];
    final catMap = {for (final c in categories) c.id: c};
    final query = _searchCtrl.text.trim();

    final matchingCustom = customFoods
        .where((cf) =>
            cf.mappedFoodId == null &&
            (_selectedCategoryId == null || cf.categoryId == _selectedCategoryId) &&
            (query.isEmpty ||
                cf.name.toLowerCase().contains(query.toLowerCase())))
        .toList();

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.86,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Pilih Makanan',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => _openAddCustomDialog(categories),
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                      label: const Text('Custom'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => _runSearch(),
                  decoration: InputDecoration(
                    hintText: 'Cari makanan atau alias (mis. nasgor, bakso, kopsu)...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: query.isNotEmpty
                        ? IconButton(
                            onPressed: () {
                              _searchCtrl.clear();
                              _runSearch();
                            },
                            icon: const Icon(Icons.close_rounded),
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),
          // Category filter bar
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    selected: _selectedCategoryId == null,
                    label: const Text('Semua'),
                    onSelected: (_) {
                      setState(() => _selectedCategoryId = null);
                      _runSearch();
                    },
                  ),
                ),
                ...categories.map((c) {
                  final sel = _selectedCategoryId == c.id;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      selected: sel,
                      label: Text(c.name),
                      onSelected: (_) {
                        setState(() => _selectedCategoryId = sel ? null : c.id);
                        _runSearch();
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      // Recent section when search is empty
                      if (query.isEmpty &&
                          _selectedCategoryId == null &&
                          _recent.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Baru Saja Dicatat',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: MamPetColors.cocoaMuted,
                            ),
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _recent
                              .map(
                                (f) => ActionChip(
                                  avatar: const Icon(Icons.history_rounded, size: 16),
                                  label: Text(f.canonicalName),
                                  onPressed: () =>
                                      Navigator.pop(context, FoodPickResult.master(f)),
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 16),
                      ],

                      if (matchingCustom.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.only(bottom: 6),
                          child: Text(
                            'Makanan Custom Kamu',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: MamPetColors.cocoaMuted,
                            ),
                          ),
                        ),
                        ...matchingCustom.map((cf) {
                          final cat = catMap[cf.categoryId];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                            leading: const CircleAvatar(
                              backgroundColor: MamPetColors.warmSurfaceAlt,
                              child: Icon(Icons.edit_note_rounded,
                                  color: MamPetColors.cocoaMuted),
                            ),
                            title: Text(
                              cf.name,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text('${cat?.name ?? cf.categoryId} • Custom'),
                            onTap: () =>
                                Navigator.pop(context, FoodPickResult.custom(cf)),
                          );
                        }),
                        const Divider(height: 20),
                      ],

                      const Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: Text(
                          'Katalog Master FoodDex',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: MamPetColors.cocoaMuted,
                          ),
                        ),
                      ),

                      if (_results.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.search_off_rounded,
                                  size: 38, color: MamPetColors.cocoaMuted),
                              const SizedBox(height: 8),
                              Text(
                                'Tidak ditemukan "$query" di katalog master',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Kamu tetap bisa mencatatnya sebagai Makanan Custom!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: MamPetColors.cocoaMuted,
                                ),
                              ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: () => _openAddCustomDialog(categories),
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Tambah Makanan Custom'),
                              ),
                            ],
                          ),
                        )
                      else
                        ..._results.map((food) {
                          final isDiscovered = discoveredIds.contains(food.id);
                          final cat = catMap[food.categoryId];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            leading: CircleAvatar(
                              backgroundColor: cat != null
                                  ? MamPetFormatters.parseHexColor(cat.colorHex)
                                      .withValues(alpha: 0.14)
                                  : MamPetColors.coralSoft,
                              child: Icon(
                                MamPetFormatters.categoryIcon(cat?.icon ?? ''),
                                size: 20,
                                color: cat != null
                                    ? MamPetFormatters.parseHexColor(cat.colorHex)
                                    : MamPetColors.coralPrimary,
                              ),
                            ),
                            title: Text(
                              food.canonicalName,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              food.aliases.isNotEmpty
                                  ? '${cat?.name ?? ''} • Alias: ${food.aliases.take(2).join(', ')}'
                                  : (cat?.name ?? ''),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: isDiscovered
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: MamPetColors.warmSurfaceAlt,
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                    child: const Text(
                                      'Ditemukan',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: MamPetColors.cocoaMuted,
                                      ),
                                    ),
                                  )
                                : Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: MamPetColors.sageAccent
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                    child: const Text(
                                      'Baru! +5 XP',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: MamPetColors.sageAccent,
                                      ),
                                    ),
                                  ),
                            onTap: () =>
                                Navigator.pop(context, FoodPickResult.master(food)),
                          );
                        }),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
