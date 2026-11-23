import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/domain/models.dart';
import '../../core/providers/app_providers.dart';
import '../meal_log/food_search_sheet.dart';

class CustomFoodsScreen extends ConsumerWidget {
  const CustomFoodsScreen({super.key});

  Future<void> _mapToMaster(
    BuildContext context,
    WidgetRef ref,
    CustomFood cf,
  ) async {
    final picked = await showFoodSearchSheet(
      context,
      initialCategoryId: cf.categoryId,
    );
    if (picked?.masterFood == null || !context.mounted) return;
    final master = picked!.masterFood!;

    final outcome = await ref.read(databaseProvider).mapCustomFoodToMaster(
          customFoodId: cf.id,
          masterFoodId: master.id,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          outcome.newlyDiscovered
              ? '"${cf.name}" dipetakan ke ${master.canonicalName}! FoodDex +1${outcome.bonusXp > 0 ? ' (+${outcome.bonusXp} XP)' : ''}.'
              : '"${cf.name}" dipetakan ke ${master.canonicalName}.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customFoods = ref.watch(customFoodsProvider).valueOrNull ?? const [];
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final allMaster = ref.watch(allMasterFoodsProvider).valueOrNull ?? const [];
    final catMap = {for (final c in categories) c.id: c.name};
    final masterMap = {for (final f in allMaster) f.id: f.canonicalName};

    return Scaffold(
      appBar: AppBar(title: const Text('Makanan Custom')),
      body: customFoods.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit_note_rounded,
                        size: 48, color: MamPetColors.cocoaMuted),
                    SizedBox(height: 12),
                    Text(
                      'Belum ada makanan custom',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Jika hidangan yang kamu makan belum ada di katalog master, kamu bisa membuatnya saat mencatat sesi makan.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: MamPetColors.cocoaMuted),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: customFoods.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, idx) {
                final cf = customFoods[idx];
                final mappedName =
                    cf.mappedFoodId != null ? masterMap[cf.mappedFoodId!] : null;

                return Card(
                  child: ListTile(
                    title: Text(cf.name,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(
                      mappedName != null
                          ? '${catMap[cf.categoryId] ?? ''} • Digabung ke $mappedName'
                          : '${catMap[cf.categoryId] ?? ''} • Aktif di FoodDex (opsional: gabung ke master)',
                    ),
                    trailing: mappedName != null
                        ? const Icon(Icons.check_circle_rounded,
                            color: MamPetColors.sageAccent)
                        : OutlinedButton(
                            onPressed: () => _mapToMaster(context, ref, cf),
                            child: const Text('Gabung'),
                          ),
                  ),
                );
              },
            ),
    );
  }
}
