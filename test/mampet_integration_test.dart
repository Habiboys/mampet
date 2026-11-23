import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mampet/core/clock/app_clock.dart';
import 'package:mampet/core/db/mampet_database.dart';
import 'package:mampet/core/db/seed_loader.dart';
import 'package:mampet/core/domain/enums.dart';
import 'package:mampet/core/domain/models.dart';
import 'package:mampet/core/files/photo_storage.dart';
import 'package:mampet/core/services/meal_share_service.dart';
import 'package:mampet/features/profile_backup/backup_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _TestPhotoStorage extends PhotoStorageService {
  final Directory dir;
  _TestPhotoStorage(this.dir);

  @override
  Future<Directory> getPhotosDirectory() async {
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
}

void main() {
  sqfliteFfiInit();

  late SeedDataBundle seed;
  late Directory tempDir;
  late FixedAppClock clock;
  late MamPetDatabase db;

  setUpAll(() {
    seed = SeedDataBundle(
      gameConfig: jsonDecode(
        File('assets/data/mampet_game_config_v1.json').readAsStringSync(),
      ) as Map<String, dynamic>,
      foodCatalog: jsonDecode(
        File('assets/data/food_catalog_seed_v1.json').readAsStringSync(),
      ) as Map<String, dynamic>,
    );
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mampet_test_');
    clock = FixedAppClock(DateTime(2026, 11, 22, 8, 30));
    db = MamPetDatabase(
      clock: clock,
      customFactory: databaseFactoryFfi,
      customPath: p.join(tempDir.path, 'test_mampet.db'),
    );
    await db.init(seed);
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('AC-01, AC-02, AC-03, AC-11: Onboarding, alias search, discovery & duplicate safety', () async {
    // AC-01: Select Foxili (04) starter
    await db.completeOnboarding(displayName: 'Budi', starterSpeciesId: '04');
    final active = await db.getActiveMonster();
    expect(active, isNotNull);
    expect(active!.species.displayName, 'Foxili');
    expect(active.owned!.level, 1);
    expect(active.owned!.xpTotal, 0);
    expect((await db.getAllEggs()).isEmpty, isTrue);

    // Alias lookup: "nasgor" -> Nasi Goreng
    final nasgorResults = await db.searchMasterFoods('nasgor');
    expect(nasgorResults.isNotEmpty, isTrue);
    final nasiGoreng = nasgorResults.first;
    expect(nasiGoreng.canonicalName, 'Nasi Goreng');

    // AC-02 & AC-11: Log Nasi Goreng without photo/price/location
    final res1 = await db.saveMealSession(
      occurredAt: clock.now(),
      mealType: MealType.breakfast,
      placeMode: PlaceMode.none,
      items: [
        MealItemDraft(
          foodId: nasiGoreng.id,
          displayName: nasiGoreng.canonicalName,
          categoryId: nasiGoreng.categoryId,
        ),
      ],
    );
    expect(res1.sessionXpAwarded, 10);
    expect(res1.discoveryXpAwarded, 5);
    expect(res1.newlyDiscoveredFoods.length, 1);
    expect((await db.getDiscoveredFoodIds()).length, 1);

    // AC-03: Log Nasi Goreng again for lunch -> history grows, FoodDex stays 1, discovery XP = 0
    clock.current = DateTime(2026, 11, 22, 12, 30);
    final res2 = await db.saveMealSession(
      occurredAt: clock.now(),
      mealType: MealType.lunch,
      placeMode: PlaceMode.home,
      items: [
        MealItemDraft(
          foodId: nasiGoreng.id,
          displayName: nasiGoreng.canonicalName,
          categoryId: nasiGoreng.categoryId,
        ),
      ],
    );
    expect(res2.sessionXpAwarded, 10);
    expect(res2.discoveryXpAwarded, 0);
    expect(res2.newlyDiscoveredFoods.isEmpty, isTrue);
    expect((await db.getDiscoveredFoodIds()).length, 1);
    expect((await db.getMealSessions()).length, 2);
  });

  test('AC-04: Single session with 5 new master foods caps discovery bonus at 3 (+15 XP)', () async {
    await db.completeOnboarding(displayName: 'Rani', starterSpeciesId: '06');
    final foods = (await db.getAllMasterFoods()).take(5).toList();

    final res = await db.saveMealSession(
      occurredAt: clock.now(),
      mealType: MealType.lunch,
      placeMode: PlaceMode.none,
      items: foods
          .map(
            (f) => MealItemDraft(
              foodId: f.id,
              displayName: f.canonicalName,
              categoryId: f.categoryId,
            ),
          )
          .toList(),
    );

    expect(res.sessionXpAwarded, 10);
    expect(res.newlyDiscoveredFoods.length, 5);
    expect(res.discoveryXpAwarded, 15); // Capped at 3 * 5 XP
    expect((await db.getDiscoveredFoodIds()).length, 5);

    // Second lunch on same day awards 0 session XP
    clock.current = clock.current.add(const Duration(minutes: 20));
    final resSecondLunch = await db.saveMealSession(
      occurredAt: clock.now(),
      mealType: MealType.lunch,
      placeMode: PlaceMode.none,
      items: [
        MealItemDraft(
          foodId: foods.first.id,
          displayName: foods.first.canonicalName,
          categoryId: foods.first.categoryId,
        ),
      ],
    );
    expect(resSecondLunch.sessionXpAwarded, 0);
    expect(resSecondLunch.discoveryXpAwarded, 0);
  });

  test('AC-06 & AC-07: Unlock egg after 3 unique + 2 days, incubate 3 sessions, hatch Baby', () async {
    await db.completeOnboarding(displayName: 'Dina', starterSpeciesId: '04');
    final allFoods = await db.getAllMasterFoods();
    final mieFoods = allFoods.where((f) => f.categoryId == 'mie_pasta').take(3).toList();

    // Day 1: log 2 unique Mie & Pasta dishes
    await db.saveMealSession(
      occurredAt: clock.now(),
      mealType: MealType.lunch,
      placeMode: PlaceMode.none,
      items: [
        MealItemDraft(foodId: mieFoods[0].id, displayName: mieFoods[0].canonicalName, categoryId: 'mie_pasta'),
        MealItemDraft(foodId: mieFoods[1].id, displayName: mieFoods[1].canonicalName, categoryId: 'mie_pasta'),
      ],
    );
    expect((await db.getAllEggs()).isEmpty, isTrue);

    // Day 2: log 3rd unique Mie & Pasta dish -> unlocks Zephlet (03, Common) egg!
    clock.current = DateTime(2026, 11, 23, 12, 0);
    final resUnlock = await db.saveMealSession(
      occurredAt: clock.now(),
      mealType: MealType.lunch,
      placeMode: PlaceMode.none,
      items: [
        MealItemDraft(foodId: mieFoods[2].id, displayName: mieFoods[2].canonicalName, categoryId: 'mie_pasta'),
      ],
    );
    expect(resUnlock.newlyGrantedEggs.length, 1);
    final egg = resUnlock.newlyGrantedEggs.first;
    expect(egg.speciesId, '03'); // Zephlet
    expect(egg.status, EggStatus.queued);

    // Start incubation
    clock.current = DateTime(2026, 11, 23, 12, 5);
    final started = await db.startEggIncubation(egg.id);
    expect(started, isTrue);

    // Session 1 after incubation (dinner Day 2) -> 1/3 incubating
    clock.current = DateTime(2026, 11, 23, 19, 0);
    await db.saveMealSession(
      occurredAt: clock.now(),
      mealType: MealType.dinner,
      placeMode: PlaceMode.none,
      items: [MealItemDraft(foodId: mieFoods[0].id, displayName: mieFoods[0].canonicalName, categoryId: 'mie_pasta')],
    );
    var activeEgg = await db.getActiveIncubatingEgg();
    expect(activeEgg!.hatchProgress, 1);
    expect(activeEgg.status, EggStatus.incubating);

    // Session 2 (breakfast Day 3) -> 2/3 CRACKED!
    clock.current = DateTime(2026, 11, 24, 8, 0);
    await db.saveMealSession(
      occurredAt: clock.now(),
      mealType: MealType.breakfast,
      placeMode: PlaceMode.none,
      items: [MealItemDraft(foodId: mieFoods[0].id, displayName: mieFoods[0].canonicalName, categoryId: 'mie_pasta')],
    );
    activeEgg = await db.getActiveIncubatingEgg();
    expect(activeEgg!.hatchProgress, 2);
    expect(activeEgg.status, EggStatus.cracked);

    // Session 3 (lunch Day 3) -> 3/3 READY!
    clock.current = DateTime(2026, 11, 24, 12, 30);
    await db.saveMealSession(
      occurredAt: clock.now(),
      mealType: MealType.lunch,
      placeMode: PlaceMode.none,
      items: [MealItemDraft(foodId: mieFoods[0].id, displayName: mieFoods[0].canonicalName, categoryId: 'mie_pasta')],
    );
    activeEgg = await db.getActiveIncubatingEgg();
    expect(activeEgg!.hatchProgress, 3);
    expect(activeEgg.status, EggStatus.ready);

    // Hatch egg -> Zephlet unlocked!
    final hatched = await db.hatchEgg(activeEgg.id);
    expect(hatched, isNotNull);
    expect(hatched!.species.displayName, 'Zephlet');
    expect(hatched.monster.level, 1);

    final allMonsters = await db.getAllMonstersWithStatus();
    expect(allMonsters.where((m) => m.isUnlocked).length, 2); // Foxili + Zephlet
  });

  test('AC-13: Delete & retry session never awards double XP or double discovery', () async {
    await db.completeOnboarding(displayName: 'Eko', starterSpeciesId: '07');
    final food = (await db.getAllMasterFoods()).first;

    final res1 = await db.saveMealSession(
      occurredAt: clock.now(),
      mealType: MealType.breakfast,
      placeMode: PlaceMode.none,
      items: [MealItemDraft(foodId: food.id, displayName: food.canonicalName, categoryId: food.categoryId)],
    );
    expect((await db.getActiveMonster())!.owned!.xpTotal, 15); // 10 session + 5 disc

    // Delete session -> XP reverts to 0 and discovery removed
    await db.deleteMealSession(res1.sessionId);
    expect((await db.getActiveMonster())!.owned!.xpTotal, 0);
    expect((await db.getDiscoveredFoodIds()).isEmpty, isTrue);

    // Retry same breakfast + same food -> XP is strictly 15, NOT 30!
    await db.saveMealSession(
      occurredAt: clock.now().add(const Duration(minutes: 5)),
      mealType: MealType.breakfast,
      placeMode: PlaceMode.none,
      items: [MealItemDraft(foodId: food.id, displayName: food.canonicalName, categoryId: food.categoryId)],
    );
    expect((await db.getActiveMonster())!.owned!.xpTotal, 15);
    expect((await db.getDiscoveredFoodIds()).length, 1);
  });

  test('Backdated session saves to history without awarding today XP', () async {
    await db.completeOnboarding(displayName: 'Siti', starterSpeciesId: '04');
    final food = (await db.getAllMasterFoods()).first;

    final yesterday = clock.now().subtract(const Duration(days: 1));
    final res = await db.saveMealSession(
      occurredAt: yesterday,
      mealType: MealType.dinner,
      placeMode: PlaceMode.none,
      items: [MealItemDraft(foodId: food.id, displayName: food.canonicalName, categoryId: food.categoryId)],
    );
    expect(res.wasBackdated, isTrue);
    expect(res.sessionXpAwarded, 0);
    expect(res.discoveryXpAwarded, 0);
    expect((await db.getMealSessions()).length, 1);
  });

  test('AC-12: Export ZIP backup, reset data, restore ZIP -> identical state', () async {
    await db.completeOnboarding(displayName: 'Tari', starterSpeciesId: '06');
    final food = (await db.getAllMasterFoods()).first;
    final photoDir = Directory(p.join(tempDir.path, 'photos'));
    await photoDir.create(recursive: true);
    final fakePhoto = File(p.join(photoDir.path, 'meal_test.jpg'));
    await fakePhoto.writeAsBytes([1, 2, 3, 4, 5, 6, 7, 8]);

    await db.saveMealSession(
      occurredAt: clock.now(),
      mealType: MealType.breakfast,
      placeMode: PlaceMode.none,
      items: [
        MealItemDraft(
          foodId: food.id,
          displayName: food.canonicalName,
          categoryId: food.categoryId,
          priceMinor: 22000,
          photoPath: fakePhoto.path,
        ),
      ],
    );

    final photoStorage = _TestPhotoStorage(photoDir);
    final backupSvc = BackupService(db: db, photoStorage: photoStorage, seed: seed);

    final exported = await backupSvc.exportBackupZip(targetDirectory: tempDir);
    expect(exported.zipFile.existsSync(), isTrue);
    expect(exported.photoCount, 1);

    // Wipe user data & photo
    await db.resetAllUserData();
    await fakePhoto.delete();
    expect((await db.getMealSessions()).isEmpty, isTrue);
    expect((await db.getActiveMonster()), isNull);

    // Restore from ZIP
    final restored = await backupSvc.restoreFromBackupZip(exported.zipFile);
    expect(restored.restoredPhotos, 1);
    expect((await db.getProfile()).displayName, 'Tari');
    expect((await db.getMealSessions()).length, 1);
    expect((await db.getActiveMonster())!.owned!.xpTotal, 15);
    expect(fakePhoto.existsSync(), isTrue);
  });

  test('Standalone custom food enters FoodDex, awards discovery XP once, and counts toward category mastery', () async {
    await db.completeOnboarding(displayName: 'Andi', starterSpeciesId: '04');

    // Create custom dish without mapping to any master item
    final custom1 = await db.createCustomFood(
      name: 'Nasi Telur Sambal Bawang',
      categoryId: 'nasi_serealia',
    );
    // Deduplication check on identical normalized name
    final customDup = await db.createCustomFood(
      name: '  nasi  telur sambal bawang! ',
      categoryId: 'nasi_serealia',
    );
    expect(customDup.id, custom1.id);

    // First log -> +10 session XP + 5 custom discovery XP = 15 XP & appears in FoodDex
    final res1 = await db.saveMealSession(
      occurredAt: clock.now(),
      mealType: MealType.breakfast,
      placeMode: PlaceMode.none,
      items: [
        MealItemDraft(
          customFoodId: custom1.id,
          displayName: custom1.name,
          categoryId: custom1.categoryId,
          isCustom: true,
        ),
      ],
    );
    expect(res1.sessionXpAwarded, 10);
    expect(res1.discoveryXpAwarded, 5);
    expect(res1.newlyDiscoveredFoods.length, 1);

    final discCustom = await db.getDiscoveredCustomFoods();
    expect(discCustom.length, 1);
    expect(discCustom.first.name, 'Nasi Telur Sambal Bawang');

    final masteries = await db.getAllCategoryMasteries();
    expect(masteries['nasi_serealia']!.uniqueDiscoveredFoods, 1);
    expect(masteries['nasi_serealia']!.categoryDays, 1);

    // Second log of same custom food -> no duplicate discovery XP
    clock.current = DateTime(2026, 11, 22, 13, 0);
    final res2 = await db.saveMealSession(
      occurredAt: clock.now(),
      mealType: MealType.lunch,
      placeMode: PlaceMode.none,
      items: [
        MealItemDraft(
          customFoodId: custom1.id,
          displayName: custom1.name,
          categoryId: custom1.categoryId,
          isCustom: true,
        ),
      ],
    );
    expect(res2.sessionXpAwarded, 10);
    expect(res2.discoveryXpAwarded, 0);
    expect((await db.getDiscoveredCustomFoods()).length, 1);
  });

  test('MealShareService formats food, notes, place & Google Maps coordinates URL cleanly', () {
    final place = PlaceModel(
      id: 'p1',
      profileId: 'default_profile',
      displayName: 'Warung Nasi Telur Mbak Sari',
      lat: -6.2088,
      lng: 106.8456,
      address: 'Jl. Kenangan No. 5',
      createdAt: DateTime(2026, 11, 23, 12, 0),
    );
    final item = MealItemRecord(
      id: 'i1',
      sessionId: 's1',
      foodId: 'nasi_serealia_051',
      displayName: 'Nasi Telur',
      categoryId: 'nasi_serealia',
      priceMinor: 18000,
      quantity: 1,
      rating: 5,
      description: 'Telurnya garing banget, sambal koreknya juara!',
      createdAt: DateTime(2026, 11, 23, 12, 30),
    );
    final session = MealSessionRecord(
      id: 's1',
      profileId: 'default_profile',
      occurredAt: DateTime(2026, 11, 23, 12, 30),
      localDate: '2026-11-23',
      mealType: MealType.lunch,
      placeId: place.id,
      placeMode: PlaceMode.place,
      place: place,
      isRewardEligible: true,
      createdAt: DateTime(2026, 11, 23, 12, 30),
      items: [item],
    );

    final caption = MealShareService.buildCaption(
      session: session,
      focusItem: item,
    );
    expect(caption, contains('Nasi Telur'));
    expect(caption, contains('Warung Nasi Telur Mbak Sari'));
    expect(caption, contains('https://www.google.com/maps/search/?api=1&query=-6.208800,106.845600'));
    expect(caption, contains('Telurnya garing banget'));
    expect(caption, contains('18.000'));
  });
}
