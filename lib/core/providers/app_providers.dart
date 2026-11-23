import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/monsters/animation/monster_animation_state.dart';
import '../../features/profile_backup/backup_service.dart';
import '../db/mampet_database.dart';
import '../db/seed_loader.dart';
import '../domain/models.dart';
import '../files/photo_storage.dart';

final seedBundleProvider = Provider<SeedDataBundle>((ref) {
  throw UnimplementedError('seedBundleProvider must be overridden at bootstrap');
});

final databaseProvider = Provider<MamPetDatabase>((ref) {
  throw UnimplementedError('databaseProvider must be overridden at bootstrap');
});

final photoStorageProvider = Provider<PhotoStorageService>((ref) {
  return PhotoStorageService();
});

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(
    db: ref.watch(databaseProvider),
    photoStorage: ref.watch(photoStorageProvider),
    seed: ref.watch(seedBundleProvider),
  );
});

/// Emits a monotonically increasing tick every time local DB data mutates.
final dbRevisionProvider = StreamProvider<int>((ref) async* {
  final db = ref.watch(databaseProvider);
  int rev = 0;
  yield rev;
  await for (final _ in db.onDataChanged) {
    rev++;
    yield rev;
  }
});

final profileProvider = FutureProvider<UserProfile>((ref) async {
  ref.watch(dbRevisionProvider);
  return ref.watch(databaseProvider).getProfile();
});

final appSettingsProvider = FutureProvider<AppSettingsModel>((ref) async {
  ref.watch(dbRevisionProvider);
  return ref.watch(databaseProvider).getSettings();
});

final categoriesProvider = FutureProvider<List<FoodCategory>>((ref) async {
  ref.watch(dbRevisionProvider);
  return ref.watch(databaseProvider).getCategories();
});

final allMasterFoodsProvider = FutureProvider<List<MasterFood>>((ref) async {
  ref.watch(dbRevisionProvider);
  return ref.watch(databaseProvider).getAllMasterFoods();
});

final discoveredFoodIdsProvider = FutureProvider<Set<String>>((ref) async {
  ref.watch(dbRevisionProvider);
  return ref.watch(databaseProvider).getDiscoveredFoodIds();
});

final customFoodsProvider = FutureProvider<List<CustomFood>>((ref) async {
  ref.watch(dbRevisionProvider);
  return ref.watch(databaseProvider).getCustomFoods();
});

final discoveredCustomFoodsProvider =
    FutureProvider<List<CustomFood>>((ref) async {
  ref.watch(dbRevisionProvider);
  return ref.watch(databaseProvider).getDiscoveredCustomFoods();
});

final categoryMasteriesProvider =
    FutureProvider<Map<String, CategoryMastery>>((ref) async {
  ref.watch(dbRevisionProvider);
  return ref.watch(databaseProvider).getAllCategoryMasteries();
});

final allMonstersProvider = FutureProvider<List<MonsterWithSpecies>>((ref) async {
  ref.watch(dbRevisionProvider);
  return ref.watch(databaseProvider).getAllMonstersWithStatus();
});

final activeMonsterProvider = FutureProvider<MonsterWithSpecies?>((ref) async {
  ref.watch(dbRevisionProvider);
  return ref.watch(databaseProvider).getActiveMonster();
});

final allEggsProvider = FutureProvider<List<MonsterEgg>>((ref) async {
  ref.watch(dbRevisionProvider);
  return ref.watch(databaseProvider).getAllEggs();
});

final activeEggProvider = FutureProvider<MonsterEgg?>((ref) async {
  ref.watch(dbRevisionProvider);
  return ref.watch(databaseProvider).getActiveIncubatingEgg();
});

final dailyXpStatusProvider = FutureProvider<DailyXpStatus>((ref) async {
  ref.watch(dbRevisionProvider);
  return ref.watch(databaseProvider).getDailyXpStatus();
});

final recentMealSessionsProvider =
    FutureProvider<List<MealSessionRecord>>((ref) async {
  ref.watch(dbRevisionProvider);
  return ref.watch(databaseProvider).getMealSessions(limit: 20);
});

final allMealSessionsProvider =
    FutureProvider<List<MealSessionRecord>>((ref) async {
  ref.watch(dbRevisionProvider);
  return ref.watch(databaseProvider).getMealSessions();
});

final placesProvider = FutureProvider<List<PlaceModel>>((ref) async {
  ref.watch(dbRevisionProvider);
  return ref.watch(databaseProvider).getPlaces();
});

final personalStatsProvider = FutureProvider<UserPersonalStats>((ref) async {
  ref.watch(dbRevisionProvider);
  return ref.watch(databaseProvider).getPersonalStats();
});

/// Queues a one-shot gameplay reaction animation (`eat`, `happy`, `evolve`) for
/// the active monster on the Home screen after logging a meal or gaining XP.
final pendingMonsterReactionProvider =
    StateProvider<MonsterAnimation?>((ref) => null);
