import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mampet/app/bootstrap.dart';
import 'package:mampet/core/clock/app_clock.dart';
import 'package:mampet/core/db/mampet_database.dart';
import 'package:mampet/core/db/seed_loader.dart';
import 'package:mampet/core/domain/models.dart';
import 'package:mampet/core/providers/app_providers.dart';
import 'package:mampet/features/monster_dex/monster_dex_screen.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late SeedDataBundle seed;
  late Directory tempDir;
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
    tempDir = await Directory.systemTemp.createTemp('mampet_widget_');
    db = MamPetDatabase(
      clock: FixedAppClock(DateTime(2026, 11, 22, 10, 0)),
      customFactory: databaseFactoryFfi,
      customPath: p.join(tempDir.path, 'widget_mampet.db'),
    );
    await db.init(seed);
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('Splash screen displays official MamPet logo then navigates to onboarding', (tester) async {
    final loaded = await tester.runAsync(() async => (
          monsters: await db.getAllMonstersWithStatus(),
          cats: await db.getCategories(),
        ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          seedBundleProvider.overrideWithValue(seed),
          databaseProvider.overrideWithValue(db),
          appSettingsProvider.overrideWith(
            (_) async => const AppSettingsModel(reduceMotion: true),
          ),
          allMonstersProvider.overrideWith((_) async => loaded!.monsters),
          categoriesProvider.overrideWith((_) async => loaded!.cats),
        ],
        child: const MamPetApp(onboardingDone: false, showSplash: true),
      ),
    );
    await tester.pump();
    expect(find.text('MamPet'), findsOneWidget);
    expect(find.text('Jurnal Kuliner & Koleksi Monster'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('Lewati'), findsOneWidget);
  });

  testWidgets('AC-01: Fresh install shows onboarding & 3 official starters', (tester) async {
    final loaded = await tester.runAsync(() async => (
          monsters: await db.getAllMonstersWithStatus(),
          cats: await db.getCategories(),
        ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          seedBundleProvider.overrideWithValue(seed),
          databaseProvider.overrideWithValue(db),
          appSettingsProvider.overrideWith(
            (_) async => const AppSettingsModel(reduceMotion: true),
          ),
          allMonstersProvider.overrideWith((_) async => loaded!.monsters),
          categoriesProvider.overrideWith((_) async => loaded!.cats),
        ],
        child: const MamPetApp(onboardingDone: false, showSplash: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MamPet'), findsOneWidget);
    await tester.tap(find.text('Lewati'));
    await tester.pumpAndSettle();

    expect(find.text('Foxili'), findsOneWidget);
    expect(find.text('Sproutle'), findsOneWidget);
    expect(find.text('Axolumi'), findsOneWidget);
  });

  testWidgets('AC-05 & AC-14: MonsterDex renders locked silhouettes as ??? and unlocked starter', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final loaded = await tester.runAsync(() async {
      await db.completeOnboarding(displayName: 'Test', starterSpeciesId: '04');
      await db.setSetting('reduce_motion', 'true');
      return (
        monsters: await db.getAllMonstersWithStatus(),
        eggs: await db.getAllEggs(),
        cats: await db.getCategories(),
        settings: await db.getSettings(),
      );
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          seedBundleProvider.overrideWithValue(seed),
          databaseProvider.overrideWithValue(db),
          allMonstersProvider.overrideWith((_) async => loaded!.monsters),
          allEggsProvider.overrideWith((_) async => loaded!.eggs),
          categoriesProvider.overrideWith((_) async => loaded!.cats),
          appSettingsProvider.overrideWith((_) async => loaded!.settings),
        ],
        child: const MaterialApp(home: MonsterDexScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1/20 dikoleksi'), findsOneWidget);
    expect(find.text('???'), findsWidgets);
    expect(find.byIcon(Icons.lock_rounded), findsWidgets);
    expect(find.text('Foxili'), findsOneWidget);
    expect(find.text('COMMON'), findsOneWidget);
  });
}
