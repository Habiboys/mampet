import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/domain/models.dart';
import '../../core/providers/app_providers.dart';
import '../../core/utils/formatters.dart';

class FoodDetailScreen extends ConsumerWidget {
  final String foodId;
  const FoodDetailScreen({super.key, required this.foodId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    ref.watch(dbRevisionProvider);
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final discoveredIds = ref.watch(discoveredFoodIdsProvider).valueOrNull ?? const {};

    return FutureBuilder<(MasterFood?, FoodPriceStats, List<MealSessionRecord>)>(
      future: Future.wait([
        db.getMasterFoodById(foodId),
        db.getFoodPriceStats(foodId),
        db.getSessionsForFood(foodId),
      ]).then((res) => (
            res[0] as MasterFood?,
            res[1] as FoodPriceStats,
            res[2] as List<MealSessionRecord>,
          )),
      builder: (context, snap) {
        if (!snap.hasData) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final (food, priceStats, sessions) = snap.data!;
        if (food == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Hidangan')),
            body: const Center(child: Text('Hidangan tidak ditemukan.')),
          );
        }

        final isDiscovered = discoveredIds.contains(food.id);
        final cat = categories.where((c) => c.id == food.categoryId).firstOrNull;

        return Scaffold(
          appBar: AppBar(title: Text(food.canonicalName)),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: isDiscovered
                                  ? MamPetColors.sageAccent.withValues(alpha: 0.16)
                                  : MamPetColors.warmSurfaceAlt,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isDiscovered
                                      ? Icons.check_circle_rounded
                                      : Icons.explore_outlined,
                                  size: 15,
                                  color: isDiscovered
                                      ? MamPetColors.sageAccent
                                      : MamPetColors.cocoaMuted,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  isDiscovered ? 'Sudah Ditemukan' : 'Belum Ditemukan',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: isDiscovered
                                        ? MamPetColors.sageAccent
                                        : MamPetColors.cocoaMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          if (cat != null)
                            Chip(
                              label: Text(cat.name,
                                  style: const TextStyle(fontSize: 11.5)),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        food.canonicalName,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      if (food.originRegion.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Asal / Ragam: ${food.originRegion}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: MamPetColors.coralPrimary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Text(
                        food.description,
                        style: const TextStyle(fontSize: 14, height: 1.5),
                      ),
                      if (food.aliases.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: food.aliases
                              .map(
                                (a) => Chip(
                                  label: Text('Alias: $a',
                                      style: const TextStyle(fontSize: 11.5)),
                                  visualDensity: VisualDensity.compact,
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Personal price statistics
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Statistik Pribadi & Harga',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _statTile('Total Log', '${priceStats.totalLogs}×'),
                          _statTile(
                            'Median Harga',
                            priceStats.medianPriceMinor != null
                                ? MamPetFormatters.formatRupiah(
                                    priceStats.medianPriceMinor)
                                : '-',
                          ),
                          _statTile(
                            'Rentang',
                            priceStats.minPriceMinor != null
                                ? '${MamPetFormatters.formatRupiah(priceStats.minPriceMinor)}\n– ${MamPetFormatters.formatRupiah(priceStats.maxPriceMinor)}'
                                : '-',
                          ),
                        ],
                      ),
                      if (priceStats.totalLogs > priceStats.pricedLogs &&
                          priceStats.pricedLogs > 0)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            '* Sebagian catatan tanpa harga tidak dihitung ke statistik nominal.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: MamPetColors.cocoaMuted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.push('/log/new?foodId=${food.id}'),
                icon: const Icon(Icons.add_rounded),
                label: Text('Catat ${food.canonicalName} Sekarang'),
              ),

              const SizedBox(height: 20),
              Text(
                'Riwayat Catatan (${sessions.length})',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 8),
              if (sessions.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'Kamu belum pernah mencatat hidangan ini.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: MamPetColors.cocoaMuted),
                    ),
                  ),
                )
              else
                ...sessions.map((s) {
                  final matchingItems =
                      s.items.where((i) => i.foodId == food.id).toList();
                  final price = matchingItems.firstOrNull?.priceMinor;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(
                        '${s.mealType.label} • ${MamPetFormatters.formatDateTime(s.occurredAt)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13.5),
                      ),
                      subtitle: Text(
                        '${s.placeDisplayLabel} • ${MamPetFormatters.formatRupiah(price)}',
                      ),
                      trailing: const Icon(Icons.edit_outlined, size: 18),
                      onTap: () => context.push('/log/edit/${s.id}'),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Widget _statTile(String label, String value) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: MamPetColors.warmSurfaceAlt,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                color: MamPetColors.cocoaMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
