import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mampet/core/domain/enums.dart';
import 'package:mampet/core/domain/game_rules.dart';
import 'package:mampet/core/utils/text_normalizer.dart';

void main() {
  group('GameRules XP, Level, Evolution & Grade', () {
    test('Matches PRD Section 6.2 cumulative XP table and Level 30 cap (AC-08)', () {
      expect(GameRules.cumulativeXpForLevel(1), 0);
      expect(GameRules.cumulativeXpForLevel(5), 78);
      expect(GameRules.cumulativeXpForLevel(10), 243);
      expect(GameRules.cumulativeXpForLevel(15), 483);
      expect(GameRules.cumulativeXpForLevel(20), 798);
      expect(GameRules.cumulativeXpForLevel(25), 1188);
      expect(GameRules.cumulativeXpForLevel(30), 1653);

      expect(GameRules.levelFromTotalXp(0), 1);
      expect(GameRules.levelFromTotalXp(242), 9);
      expect(GameRules.levelFromTotalXp(243), 10);
      expect(GameRules.levelFromTotalXp(1187), 24);
      expect(GameRules.levelFromTotalXp(1188), 25);
      expect(GameRules.levelFromTotalXp(1653), 30);
      expect(GameRules.levelFromTotalXp(99999), 30); // Capped at 30

      expect(GameRules.phaseForLevel(1), EvolutionPhase.baby);
      expect(GameRules.phaseForLevel(9), EvolutionPhase.baby);
      expect(GameRules.phaseForLevel(10), EvolutionPhase.young);
      expect(GameRules.phaseForLevel(24), EvolutionPhase.young);
      expect(GameRules.phaseForLevel(25), EvolutionPhase.adult);
      expect(GameRules.phaseForLevel(30), EvolutionPhase.adult);
    });

    test('Grade rules support both place path and home/days path (AC-09)', () {
      expect(
        GameRules.calculateGrade(uniqueFoods: 0, distinctPlaces: 0, categoryDays: 0),
        CategoryGrade.c,
      );
      expect(
        GameRules.calculateGrade(uniqueFoods: 3, distinctPlaces: 0, categoryDays: 1),
        CategoryGrade.b,
      );
      expect(
        GameRules.calculateGrade(uniqueFoods: 6, distinctPlaces: 0, categoryDays: 1),
        CategoryGrade.a,
      );
      // 10 unique but neither 2 places nor 5 days -> remains Grade A
      expect(
        GameRules.calculateGrade(uniqueFoods: 10, distinctPlaces: 1, categoryDays: 4),
        CategoryGrade.a,
      );
      // 10 unique + 2 places -> Grade S
      expect(
        GameRules.calculateGrade(uniqueFoods: 10, distinctPlaces: 2, categoryDays: 1),
        CategoryGrade.s,
      );
      // 10 unique + 5 days (home user!) -> Grade S
      expect(
        GameRules.calculateGrade(uniqueFoods: 10, distinctPlaces: 0, categoryDays: 5),
        CategoryGrade.s,
      );
      // 18 unique + 4 places -> Grade SS
      expect(
        GameRules.calculateGrade(uniqueFoods: 18, distinctPlaces: 4, categoryDays: 2),
        CategoryGrade.ss,
      );
      // 18 unique + 10 days (home user!) -> Grade SS
      expect(
        GameRules.calculateGrade(uniqueFoods: 18, distinctPlaces: 0, categoryDays: 10),
        CategoryGrade.ss,
      );
    });

    test('Egg status transitions 0 -> 1 -> 2(cracked) -> 3(ready)', () {
      expect(
        GameRules.eggStatusForProgress(progress: 0, isIncubating: false),
        EggStatus.queued,
      );
      expect(
        GameRules.eggStatusForProgress(progress: 0, isIncubating: true),
        EggStatus.incubating,
      );
      expect(
        GameRules.eggStatusForProgress(progress: 1, isIncubating: true),
        EggStatus.incubating,
      );
      expect(
        GameRules.eggStatusForProgress(progress: 2, isIncubating: true),
        EggStatus.cracked,
      );
      expect(
        GameRules.eggStatusForProgress(progress: 3, isIncubating: true),
        EggStatus.ready,
      );
    });

    test('Text normalization handles case, extra spaces, punctuation & diacritics', () {
      expect(normalizeFoodText('  Nasi   Goreng! '), 'nasi goreng');
      expect(normalizeFoodText('Gado-Gado'), 'gado gado');
      expect(normalizeFoodText('Café  Latte'), 'cafe latte');
    });
  });

  group('Seed JSON & 72 Bundled Assets Integrity', () {
    test('All 20 species × 3 phases (60 PNG) and 6 elements × 2 states (12 PNG) exist on disk', () {
      final config = jsonDecode(
        File('assets/data/mampet_game_config_v1.json').readAsStringSync(),
      ) as Map<String, dynamic>;

      final species = config['species'] as List<dynamic>;
      expect(species.length, 20);

      int common = 0, uncommon = 0, rare = 0;
      for (final raw in species) {
        final sp = raw as Map<String, dynamic>;
        expect(File(sp['asset_baby'] as String).existsSync(), isTrue,
            reason: 'Missing ${sp['asset_baby']}');
        expect(File(sp['asset_young'] as String).existsSync(), isTrue,
            reason: 'Missing ${sp['asset_young']}');
        expect(File(sp['asset_adult'] as String).existsSync(), isTrue,
            reason: 'Missing ${sp['asset_adult']}');
        if (sp['rarity_id'] == 'common') common++;
        if (sp['rarity_id'] == 'uncommon') uncommon++;
        if (sp['rarity_id'] == 'rare') rare++;
      }
      expect(common, 12);
      expect(uncommon, 5);
      expect(rare, 3);

      final elements = config['elements'] as List<dynamic>;
      expect(elements.length, 6);
      for (final raw in elements) {
        final el = raw as Map<String, dynamic>;
        expect(File(el['intact_asset'] as String).existsSync(), isTrue);
        expect(File(el['cracked_asset'] as String).existsSync(), isTrue);
      }
    });

    test('Food catalog has 12 categories and 51 curated dishes per category (612 total)', () {
      final catalog = jsonDecode(
        File('assets/data/food_catalog_seed_v1.json').readAsStringSync(),
      ) as Map<String, dynamic>;

      final categories = catalog['categories'] as List<dynamic>;
      final foods = catalog['foods'] as List<dynamic>;

      expect(categories.length, 12);
      expect(foods.length, 612);

      final countByCat = <String, int>{};
      for (final raw in foods) {
        final catId = (raw as Map<String, dynamic>)['category_id'] as String;
        countByCat[catId] = (countByCat[catId] ?? 0) + 1;
      }
      for (final rawCat in categories) {
        final id = (rawCat as Map<String, dynamic>)['id'] as String;
        expect(countByCat[id] ?? 0, 51,
            reason: 'Category $id must have 51 curated dishes');
      }
    });
  });
}
