import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../clock/app_clock.dart';
import '../domain/enums.dart';
import '../domain/game_rules.dart';
import '../domain/models.dart';
import '../utils/text_normalizer.dart';
import 'seed_loader.dart';

class MamPetDatabase {
  static const int currentSchemaVersion = 1;
  static const String defaultProfileId = 'local_default_profile';
  static const String dbFileName = 'mampet_v1.db';
  static const _uuid = Uuid();

  final AppClock clock;
  final DatabaseFactory? customFactory;
  final String? customPath;

  Database? _db;
  String? _resolvedPath;

  final StreamController<void> _changes = StreamController<void>.broadcast();
  Stream<void> get onDataChanged => _changes.stream;

  MamPetDatabase({
    this.clock = const SystemAppClock(),
    this.customFactory,
    this.customPath,
  });

  String? get databasePath => _resolvedPath;

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    throw StateError('MamPetDatabase has not been initialized yet.');
  }

  Future<void> init(SeedDataBundle seed) async {
    final factory = customFactory ?? databaseFactory;
    final dbPath = customPath ?? p.join(await factory.getDatabasesPath(), dbFileName);
    _resolvedPath = dbPath;

    _db = await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: currentSchemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await _createSchema(db, version);
        },
      ),
    );

    await _ensureSeeded(seed);
  }

  Future<void> reopen(SeedDataBundle seed) async {
    await close();
    await init(seed);
    _notify();
  }

  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
    }
    _db = null;
  }

  void _notify() {
    if (!_changes.isClosed) {
      _changes.add(null);
    }
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE schema_migrations (
        version INTEGER PRIMARY KEY,
        applied_at TEXT NOT NULL,
        description TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE profiles (
        id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL DEFAULT '',
        locale TEXT NOT NULL DEFAULT 'id_ID',
        timezone TEXT NOT NULL DEFAULT 'Asia/Jakarta',
        currency TEXT NOT NULL DEFAULT 'IDR',
        starter_selected INTEGER NOT NULL DEFAULT 0,
        starter_species_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE food_categories (
        id TEXT PRIMARY KEY,
        slug TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        icon TEXT NOT NULL,
        color_hex TEXT NOT NULL,
        sort_order INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE foods (
        id TEXT PRIMARY KEY,
        category_id TEXT NOT NULL REFERENCES food_categories(id),
        canonical_name TEXT NOT NULL,
        normalized_name TEXT NOT NULL UNIQUE,
        locale TEXT NOT NULL DEFAULT 'id_ID',
        description TEXT NOT NULL DEFAULT '',
        origin_region TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'active',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE food_aliases (
        id TEXT PRIMARY KEY,
        food_id TEXT NOT NULL REFERENCES foods(id) ON DELETE CASCADE,
        alias TEXT NOT NULL,
        normalized_alias TEXT NOT NULL,
        locale TEXT NOT NULL DEFAULT 'id_ID',
        UNIQUE(normalized_alias, locale)
      )
    ''');

    await db.execute('''
      CREATE TABLE food_tags (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE
      )
    ''');

    await db.execute('''
      CREATE TABLE food_tag_links (
        tag_id TEXT NOT NULL REFERENCES food_tags(id) ON DELETE CASCADE,
        food_id TEXT NOT NULL REFERENCES foods(id) ON DELETE CASCADE,
        PRIMARY KEY (tag_id, food_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE custom_foods (
        id TEXT PRIMARY KEY,
        profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        normalized_name TEXT NOT NULL,
        category_id TEXT NOT NULL REFERENCES food_categories(id),
        mapped_food_id TEXT REFERENCES foods(id),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE places (
        id TEXT PRIMARY KEY,
        profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
        display_name TEXT NOT NULL,
        lat REAL,
        lng REAL,
        address TEXT,
        source TEXT NOT NULL DEFAULT 'manual',
        privacy TEXT NOT NULL DEFAULT 'private',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE meal_sessions (
        id TEXT PRIMARY KEY,
        profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
        occurred_at TEXT NOT NULL,
        local_date TEXT NOT NULL,
        meal_type TEXT NOT NULL,
        place_id TEXT REFERENCES places(id) ON DELETE SET NULL,
        place_mode TEXT NOT NULL DEFAULT 'none',
        notes TEXT,
        is_reward_eligible INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE meal_items (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL REFERENCES meal_sessions(id) ON DELETE CASCADE,
        food_id TEXT REFERENCES foods(id),
        custom_food_id TEXT REFERENCES custom_foods(id),
        price_minor INTEGER,
        currency TEXT NOT NULL DEFAULT 'IDR',
        quantity INTEGER NOT NULL DEFAULT 1,
        rating INTEGER,
        photo_path TEXT,
        description TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        CHECK ((food_id IS NOT NULL AND custom_food_id IS NULL) OR (food_id IS NULL AND custom_food_id IS NOT NULL))
      )
    ''');

    await db.execute('''
      CREATE TABLE food_discoveries (
        id TEXT PRIMARY KEY,
        profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
        food_id TEXT NOT NULL REFERENCES foods(id),
        first_meal_item_id TEXT,
        discovered_date TEXT NOT NULL,
        discovered_at TEXT NOT NULL,
        UNIQUE(profile_id, food_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE monster_species (
        id TEXT PRIMARY KEY,
        slug TEXT NOT NULL UNIQUE,
        display_name TEXT NOT NULL,
        category_id TEXT NOT NULL REFERENCES food_categories(id),
        element_id TEXT NOT NULL,
        rarity_id TEXT NOT NULL,
        flavor_text TEXT NOT NULL,
        unlock_unique_foods INTEGER NOT NULL,
        unlock_category_days INTEGER NOT NULL,
        is_starter INTEGER NOT NULL DEFAULT 0,
        asset_baby TEXT NOT NULL,
        asset_young TEXT NOT NULL,
        asset_adult TEXT NOT NULL,
        sort_order INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE user_monsters (
        id TEXT PRIMARY KEY,
        profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
        species_id TEXT NOT NULL REFERENCES monster_species(id),
        level INTEGER NOT NULL DEFAULT 1,
        xp_total INTEGER NOT NULL DEFAULT 0,
        bond INTEGER NOT NULL DEFAULT 0,
        last_bond_at TEXT,
        is_active INTEGER NOT NULL DEFAULT 0,
        unlocked_at TEXT NOT NULL,
        evolved_young_at TEXT,
        evolved_adult_at TEXT,
        mastery_points INTEGER NOT NULL DEFAULT 0,
        UNIQUE(profile_id, species_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE monster_eggs (
        id TEXT PRIMARY KEY,
        profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
        species_id TEXT NOT NULL REFERENCES monster_species(id),
        element_id TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'queued',
        hatch_progress INTEGER NOT NULL DEFAULT 0,
        granted_at TEXT NOT NULL,
        incubated_at TEXT,
        hatched_at TEXT,
        UNIQUE(profile_id, species_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE egg_incubation_events (
        id TEXT PRIMARY KEY,
        egg_id TEXT NOT NULL REFERENCES monster_eggs(id) ON DELETE CASCADE,
        meal_session_id TEXT NOT NULL REFERENCES meal_sessions(id) ON DELETE CASCADE,
        created_at TEXT NOT NULL,
        UNIQUE(egg_id, meal_session_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE reward_ledger (
        id TEXT PRIMARY KEY,
        profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
        source_event_id TEXT NOT NULL,
        reward_type TEXT NOT NULL,
        value INTEGER NOT NULL,
        monster_id TEXT,
        local_date TEXT NOT NULL,
        idempotency_key TEXT NOT NULL UNIQUE,
        is_revoked INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    // Performance indexes
    await db.execute('CREATE INDEX idx_foods_cat ON foods(category_id)');
    await db.execute('CREATE INDEX idx_foods_norm ON foods(normalized_name)');
    await db.execute('CREATE INDEX idx_aliases_norm ON food_aliases(normalized_alias)');
    await db.execute('CREATE INDEX idx_aliases_food ON food_aliases(food_id)');
    await db.execute('CREATE INDEX idx_sessions_date ON meal_sessions(profile_id, local_date, meal_type)');
    await db.execute('CREATE INDEX idx_sessions_occ ON meal_sessions(occurred_at DESC)');
    await db.execute('CREATE INDEX idx_items_session ON meal_items(session_id)');
    await db.execute('CREATE INDEX idx_items_food ON meal_items(food_id)');
    await db.execute('CREATE INDEX idx_disc_profile ON food_discoveries(profile_id, food_id)');
    await db.execute('CREATE INDEX idx_ledger_monster ON reward_ledger(monster_id, is_revoked)');
    await db.execute('CREATE INDEX idx_ledger_date ON reward_ledger(profile_id, local_date, reward_type)');

    final nowIso = clock.now().toIso8601String();
    await db.insert('schema_migrations', {
      'version': version,
      'applied_at': nowIso,
      'description': 'Initial MamPet v1.0 schema',
    });
  }

  Future<void> _ensureSeeded(SeedDataBundle seed) async {
    final db = await database;
    final nowIso = clock.now().toIso8601String();

    await db.transaction((txn) async {
      // 1. Default profile
      final profiles = await txn.query('profiles', where: 'id = ?', whereArgs: [defaultProfileId]);
      if (profiles.isEmpty) {
        await txn.insert('profiles', {
          'id': defaultProfileId,
          'display_name': '',
          'locale': 'id_ID',
          'timezone': 'Asia/Jakarta',
          'currency': 'IDR',
          'starter_selected': 0,
          'starter_species_id': null,
          'created_at': nowIso,
          'updated_at': nowIso,
        });
      }

      // 2. Default settings
      final defaultSettings = {
        'reduce_motion': 'false',
        'theme_mode': 'light',
        'tutorial_completed': 'false',
        'schema_version': currentSchemaVersion.toString(),
      };
      for (final entry in defaultSettings.entries) {
        await txn.insert(
          'app_settings',
          {'key': entry.key, 'value': entry.value, 'updated_at': nowIso},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      // 3. Seed 12 food categories
      final catList = (seed.foodCatalog['categories'] as List<dynamic>);
      for (final raw in catList) {
        final c = raw as Map<String, dynamic>;
        await txn.insert(
          'food_categories',
          {
            'id': c['id'],
            'slug': c['slug'],
            'name': c['name'],
            'icon': c['icon'],
            'color_hex': c['color_hex'],
            'sort_order': c['sort_order'],
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      // 4. Seed 360+ master foods + aliases (only if foods table empty or new items added)
      final existingCount = Sqflite.firstIntValue(
            await txn.rawQuery('SELECT COUNT(*) FROM foods'),
          ) ??
          0;
      final foodsList = (seed.foodCatalog['foods'] as List<dynamic>);
      if (existingCount < foodsList.length) {
        final batch = txn.batch();
        for (final raw in foodsList) {
          final f = raw as Map<String, dynamic>;
          final foodId = f['id'] as String;
          batch.insert(
            'foods',
            {
              'id': foodId,
              'category_id': f['category_id'],
              'canonical_name': f['canonical_name'],
              'normalized_name': f['normalized_name'],
              'locale': f['locale'] ?? 'id_ID',
              'description': f['description'] ?? '',
              'origin_region': f['origin_region'] ?? '',
              'status': f['status'] ?? 'active',
              'created_at': nowIso,
              'updated_at': nowIso,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          final aliases = (f['aliases'] as List<dynamic>? ?? const []);
          for (var i = 0; i < aliases.length; i++) {
            final alias = aliases[i] as String;
            final normAlias = normalizeFoodText(alias);
            if (normAlias.isEmpty) continue;
            batch.insert(
              'food_aliases',
              {
                'id': '${foodId}_alias_$i',
                'food_id': foodId,
                'alias': alias,
                'normalized_alias': normAlias,
                'locale': f['locale'] ?? 'id_ID',
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }
        }
        await batch.commit(noResult: true);
      }

      // 5. Seed 20 official monster species
      final speciesList = (seed.gameConfig['species'] as List<dynamic>);
      for (final raw in speciesList) {
        final s = raw as Map<String, dynamic>;
        await txn.insert(
          'monster_species',
          {
            'id': s['id'],
            'slug': s['slug'],
            'display_name': s['display_name'],
            'category_id': s['category_id'],
            'element_id': s['element_id'],
            'rarity_id': s['rarity_id'],
            'flavor_text': s['flavor_text'],
            'unlock_unique_foods': s['unlock_unique_foods'],
            'unlock_category_days': s['unlock_category_days'],
            'is_starter': (s['is_starter'] == true) ? 1 : 0,
            'asset_baby': s['asset_baby'],
            'asset_young': s['asset_young'],
            'asset_adult': s['asset_adult'],
            'sort_order': s['sort_order'],
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  // ============================================================
  // PROFILE & SETTINGS
  // ============================================================

  Future<UserProfile> getProfile() async {
    final db = await database;
    final rows = await db.query('profiles', where: 'id = ?', whereArgs: [defaultProfileId]);
    return UserProfile.fromMap(rows.first);
  }

  Future<void> updateDisplayName(String displayName) async {
    final db = await database;
    await db.update(
      'profiles',
      {
        'display_name': displayName.trim(),
        'updated_at': clock.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [defaultProfileId],
    );
    _notify();
  }

  /// AC-01: Selects starter (Foxili 04, Sproutle 06, or Axolumi 07), creates
  /// Level 1 active user_monster without creating an egg.
  Future<void> completeOnboarding({
    required String displayName,
    required String starterSpeciesId,
  }) async {
    final db = await database;
    final nowIso = clock.now().toIso8601String();

    await db.transaction((txn) async {
      await txn.update(
        'profiles',
        {
          'display_name': displayName.trim(),
          'starter_selected': 1,
          'starter_species_id': starterSpeciesId,
          'updated_at': nowIso,
        },
        where: 'id = ?',
        whereArgs: [defaultProfileId],
      );

      final existing = await txn.query(
        'user_monsters',
        where: 'profile_id = ? AND species_id = ?',
        whereArgs: [defaultProfileId, starterSpeciesId],
      );
      if (existing.isEmpty) {
        await txn.update(
          'user_monsters',
          {'is_active': 0},
          where: 'profile_id = ?',
          whereArgs: [defaultProfileId],
        );
        await txn.insert('user_monsters', {
          'id': _uuid.v4(),
          'profile_id': defaultProfileId,
          'species_id': starterSpeciesId,
          'level': 1,
          'xp_total': 0,
          'bond': 0,
          'last_bond_at': null,
          'is_active': 1,
          'unlocked_at': nowIso,
          'evolved_young_at': null,
          'evolved_adult_at': null,
          'mastery_points': 0,
        });
      }
    });
    _notify();
  }

  Future<AppSettingsModel> getSettings() async {
    final db = await database;
    final rows = await db.query('app_settings');
    final map = <String, String>{};
    for (final r in rows) {
      map[r['key'] as String] = r['value'] as String;
    }
    return AppSettingsModel(
      reduceMotion: map['reduce_motion'] == 'true',
      themeMode: map['theme_mode'] ?? 'light',
      lastBackupAt: map['last_backup_at'],
      tutorialCompleted: map['tutorial_completed'] == 'true',
      lastRecordedLocalDate: map['last_recorded_local_date'],
    );
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'app_settings',
      {
        'key': key,
        'value': value,
        'updated_at': clock.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notify();
  }

  // ============================================================
  // FOOD CATALOG & SEARCH
  // ============================================================

  Future<List<FoodCategory>> getCategories() async {
    final db = await database;
    final rows = await db.query('food_categories', orderBy: 'sort_order ASC');
    return rows.map(FoodCategory.fromMap).toList();
  }

  Future<List<MasterFood>> getAllMasterFoods() async {
    final db = await database;
    final foodRows = await db.query(
      'foods',
      where: "status = 'active'",
      orderBy: 'canonical_name ASC',
    );
    final aliasRows = await db.query('food_aliases');
    final aliasMap = <String, List<String>>{};
    for (final a in aliasRows) {
      final fid = a['food_id'] as String;
      aliasMap.putIfAbsent(fid, () => []).add(a['alias'] as String);
    }
    return foodRows
        .map((r) => MasterFood.fromMap(r, aliases: aliasMap[r['id'] as String] ?? const []))
        .toList();
  }

  Future<MasterFood?> getMasterFoodById(String foodId) async {
    final db = await database;
    final rows = await db.query('foods', where: 'id = ?', whereArgs: [foodId]);
    if (rows.isEmpty) return null;
    final aliasRows = await db.query('food_aliases', where: 'food_id = ?', whereArgs: [foodId]);
    return MasterFood.fromMap(
      rows.first,
      aliases: aliasRows.map((e) => e['alias'] as String).toList(),
    );
  }

  /// Normalized, alias-aware search across master foods without AI.
  Future<List<MasterFood>> searchMasterFoods(
    String query, {
    String? categoryId,
    int limit = 60,
  }) async {
    final db = await database;
    final norm = normalizeFoodText(query);
    if (norm.isEmpty) {
      final rows = await db.query(
        'foods',
        where: categoryId != null ? "status = 'active' AND category_id = ?" : "status = 'active'",
        whereArgs: categoryId != null ? [categoryId] : null,
        orderBy: 'canonical_name ASC',
        limit: limit,
      );
      return _attachAliases(db, rows);
    }

    final likeArg = '%$norm%';
    final startsArg = '$norm%';
    final whereCat = categoryId != null ? ' AND f.category_id = ?' : '';
    final args = <Object?>[
      norm,
      norm,
      startsArg,
      startsArg,
      likeArg,
      likeArg,
      ?categoryId,
      limit,
    ];

    final rows = await db.rawQuery('''
      SELECT DISTINCT f.*,
        CASE
          WHEN f.normalized_name = ? THEN 0
          WHEN EXISTS (SELECT 1 FROM food_aliases a WHERE a.food_id = f.id AND a.normalized_alias = ?) THEN 1
          WHEN f.normalized_name LIKE ? THEN 2
          WHEN EXISTS (SELECT 1 FROM food_aliases a WHERE a.food_id = f.id AND a.normalized_alias LIKE ?) THEN 3
          ELSE 4
        END AS match_rank
      FROM foods f
      LEFT JOIN food_aliases a ON a.food_id = f.id
      WHERE f.status = 'active'
        AND (f.normalized_name LIKE ? OR a.normalized_alias LIKE ?)
        $whereCat
      ORDER BY match_rank ASC, f.canonical_name ASC
      LIMIT ?
    ''', args);

    return _attachAliases(db, rows);
  }

  Future<List<MasterFood>> _attachAliases(
    DatabaseExecutor db,
    List<Map<String, Object?>> foodRows,
  ) async {
    if (foodRows.isEmpty) return [];
    final ids = foodRows.map((r) => r['id'] as String).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final aliasRows = await db.rawQuery(
      'SELECT food_id, alias FROM food_aliases WHERE food_id IN ($placeholders)',
      ids,
    );
    final aliasMap = <String, List<String>>{};
    for (final a in aliasRows) {
      final fid = a['food_id'] as String;
      aliasMap.putIfAbsent(fid, () => []).add(a['alias'] as String);
    }
    return foodRows
        .map((r) => MasterFood.fromMap(r, aliases: aliasMap[r['id'] as String] ?? const []))
        .toList();
  }

  Future<List<MasterFood>> getRecentMasterFoods({int limit = 12}) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT f.*
      FROM foods f
      INNER JOIN (
        SELECT food_id, MAX(created_at) AS last_used
        FROM meal_items
        WHERE food_id IS NOT NULL
        GROUP BY food_id
      ) r ON r.food_id = f.id
      WHERE f.status = 'active'
      ORDER BY r.last_used DESC
      LIMIT ?
    ''', [limit]);
    return _attachAliases(db, rows);
  }

  Future<Set<String>> getDiscoveredFoodIds() async {
    final db = await database;
    final rows = await db.query(
      'food_discoveries',
      columns: ['food_id'],
      where: 'profile_id = ?',
      whereArgs: [defaultProfileId],
    );
    return rows.map((r) => r['food_id'] as String).toSet();
  }

  // ============================================================
  // CUSTOM FOODS & MAPPING TO MASTER
  // ============================================================

  Future<List<CustomFood>> getCustomFoods() async {
    final db = await database;
    final rows = await db.query(
      'custom_foods',
      where: 'profile_id = ?',
      whereArgs: [defaultProfileId],
      orderBy: 'created_at DESC',
    );
    return rows.map(CustomFood.fromMap).toList();
  }

  /// Unmapped custom foods that have been logged at least once in meal history,
  /// automatically counted as personal FoodDex discoveries.
  Future<List<CustomFood>> getDiscoveredCustomFoods() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT cf.*
      FROM custom_foods cf
      INNER JOIN meal_items mi ON mi.custom_food_id = cf.id
      INNER JOIN meal_sessions ms ON ms.id = mi.session_id
      WHERE cf.profile_id = ?
        AND ms.profile_id = ?
        AND cf.mapped_food_id IS NULL
      ORDER BY cf.name ASC
    ''', [defaultProfileId, defaultProfileId]);
    return rows.map(CustomFood.fromMap).toList();
  }

  Future<CustomFood> createCustomFood({
    required String name,
    required String categoryId,
  }) async {
    final db = await database;
    final norm = normalizeFoodText(name);
    // Prevent duplicate unmapped custom food entries with identical normalized names
    final existing = await db.query(
      'custom_foods',
      where: 'profile_id = ? AND normalized_name = ? AND mapped_food_id IS NULL',
      whereArgs: [defaultProfileId, norm],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return CustomFood.fromMap(existing.first);
    }

    final now = clock.now();
    final id = _uuid.v4();
    await db.insert('custom_foods', {
      'id': id,
      'profile_id': defaultProfileId,
      'name': name.trim(),
      'normalized_name': norm,
      'category_id': categoryId,
      'mapped_food_id': null,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    _notify();
    return CustomFood(
      id: id,
      profileId: defaultProfileId,
      name: name.trim(),
      normalizedName: norm,
      categoryId: categoryId,
      createdAt: now,
    );
  }

  /// Section 4.3 & 5.1: Maps a custom food to a curated master food, migrates
  /// meal items, and reconciles one-time discovery & egg eligibility atomically.
  Future<({bool newlyDiscovered, int bonusXp, List<MonsterEgg> grantedEggs})>
      mapCustomFoodToMaster({
    required String customFoodId,
    required String masterFoodId,
  }) async {
    final db = await database;
    final now = clock.now();
    final today = AppClock.formatLocalDate(now);
    bool newlyDiscovered = false;
    int bonusXp = 0;
    final grantedEggs = <MonsterEgg>[];

    await db.transaction((txn) async {
      await txn.update(
        'custom_foods',
        {
          'mapped_food_id': masterFoodId,
          'updated_at': now.toIso8601String(),
        },
        where: 'id = ? AND profile_id = ?',
        whereArgs: [customFoodId, defaultProfileId],
      );

      // Revoke standalone custom discovery ledger before merging into master to prevent double XP
      await txn.update(
        'reward_ledger',
        {'is_revoked': 1},
        where: 'idempotency_key = ?',
        whereArgs: ['custom_discovery:$defaultProfileId:$customFoodId'],
      );

      final items = await txn.query(
        'meal_items',
        where: 'custom_food_id = ?',
        whereArgs: [customFoodId],
      );

      for (final item in items) {
        await txn.update(
          'meal_items',
          {
            'food_id': masterFoodId,
            'custom_food_id': null,
            'updated_at': now.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [item['id']],
        );
      }

      if (items.isNotEmpty) {
        final discExists = await txn.query(
          'food_discoveries',
          where: 'profile_id = ? AND food_id = ?',
          whereArgs: [defaultProfileId, masterFoodId],
        );
        if (discExists.isEmpty) {
          newlyDiscovered = true;
          await txn.insert('food_discoveries', {
            'id': _uuid.v4(),
            'profile_id': defaultProfileId,
            'food_id': masterFoodId,
            'first_meal_item_id': items.first['id'],
            'discovered_date': today,
            'discovered_at': now.toIso8601String(),
          });

          final activeMonster = await _getActiveMonsterTxn(txn);
          if (activeMonster != null) {
            final dailyDiscCount = await _countActiveDiscoveryBonusesTxn(txn, today);
            if (dailyDiscCount < GameRules.maxDailyDiscoveryBonuses) {
              final awarded = await _awardOrUnrevokeLedgerTxn(
                txn: txn,
                idempotencyKey: 'discovery:$defaultProfileId:$masterFoodId',
                sourceEventId: items.first['id'] as String,
                rewardType: 'discovery_xp',
                value: GameRules.discoveryBonusXp,
                monsterId: activeMonster.id,
                localDate: today,
                nowIso: now.toIso8601String(),
              );
              if (awarded) {
                bonusXp = GameRules.discoveryBonusXp;
                await _recomputeMonsterXpTxn(txn, activeMonster.id, now.toIso8601String());
              }
            }
          }
        }
      }

      final eggOutcome = await _evaluateSpeciesUnlocksTxn(txn, now.toIso8601String());
      grantedEggs.addAll(eggOutcome.grantedEggs);
    });

    _notify();
    return (
      newlyDiscovered: newlyDiscovered,
      bonusXp: bonusXp,
      grantedEggs: grantedEggs,
    );
  }

  // ============================================================
  // PLACES
  // ============================================================

  Future<List<PlaceModel>> getPlaces() async {
    final db = await database;
    final rows = await db.query(
      'places',
      where: 'profile_id = ?',
      whereArgs: [defaultProfileId],
      orderBy: 'display_name ASC',
    );
    return rows.map(PlaceModel.fromMap).toList();
  }

  Future<PlaceModel> createPlace({
    required String displayName,
    double? lat,
    double? lng,
    String? address,
    String source = 'manual',
  }) async {
    final db = await database;
    final now = clock.now();
    final id = _uuid.v4();
    await db.insert('places', {
      'id': id,
      'profile_id': defaultProfileId,
      'display_name': displayName.trim(),
      'lat': lat,
      'lng': lng,
      'address': address?.trim().isEmpty == true ? null : address?.trim(),
      'source': source,
      'privacy': 'private',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    _notify();
    return PlaceModel(
      id: id,
      profileId: defaultProfileId,
      displayName: displayName.trim(),
      lat: lat,
      lng: lng,
      address: address?.trim().isEmpty == true ? null : address?.trim(),
      source: source,
      createdAt: now,
    );
  }

  // ============================================================
  // MEAL SESSIONS (ATOMIC SAVE, EDIT, DELETE + LEDGER ENGINE)
  // ============================================================

  Future<SaveMealResult> saveMealSession({
    required DateTime occurredAt,
    required MealType mealType,
    required List<MealItemDraft> items,
    required PlaceMode placeMode,
    String? placeId,
    String? notes,
  }) async {
    if (items.isEmpty) {
      throw ArgumentError('Sesi makan harus memiliki minimal satu makanan.');
    }

    final db = await database;
    final now = clock.now();
    final today = AppClock.formatLocalDate(now);
    final sessionLocalDate = AppClock.formatLocalDate(occurredAt);

    // Reject future dates beyond slight clock tolerance
    if (occurredAt.isAfter(now.add(const Duration(minutes: 5)))) {
      throw ArgumentError('Waktu makan tidak boleh di masa depan.');
    }

    // Backdated sessions are valid for history, not eligible for today's XP/days/incubator
    final bool isToday = sessionLocalDate == today;
    final bool isRewardEligible = isToday;
    final bool wasBackdated = !isToday;

    late SaveMealResult result;

    await db.transaction((txn) async {
      // Clock rollback detection (Section 17)
      bool clockWarning = false;
      final lastDateRows = await txn.query(
        'app_settings',
        where: "key = 'last_recorded_local_date'",
      );
      if (lastDateRows.isNotEmpty) {
        final lastRecorded = lastDateRows.first['value'] as String;
        if (today.compareTo(lastRecorded) < 0) {
          clockWarning = true;
        }
      }
      if (!clockWarning && (lastDateRows.isEmpty || today.compareTo(lastDateRows.first['value'] as String) >= 0)) {
        await txn.insert(
          'app_settings',
          {
            'key': 'last_recorded_local_date',
            'value': today,
            'updated_at': now.toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // Snapshot grades & active monster before save
      final gradesBefore = await _computeAllCategoryMasteriesTxn(txn);
      final activeBefore = await _getActiveMonsterTxn(txn);

      // Persist meal_session
      final sessionId = _uuid.v4();
      final effectivePlaceId = placeMode == PlaceMode.place ? placeId : null;
      await txn.insert('meal_sessions', {
        'id': sessionId,
        'profile_id': defaultProfileId,
        'occurred_at': occurredAt.toIso8601String(),
        'local_date': sessionLocalDate,
        'meal_type': mealType.code,
        'place_id': effectivePlaceId,
        'place_mode': placeMode.code,
        'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
        'is_reward_eligible': isRewardEligible ? 1 : 0,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      // Check which custom foods were already logged before this session
      final incomingCustomIds = items
          .map((e) => e.customFoodId)
          .whereType<String>()
          .toSet();
      final previouslyLoggedCustomIds = <String>{};
      if (incomingCustomIds.isNotEmpty) {
        final ph = List.filled(incomingCustomIds.length, '?').join(',');
        final prevRows = await txn.rawQuery('''
          SELECT DISTINCT mi.custom_food_id
          FROM meal_items mi
          INNER JOIN meal_sessions ms ON ms.id = mi.session_id
          WHERE ms.profile_id = ? AND mi.custom_food_id IN ($ph)
        ''', [defaultProfileId, ...incomingCustomIds]);
        for (final r in prevRows) {
          if (r['custom_food_id'] != null) {
            previouslyLoggedCustomIds.add(r['custom_food_id'] as String);
          }
        }
      }

      // Persist meal_items
      final distinctMasterFoodIds = <String>{};
      final firstItemIdByFood = <String, String>{};
      final distinctCustomFoodIds = <String>{};
      final firstItemIdByCustom = <String, String>{};
      for (final item in items) {
        final itemId = _uuid.v4();
        final desc = item.description?.trim();
        await txn.insert('meal_items', {
          'id': itemId,
          'session_id': sessionId,
          'food_id': item.foodId,
          'custom_food_id': item.customFoodId,
          'price_minor': item.priceMinor != null && item.priceMinor! >= 0
              ? item.priceMinor
              : null,
          'currency': 'IDR',
          'quantity': item.quantity < 1 ? 1 : item.quantity,
          'rating': (item.rating != null && item.rating! >= 1 && item.rating! <= 5)
              ? item.rating
              : null,
          'photo_path': item.photoPath,
          'description': desc == null || desc.isEmpty
              ? null
              : (desc.length > 500 ? desc.substring(0, 500) : desc),
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
        if (item.foodId != null) {
          distinctMasterFoodIds.add(item.foodId!);
          firstItemIdByFood.putIfAbsent(item.foodId!, () => itemId);
        } else if (item.customFoodId != null) {
          distinctCustomFoodIds.add(item.customFoodId!);
          firstItemIdByCustom.putIfAbsent(item.customFoodId!, () => itemId);
        }
      }

      int sessionXpAwarded = 0;
      int discoveryXpAwarded = 0;
      final newlyDiscoveredFoods = <MasterFood>[];
      bool eggProgressed = false;
      MonsterEgg? updatedEgg;

      // 1. Session Slot XP + Active Egg Incubation (only if reward-eligible today and mealType awards XP)
      if (isRewardEligible && mealType.awardsSessionXp) {
        final slotKey = 'session_slot:$defaultProfileId:$sessionLocalDate:${mealType.code}';
        final awardedSlot = await _awardOrUnrevokeLedgerTxn(
          txn: txn,
          idempotencyKey: slotKey,
          sourceEventId: sessionId,
          rewardType: 'session_xp',
          value: mealType.baseXp,
          monsterId: activeBefore?.id,
          localDate: sessionLocalDate,
          nowIso: now.toIso8601String(),
        );
        if (awardedSlot) {
          sessionXpAwarded = mealType.baseXp;
          // Increment active incubating egg (once per meal_session_id, only if incubated before now)
          final incResult = await _incrementActiveEggTxn(
            txn: txn,
            mealSessionId: sessionId,
            sessionCreatedAt: now,
          );
          eggProgressed = incResult.progressed;
          updatedEgg = incResult.egg;
        }
      }

      // 2. FoodDex Master Discoveries + Daily Discovery Bonus XP (max 3/day)
      for (final foodId in distinctMasterFoodIds) {
        final existingDisc = await txn.query(
          'food_discoveries',
          where: 'profile_id = ? AND food_id = ?',
          whereArgs: [defaultProfileId, foodId],
        );
        if (existingDisc.isEmpty) {
          await txn.insert('food_discoveries', {
            'id': _uuid.v4(),
            'profile_id': defaultProfileId,
            'food_id': foodId,
            'first_meal_item_id': firstItemIdByFood[foodId],
            'discovered_date': sessionLocalDate,
            'discovered_at': now.toIso8601String(),
          });

          final foodRows = await txn.query('foods', where: 'id = ?', whereArgs: [foodId]);
          if (foodRows.isNotEmpty) {
            newlyDiscoveredFoods.add(MasterFood.fromMap(foodRows.first));
          }

          if (isRewardEligible) {
            final dailyDiscCount = await _countActiveDiscoveryBonusesTxn(txn, sessionLocalDate);
            if (dailyDiscCount < GameRules.maxDailyDiscoveryBonuses) {
              final discKey = 'discovery:$defaultProfileId:$foodId';
              final awardedDisc = await _awardOrUnrevokeLedgerTxn(
                txn: txn,
                idempotencyKey: discKey,
                sourceEventId: firstItemIdByFood[foodId] ?? sessionId,
                rewardType: 'discovery_xp',
                value: GameRules.discoveryBonusXp,
                monsterId: activeBefore?.id,
                localDate: sessionLocalDate,
                nowIso: now.toIso8601String(),
              );
              if (awardedDisc) {
                discoveryXpAwarded += GameRules.discoveryBonusXp;
              }
            }
          }
        }
      }

      // 2b. Standalone Custom Food Discoveries (First-Class FoodDex Collection!)
      for (final customId in distinctCustomFoodIds) {
        if (previouslyLoggedCustomIds.contains(customId)) continue;
        final cfRows = await txn.query(
          'custom_foods',
          where: 'id = ? AND profile_id = ? AND mapped_food_id IS NULL',
          whereArgs: [customId, defaultProfileId],
        );
        if (cfRows.isEmpty) continue;
        final cf = CustomFood.fromMap(cfRows.first);
        newlyDiscoveredFoods.add(
          MasterFood(
            id: 'custom:${cf.id}',
            categoryId: cf.categoryId,
            canonicalName: cf.name,
            normalizedName: cf.normalizedName,
            locale: 'id_ID',
            description: 'Menu koleksi pribadi di FoodDex',
            originRegion: 'Custom',
            status: 'custom',
          ),
        );
        if (isRewardEligible) {
          final dailyDiscCount =
              await _countActiveDiscoveryBonusesTxn(txn, sessionLocalDate);
          if (dailyDiscCount < GameRules.maxDailyDiscoveryBonuses) {
            final discKey = 'custom_discovery:$defaultProfileId:$customId';
            final awardedDisc = await _awardOrUnrevokeLedgerTxn(
              txn: txn,
              idempotencyKey: discKey,
              sourceEventId: firstItemIdByCustom[customId] ?? sessionId,
              rewardType: 'discovery_xp',
              value: GameRules.discoveryBonusXp,
              monsterId: activeBefore?.id,
              localDate: sessionLocalDate,
              nowIso: now.toIso8601String(),
            );
            if (awardedDisc) {
              discoveryXpAwarded += GameRules.discoveryBonusXp;
            }
          }
        }
      }

      // 3. Recompute active monster XP, level, and evolution timestamps
      UserMonster? activeAfter;
      MonsterSpecies? activeSpecies;
      EvolutionPhase? evolvedFrom;
      EvolutionPhase? evolvedTo;

      if (activeBefore != null) {
        activeAfter = await _recomputeMonsterXpTxn(
          txn,
          activeBefore.id,
          now.toIso8601String(),
        );
        final spRows = await txn.query(
          'monster_species',
          where: 'id = ?',
          whereArgs: [activeBefore.speciesId],
        );
        if (spRows.isNotEmpty) {
          activeSpecies = MonsterSpecies.fromMap(spRows.first);
        }
        if (activeBefore.phase != activeAfter.phase) {
          evolvedFrom = activeBefore.phase;
          evolvedTo = activeAfter.phase;
        }
      }

      // 4. Re-evaluate species egg eligibility & starter mastery bonuses
      final unlockOutcome = await _evaluateSpeciesUnlocksTxn(txn, now.toIso8601String());

      // 5. Detect Grade upgrades
      final gradesAfter = await _computeAllCategoryMasteriesTxn(txn);
      final cats = await txn.query('food_categories');
      final catNameMap = {
        for (final c in cats) c['id'] as String: c['name'] as String,
      };
      final gradeUpgrades =
          <({String categoryName, CategoryGrade oldGrade, CategoryGrade newGrade})>[];
      for (final entry in gradesAfter.entries) {
        final oldG = gradesBefore[entry.key]?.grade ?? CategoryGrade.c;
        final newG = entry.value.grade;
        if (newG.rank > oldG.rank) {
          gradeUpgrades.add((
            categoryName: catNameMap[entry.key] ?? entry.key,
            oldGrade: oldG,
            newGrade: newG,
          ));
        }
      }

      // Mark tutorial done after first meal saved
      await txn.insert(
        'app_settings',
        {
          'key': 'tutorial_completed',
          'value': 'true',
          'updated_at': now.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      result = SaveMealResult(
        sessionId: sessionId,
        sessionXpAwarded: sessionXpAwarded,
        discoveryXpAwarded: discoveryXpAwarded,
        newlyDiscoveredFoods: newlyDiscoveredFoods,
        newlyGrantedEggs: unlockOutcome.grantedEggs,
        starterMasteryBonusSpeciesIds: unlockOutcome.starterBonusSpeciesIds,
        eggProgressed: eggProgressed,
        updatedIncubatingEgg: updatedEgg,
        activeMonsterBefore: activeBefore,
        activeMonsterAfter: activeAfter,
        activeMonsterSpecies: activeSpecies,
        evolvedFrom: evolvedFrom,
        evolvedTo: evolvedTo,
        gradeUpgrades: gradeUpgrades,
        wasBackdated: wasBackdated,
        clockWarning: clockWarning,
      );
    });

    _notify();
    return result;
  }

  /// Edits an existing meal session atomically and deterministically reconciles
  /// discoveries, session slot XP, active monster XP, and egg incubation.
  Future<void> updateMealSession({
    required String sessionId,
    required DateTime occurredAt,
    required MealType mealType,
    required List<MealItemDraft> items,
    required PlaceMode placeMode,
    String? placeId,
    String? notes,
  }) async {
    if (items.isEmpty) {
      throw ArgumentError('Sesi makan harus memiliki minimal satu makanan.');
    }
    final db = await database;
    final now = clock.now();
    final today = AppClock.formatLocalDate(now);
    final newLocalDate = AppClock.formatLocalDate(occurredAt);

    if (occurredAt.isAfter(now.add(const Duration(minutes: 5)))) {
      throw ArgumentError('Waktu makan tidak boleh di masa depan.');
    }

    await db.transaction((txn) async {
      final oldRows = await txn.query('meal_sessions', where: 'id = ?', whereArgs: [sessionId]);
      if (oldRows.isEmpty) return;
      final oldSession = oldRows.first;
      final oldLocalDate = oldSession['local_date'] as String;
      final oldMealType = MealType.fromCode(oldSession['meal_type'] as String);
      final oldEligible = (oldSession['is_reward_eligible'] as int? ?? 0) == 1;

      // Backdated edit never turns an old non-eligible session into a reward-eligible session
      final bool newEligible = oldEligible && (newLocalDate == today);

      final oldItemRows = await txn.query('meal_items', where: 'session_id = ?', whereArgs: [sessionId]);
      final affectedFoodIds = <String>{};
      final affectedCustomIds = <String>{};
      for (final r in oldItemRows) {
        if (r['food_id'] != null) affectedFoodIds.add(r['food_id'] as String);
        if (r['custom_food_id'] != null) {
          affectedCustomIds.add(r['custom_food_id'] as String);
        }
      }

      final effectivePlaceId = placeMode == PlaceMode.place ? placeId : null;
      await txn.update(
        'meal_sessions',
        {
          'occurred_at': occurredAt.toIso8601String(),
          'local_date': newLocalDate,
          'meal_type': mealType.code,
          'place_id': effectivePlaceId,
          'place_mode': placeMode.code,
          'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
          'is_reward_eligible': newEligible ? 1 : 0,
          'updated_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [sessionId],
      );

      // Replace items
      await txn.delete('meal_items', where: 'session_id = ?', whereArgs: [sessionId]);
      final firstItemIdByFood = <String, String>{};
      for (final item in items) {
        final itemId = item.id ?? _uuid.v4();
        final desc = item.description?.trim();
        await txn.insert('meal_items', {
          'id': itemId,
          'session_id': sessionId,
          'food_id': item.foodId,
          'custom_food_id': item.customFoodId,
          'price_minor': item.priceMinor != null && item.priceMinor! >= 0
              ? item.priceMinor
              : null,
          'currency': 'IDR',
          'quantity': item.quantity < 1 ? 1 : item.quantity,
          'rating': (item.rating != null && item.rating! >= 1 && item.rating! <= 5)
              ? item.rating
              : null,
          'photo_path': item.photoPath,
          'description': desc == null || desc.isEmpty
              ? null
              : (desc.length > 500 ? desc.substring(0, 500) : desc),
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
        if (item.foodId != null) {
          affectedFoodIds.add(item.foodId!);
          firstItemIdByFood.putIfAbsent(item.foodId!, () => itemId);
        } else if (item.customFoodId != null) {
          affectedCustomIds.add(item.customFoodId!);
        }
      }

      // If session no longer qualifies for reward (e.g. changed to 'other' or backdated), remove its incubation event
      if (!newEligible || !mealType.awardsSessionXp) {
        await txn.delete('egg_incubation_events', where: 'meal_session_id = ?', whereArgs: [sessionId]);
      }

      // Reconcile affected slots
      await _reconcileSlotLedgerTxn(txn, oldLocalDate, oldMealType, now.toIso8601String());
      if (newLocalDate != oldLocalDate || mealType != oldMealType) {
        await _reconcileSlotLedgerTxn(txn, newLocalDate, mealType, now.toIso8601String());
      }

      // Reconcile discoveries for all affected master & custom foods
      final activeMonster = await _getActiveMonsterTxn(txn);
      for (final foodId in affectedFoodIds) {
        await _reconcileFoodDiscoveryTxn(
          txn: txn,
          foodId: foodId,
          allowNewDiscoveryBonus: newEligible,
          localDate: newLocalDate,
          fallbackItemId: firstItemIdByFood[foodId],
          activeMonsterId: activeMonster?.id,
          nowIso: now.toIso8601String(),
        );
      }
      for (final customId in affectedCustomIds) {
        await _reconcileCustomDiscoveryTxn(
          txn: txn,
          customFoodId: customId,
          allowNewDiscoveryBonus: newEligible,
          localDate: newLocalDate,
          activeMonsterId: activeMonster?.id,
          nowIso: now.toIso8601String(),
        );
      }

      // Recompute all owned monsters XP & active egg progress
      await _recomputeAllMonstersXpTxn(txn, now.toIso8601String());
      await _reconcileActiveEggProgressTxn(txn);
      await _evaluateSpeciesUnlocksTxn(txn, now.toIso8601String());
    });

    _notify();
  }

  /// Deletes a meal session atomically and deterministically reconciles
  /// ledger XP, FoodDex discoveries, and incubating egg progress (AC-13).
  Future<List<String>> deleteMealSession(String sessionId) async {
    final db = await database;
    final nowIso = clock.now().toIso8601String();
    final photoPaths = <String>[];

    await db.transaction((txn) async {
      final sessionRows = await txn.query('meal_sessions', where: 'id = ?', whereArgs: [sessionId]);
      if (sessionRows.isEmpty) return;
      final session = sessionRows.first;
      final localDate = session['local_date'] as String;
      final mealType = MealType.fromCode(session['meal_type'] as String);

      final itemRows = await txn.query('meal_items', where: 'session_id = ?', whereArgs: [sessionId]);
      final affectedFoodIds = <String>{};
      final affectedCustomIds = <String>{};
      for (final item in itemRows) {
        if (item['food_id'] != null) affectedFoodIds.add(item['food_id'] as String);
        if (item['custom_food_id'] != null) {
          affectedCustomIds.add(item['custom_food_id'] as String);
        }
        if (item['photo_path'] != null) photoPaths.add(item['photo_path'] as String);
      }

      // Cascades delete meal_items and egg_incubation_events
      await txn.delete('meal_sessions', where: 'id = ?', whereArgs: [sessionId]);

      // Reconcile slot XP ledger
      await _reconcileSlotLedgerTxn(txn, localDate, mealType, nowIso);

      // Reconcile discoveries for removed master & custom foods
      for (final foodId in affectedFoodIds) {
        await _reconcileFoodDiscoveryTxn(
          txn: txn,
          foodId: foodId,
          allowNewDiscoveryBonus: false,
          localDate: localDate,
          fallbackItemId: null,
          activeMonsterId: null,
          nowIso: nowIso,
        );
      }
      for (final customId in affectedCustomIds) {
        await _reconcileCustomDiscoveryTxn(
          txn: txn,
          customFoodId: customId,
          allowNewDiscoveryBonus: false,
          localDate: localDate,
          activeMonsterId: null,
          nowIso: nowIso,
        );
      }

      // Recompute monster XP & active egg progress
      await _recomputeAllMonstersXpTxn(txn, nowIso);
      await _reconcileActiveEggProgressTxn(txn);
    });

    _notify();
    return photoPaths;
  }

  // ============================================================
  // TRANSACTIONAL LEDGER & RECONCILIATION HELPERS
  // ============================================================

  Future<bool> _awardOrUnrevokeLedgerTxn({
    required Transaction txn,
    required String idempotencyKey,
    required String sourceEventId,
    required String rewardType,
    required int value,
    required String? monsterId,
    required String localDate,
    required String nowIso,
  }) async {
    final existing = await txn.query(
      'reward_ledger',
      where: 'idempotency_key = ?',
      whereArgs: [idempotencyKey],
    );
    if (existing.isEmpty) {
      await txn.insert('reward_ledger', {
        'id': _uuid.v4(),
        'profile_id': defaultProfileId,
        'source_event_id': sourceEventId,
        'reward_type': rewardType,
        'value': value,
        'monster_id': monsterId,
        'local_date': localDate,
        'idempotency_key': idempotencyKey,
        'is_revoked': 0,
        'created_at': nowIso,
      });
      return true;
    }

    final row = existing.first;
    if ((row['is_revoked'] as int? ?? 0) == 1) {
      await txn.update(
        'reward_ledger',
        {
          'source_event_id': sourceEventId,
          'value': value,
          'monster_id': monsterId ?? row['monster_id'],
          'local_date': localDate,
          'is_revoked': 0,
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
      return true;
    }
    return false;
  }

  Future<int> _countActiveDiscoveryBonusesTxn(Transaction txn, String localDate) async {
    return Sqflite.firstIntValue(await txn.rawQuery('''
          SELECT COUNT(*) FROM reward_ledger
          WHERE profile_id = ? AND local_date = ?
            AND reward_type = 'discovery_xp' AND is_revoked = 0
        ''', [defaultProfileId, localDate])) ??
        0;
  }

  Future<void> _reconcileSlotLedgerTxn(
    Transaction txn,
    String localDate,
    MealType mealType,
    String nowIso,
  ) async {
    if (!mealType.awardsSessionXp) return;
    final slotKey = 'session_slot:$defaultProfileId:$localDate:${mealType.code}';

    final remaining = await txn.query(
      'meal_sessions',
      where: 'profile_id = ? AND local_date = ? AND meal_type = ? AND is_reward_eligible = 1',
      whereArgs: [defaultProfileId, localDate, mealType.code],
      orderBy: 'created_at ASC',
      limit: 1,
    );

    final ledgerRows = await txn.query(
      'reward_ledger',
      where: 'idempotency_key = ?',
      whereArgs: [slotKey],
    );

    if (remaining.isEmpty) {
      if (ledgerRows.isNotEmpty) {
        await txn.update(
          'reward_ledger',
          {'is_revoked': 1},
          where: 'id = ?',
          whereArgs: [ledgerRows.first['id']],
        );
      }
    } else {
      final earliestId = remaining.first['id'] as String;
      if (ledgerRows.isNotEmpty) {
        await txn.update(
          'reward_ledger',
          {
            'source_event_id': earliestId,
            'is_revoked': 0,
          },
          where: 'id = ?',
          whereArgs: [ledgerRows.first['id']],
        );
      } else {
        // Only grant if this date is still today
        if (localDate == clock.todayLocalDate()) {
          final active = await _getActiveMonsterTxn(txn);
          await _awardOrUnrevokeLedgerTxn(
            txn: txn,
            idempotencyKey: slotKey,
            sourceEventId: earliestId,
            rewardType: 'session_xp',
            value: mealType.baseXp,
            monsterId: active?.id,
            localDate: localDate,
            nowIso: nowIso,
          );
        }
      }
    }
  }

  Future<void> _reconcileFoodDiscoveryTxn({
    required Transaction txn,
    required String foodId,
    required bool allowNewDiscoveryBonus,
    required String localDate,
    required String? fallbackItemId,
    required String? activeMonsterId,
    required String nowIso,
  }) async {
    final remainingItems = await txn.rawQuery('''
      SELECT mi.id, ms.local_date
      FROM meal_items mi
      INNER JOIN meal_sessions ms ON ms.id = mi.session_id
      WHERE ms.profile_id = ? AND mi.food_id = ?
      ORDER BY ms.created_at ASC
      LIMIT 1
    ''', [defaultProfileId, foodId]);

    final discKey = 'discovery:$defaultProfileId:$foodId';

    if (remainingItems.isEmpty) {
      await txn.delete(
        'food_discoveries',
        where: 'profile_id = ? AND food_id = ?',
        whereArgs: [defaultProfileId, foodId],
      );
      await txn.update(
        'reward_ledger',
        {'is_revoked': 1},
        where: 'idempotency_key = ?',
        whereArgs: [discKey],
      );
    } else {
      final firstItemId = remainingItems.first['id'] as String;
      final existingDisc = await txn.query(
        'food_discoveries',
        where: 'profile_id = ? AND food_id = ?',
        whereArgs: [defaultProfileId, foodId],
      );
      if (existingDisc.isEmpty) {
        await txn.insert('food_discoveries', {
          'id': _uuid.v4(),
          'profile_id': defaultProfileId,
          'food_id': foodId,
          'first_meal_item_id': fallbackItemId ?? firstItemId,
          'discovered_date': localDate,
          'discovered_at': nowIso,
        });
        if (allowNewDiscoveryBonus && activeMonsterId != null) {
          final dailyDiscCount = await _countActiveDiscoveryBonusesTxn(txn, localDate);
          if (dailyDiscCount < GameRules.maxDailyDiscoveryBonuses) {
            await _awardOrUnrevokeLedgerTxn(
              txn: txn,
              idempotencyKey: discKey,
              sourceEventId: fallbackItemId ?? firstItemId,
              rewardType: 'discovery_xp',
              value: GameRules.discoveryBonusXp,
              monsterId: activeMonsterId,
              localDate: localDate,
              nowIso: nowIso,
            );
          }
        }
      }
    }
  }

  Future<void> _reconcileCustomDiscoveryTxn({
    required Transaction txn,
    required String customFoodId,
    required bool allowNewDiscoveryBonus,
    required String localDate,
    required String? activeMonsterId,
    required String nowIso,
  }) async {
    final remaining = await txn.rawQuery('''
      SELECT mi.id
      FROM meal_items mi
      INNER JOIN meal_sessions ms ON ms.id = mi.session_id
      INNER JOIN custom_foods cf ON cf.id = mi.custom_food_id
      WHERE ms.profile_id = ?
        AND mi.custom_food_id = ?
        AND cf.mapped_food_id IS NULL
      ORDER BY ms.created_at ASC
      LIMIT 1
    ''', [defaultProfileId, customFoodId]);

    final discKey = 'custom_discovery:$defaultProfileId:$customFoodId';
    if (remaining.isEmpty) {
      await txn.update(
        'reward_ledger',
        {'is_revoked': 1},
        where: 'idempotency_key = ?',
        whereArgs: [discKey],
      );
    } else if (allowNewDiscoveryBonus && activeMonsterId != null) {
      final dailyDiscCount =
          await _countActiveDiscoveryBonusesTxn(txn, localDate);
      if (dailyDiscCount < GameRules.maxDailyDiscoveryBonuses) {
        await _awardOrUnrevokeLedgerTxn(
          txn: txn,
          idempotencyKey: discKey,
          sourceEventId: remaining.first['id'] as String,
          rewardType: 'discovery_xp',
          value: GameRules.discoveryBonusXp,
          monsterId: activeMonsterId,
          localDate: localDate,
          nowIso: nowIso,
        );
      }
    }
  }

  Future<UserMonster?> _getActiveMonsterTxn(Transaction txn) async {
    final rows = await txn.query(
      'user_monsters',
      where: 'profile_id = ? AND is_active = 1',
      whereArgs: [defaultProfileId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return UserMonster.fromMap(rows.first);
  }

  Future<UserMonster> _recomputeMonsterXpTxn(
    Transaction txn,
    String userMonsterId,
    String nowIso,
  ) async {
    final sumRows = await txn.rawQuery('''
      SELECT COALESCE(SUM(value), 0) AS total_xp
      FROM reward_ledger
      WHERE monster_id = ? AND is_revoked = 0
        AND reward_type IN ('session_xp', 'discovery_xp', 'bonus_xp')
    ''', [userMonsterId]);

    final totalXp = (sumRows.first['total_xp'] as num?)?.toInt() ?? 0;
    final clampedXp = totalXp < 0 ? 0 : totalXp;
    final newLevel = GameRules.levelFromTotalXp(clampedXp);

    final mRows = await txn.query('user_monsters', where: 'id = ?', whereArgs: [userMonsterId]);
    final current = UserMonster.fromMap(mRows.first);

    final evolvedYoungAt = current.evolvedYoungAt ??
        (newLevel >= GameRules.youngEvolutionLevel ? DateTime.parse(nowIso) : null);
    final evolvedAdultAt = current.evolvedAdultAt ??
        (newLevel >= GameRules.adultEvolutionLevel ? DateTime.parse(nowIso) : null);

    await txn.update(
      'user_monsters',
      {
        'xp_total': clampedXp,
        'level': newLevel,
        'evolved_young_at': evolvedYoungAt?.toIso8601String(),
        'evolved_adult_at': evolvedAdultAt?.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [userMonsterId],
    );

    final updated = await txn.query('user_monsters', where: 'id = ?', whereArgs: [userMonsterId]);
    return UserMonster.fromMap(updated.first);
  }

  Future<void> _recomputeAllMonstersXpTxn(Transaction txn, String nowIso) async {
    final monsters = await txn.query(
      'user_monsters',
      columns: ['id'],
      where: 'profile_id = ?',
      whereArgs: [defaultProfileId],
    );
    for (final m in monsters) {
      await _recomputeMonsterXpTxn(txn, m['id'] as String, nowIso);
    }
  }

  Future<({bool progressed, MonsterEgg? egg})> _incrementActiveEggTxn({
    required Transaction txn,
    required String mealSessionId,
    required DateTime sessionCreatedAt,
  }) async {
    final activeEggs = await txn.query(
      'monster_eggs',
      where: "profile_id = ? AND status IN ('incubating', 'cracked')",
      whereArgs: [defaultProfileId],
      limit: 1,
    );
    if (activeEggs.isEmpty) return (progressed: false, egg: null);

    final egg = MonsterEgg.fromMap(activeEggs.first);
    if (egg.incubatedAt != null && sessionCreatedAt.isBefore(egg.incubatedAt!)) {
      return (progressed: false, egg: egg);
    }
    if (egg.hatchProgress >= GameRules.sessionsToHatch) {
      return (progressed: false, egg: egg);
    }

    // Insert unique event (egg_id, meal_session_id)
    final inserted = await txn.insert(
      'egg_incubation_events',
      {
        'id': _uuid.v4(),
        'egg_id': egg.id,
        'meal_session_id': mealSessionId,
        'created_at': sessionCreatedAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    if (inserted == 0) {
      return (progressed: false, egg: egg);
    }

    final updated = await _reconcileActiveEggProgressTxn(txn);
    return (progressed: true, egg: updated);
  }

  Future<MonsterEgg?> _reconcileActiveEggProgressTxn(Transaction txn) async {
    final activeEggs = await txn.query(
      'monster_eggs',
      where: "profile_id = ? AND status IN ('incubating', 'cracked', 'ready')",
      whereArgs: [defaultProfileId],
      limit: 1,
    );
    if (activeEggs.isEmpty) return null;

    final egg = MonsterEgg.fromMap(activeEggs.first);
    final count = Sqflite.firstIntValue(await txn.rawQuery('''
          SELECT COUNT(DISTINCT e.meal_session_id)
          FROM egg_incubation_events e
          INNER JOIN meal_sessions s ON s.id = e.meal_session_id
          WHERE e.egg_id = ? AND s.is_reward_eligible = 1
        ''', [egg.id])) ??
        0;

    final clamped = count.clamp(0, GameRules.sessionsToHatch);
    final newStatus = GameRules.eggStatusForProgress(
      progress: clamped,
      isIncubating: true,
    );

    await txn.update(
      'monster_eggs',
      {
        'hatch_progress': clamped,
        'status': newStatus.code,
      },
      where: 'id = ?',
      whereArgs: [egg.id],
    );

    final refreshed = await txn.query('monster_eggs', where: 'id = ?', whereArgs: [egg.id]);
    return MonsterEgg.fromMap(refreshed.first);
  }

  Future<({List<MonsterEgg> grantedEggs, List<String> starterBonusSpeciesIds})>
      _evaluateSpeciesUnlocksTxn(Transaction txn, String nowIso) async {
    final masteries = await _computeAllCategoryMasteriesTxn(txn);
    final speciesRows = await txn.query('monster_species', orderBy: 'sort_order ASC');
    final ownedRows = await txn.query(
      'user_monsters',
      where: 'profile_id = ?',
      whereArgs: [defaultProfileId],
    );
    final ownedBySpecies = {
      for (final r in ownedRows) r['species_id'] as String: UserMonster.fromMap(r),
    };
    final eggRows = await txn.query(
      'monster_eggs',
      where: 'profile_id = ?',
      whereArgs: [defaultProfileId],
    );
    final existingEggSpecies = eggRows.map((r) => r['species_id'] as String).toSet();

    final grantedEggs = <MonsterEgg>[];
    final starterBonusSpeciesIds = <String>[];
    final today = clock.todayLocalDate();

    for (final raw in speciesRows) {
      final sp = MonsterSpecies.fromMap(raw);
      final mastery = masteries[sp.categoryId];
      if (mastery == null) continue;

      final eligible = GameRules.meetsSpeciesUnlock(
        requiredUniqueFoods: sp.unlockUniqueFoods,
        requiredCategoryDays: sp.unlockCategoryDays,
        actualUniqueFoods: mastery.uniqueDiscoveredFoods,
        actualCategoryDays: mastery.categoryDays,
      );
      if (!eligible) continue;

      if (ownedBySpecies.containsKey(sp.id)) {
        // Section 17: Starter species reached its unlock milestone -> grant cosmetic mastery points once
        final owned = ownedBySpecies[sp.id]!;
        final key = 'starter_mastery:$defaultProfileId:${sp.id}';
        final existingLedger = await txn.query(
          'reward_ledger',
          where: 'idempotency_key = ?',
          whereArgs: [key],
        );
        if (existingLedger.isEmpty && sp.isStarter) {
          await txn.insert('reward_ledger', {
            'id': _uuid.v4(),
            'profile_id': defaultProfileId,
            'source_event_id': sp.id,
            'reward_type': 'starter_mastery',
            'value': GameRules.starterMasteryBonusPoints,
            'monster_id': owned.id,
            'local_date': today,
            'idempotency_key': key,
            'is_revoked': 0,
            'created_at': nowIso,
          });
          await txn.update(
            'user_monsters',
            {'mastery_points': owned.masteryPoints + GameRules.starterMasteryBonusPoints},
            where: 'id = ?',
            whereArgs: [owned.id],
          );
          starterBonusSpeciesIds.add(sp.id);
        }
        continue;
      }

      if (existingEggSpecies.contains(sp.id)) continue;

      // Grant egg once per species
      final eggId = _uuid.v4();
      await txn.insert('monster_eggs', {
        'id': eggId,
        'profile_id': defaultProfileId,
        'species_id': sp.id,
        'element_id': sp.element.code,
        'status': EggStatus.queued.code,
        'hatch_progress': 0,
        'granted_at': nowIso,
        'incubated_at': null,
        'hatched_at': null,
      });

      final newEgg = MonsterEgg(
        id: eggId,
        profileId: defaultProfileId,
        speciesId: sp.id,
        element: sp.element,
        status: EggStatus.queued,
        hatchProgress: 0,
        grantedAt: DateTime.parse(nowIso),
      );
      grantedEggs.add(newEgg);
      existingEggSpecies.add(sp.id);
    }

    return (
      grantedEggs: grantedEggs,
      starterBonusSpeciesIds: starterBonusSpeciesIds,
    );
  }

  Future<Map<String, CategoryMastery>> _computeAllCategoryMasteriesTxn(
    DatabaseExecutor db,
  ) async {
    final cats = await db.query('food_categories');
    final totalFoodsRows = await db.rawQuery(
      "SELECT category_id, COUNT(*) AS cnt FROM foods WHERE status = 'active' GROUP BY category_id",
    );
    final totalByCat = {
      for (final r in totalFoodsRows) r['category_id'] as String: (r['cnt'] as num).toInt(),
    };

    final discRows = await db.rawQuery('''
      SELECT f.category_id, COUNT(DISTINCT fd.food_id) AS cnt
      FROM food_discoveries fd
      INNER JOIN foods f ON f.id = fd.food_id
      WHERE fd.profile_id = ?
      GROUP BY f.category_id
    ''', [defaultProfileId]);
    final discByCat = {
      for (final r in discRows) r['category_id'] as String: (r['cnt'] as num).toInt(),
    };

    // Standalone unmapped custom foods logged at least once count as personal FoodDex discoveries!
    final customDiscRows = await db.rawQuery('''
      SELECT cf.category_id, COUNT(DISTINCT cf.id) AS cnt
      FROM custom_foods cf
      INNER JOIN meal_items mi ON mi.custom_food_id = cf.id
      INNER JOIN meal_sessions ms ON ms.id = mi.session_id
      WHERE cf.profile_id = ?
        AND ms.profile_id = ?
        AND cf.mapped_food_id IS NULL
      GROUP BY cf.category_id
    ''', [defaultProfileId, defaultProfileId]);
    for (final r in customDiscRows) {
      final cid = r['category_id'] as String;
      discByCat[cid] = (discByCat[cid] ?? 0) + (r['cnt'] as num).toInt();
    }

    // Category days: distinct calendar dates with >=1 reward-eligible session in that category (master OR custom)
    final daysRows = await db.rawQuery('''
      SELECT COALESCE(f.category_id, cf.category_id) AS category_id,
             COUNT(DISTINCT ms.local_date) AS cnt
      FROM meal_sessions ms
      INNER JOIN meal_items mi ON mi.session_id = ms.id
      LEFT JOIN foods f ON f.id = mi.food_id
      LEFT JOIN custom_foods cf ON cf.id = mi.custom_food_id
      WHERE ms.profile_id = ? AND ms.is_reward_eligible = 1
      GROUP BY COALESCE(f.category_id, cf.category_id)
    ''', [defaultProfileId]);
    final daysByCat = {
      for (final r in daysRows)
        if (r['category_id'] != null) r['category_id'] as String: (r['cnt'] as num).toInt(),
    };

    // Distinct places with place_id in that category (master OR custom)
    final placesRows = await db.rawQuery('''
      SELECT COALESCE(f.category_id, cf.category_id) AS category_id,
             COUNT(DISTINCT ms.place_id) AS cnt
      FROM meal_sessions ms
      INNER JOIN meal_items mi ON mi.session_id = ms.id
      LEFT JOIN foods f ON f.id = mi.food_id
      LEFT JOIN custom_foods cf ON cf.id = mi.custom_food_id
      WHERE ms.profile_id = ? AND ms.place_id IS NOT NULL
      GROUP BY COALESCE(f.category_id, cf.category_id)
    ''', [defaultProfileId]);
    final placesByCat = {
      for (final r in placesRows)
        if (r['category_id'] != null) r['category_id'] as String: (r['cnt'] as num).toInt(),
    };

    // Total logs per category (including custom foods belonging to that category)
    final logsRows = await db.rawQuery('''
      SELECT COALESCE(f.category_id, cf.category_id) AS category_id, COUNT(*) AS cnt
      FROM meal_items mi
      INNER JOIN meal_sessions ms ON ms.id = mi.session_id
      LEFT JOIN foods f ON f.id = mi.food_id
      LEFT JOIN custom_foods cf ON cf.id = mi.custom_food_id
      WHERE ms.profile_id = ?
      GROUP BY COALESCE(f.category_id, cf.category_id)
    ''', [defaultProfileId]);
    final logsByCat = {
      for (final r in logsRows)
        if (r['category_id'] != null) r['category_id'] as String: (r['cnt'] as num).toInt(),
    };

    final result = <String, CategoryMastery>{};
    for (final c in cats) {
      final catId = c['id'] as String;
      final unique = discByCat[catId] ?? 0;
      final days = daysByCat[catId] ?? 0;
      final places = placesByCat[catId] ?? 0;
      final grade = GameRules.calculateGrade(
        uniqueFoods: unique,
        distinctPlaces: places,
        categoryDays: days,
      );
      result[catId] = CategoryMastery(
        categoryId: catId,
        totalMasterFoods: totalByCat[catId] ?? 0,
        uniqueDiscoveredFoods: unique,
        categoryDays: days,
        distinctPlaces: places,
        totalLogs: logsByCat[catId] ?? 0,
        grade: grade,
      );
    }
    return result;
  }

  Future<Map<String, CategoryMastery>> getAllCategoryMasteries() async {
    final db = await database;
    return _computeAllCategoryMasteriesTxn(db);
  }

  // ============================================================
  // QUERIES: MEAL SESSIONS, DAILY XP, STATS
  // ============================================================

  Future<DailyXpStatus> getDailyXpStatus([String? localDate]) async {
    final db = await database;
    final date = localDate ?? clock.todayLocalDate();

    final rows = await db.query(
      'reward_ledger',
      where: 'profile_id = ? AND local_date = ? AND is_revoked = 0',
      whereArgs: [defaultProfileId, date],
    );

    final claimedSlots = <MealType>{};
    int discBonuses = 0;
    int totalXp = 0;

    for (final r in rows) {
      final type = r['reward_type'] as String;
      final val = (r['value'] as num).toInt();
      if (type == 'session_xp') {
        totalXp += val;
        final key = r['idempotency_key'] as String;
        final mealCode = key.split(':').last;
        claimedSlots.add(MealType.fromCode(mealCode));
      } else if (type == 'discovery_xp') {
        totalXp += val;
        discBonuses++;
      }
    }

    return DailyXpStatus(
      localDate: date,
      claimedSlots: claimedSlots,
      discoveryBonusesClaimed: discBonuses,
      totalXpToday: totalXp,
    );
  }

  Future<List<MealSessionRecord>> getMealSessions({
    int? limit,
    String? placeId,
    String? categoryId,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    final db = await database;
    final whereParts = <String>['ms.profile_id = ?'];
    final args = <Object?>[defaultProfileId];

    if (placeId != null) {
      whereParts.add('ms.place_id = ?');
      args.add(placeId);
    }
    if (fromDate != null) {
      whereParts.add('ms.local_date >= ?');
      args.add(AppClock.formatLocalDate(fromDate));
    }
    if (toDate != null) {
      whereParts.add('ms.local_date <= ?');
      args.add(AppClock.formatLocalDate(toDate));
    }
    if (categoryId != null) {
      whereParts.add('''
        EXISTS (
          SELECT 1 FROM meal_items mi
          LEFT JOIN foods f ON f.id = mi.food_id
          LEFT JOIN custom_foods cf ON cf.id = mi.custom_food_id
          WHERE mi.session_id = ms.id
            AND COALESCE(f.category_id, cf.category_id) = ?
        )
      ''');
      args.add(categoryId);
    }

    final limitSql = limit != null ? 'LIMIT $limit' : '';
    final sessionRows = await db.rawQuery('''
      SELECT ms.*
      FROM meal_sessions ms
      WHERE ${whereParts.join(' AND ')}
      ORDER BY ms.occurred_at DESC, ms.created_at DESC
      $limitSql
    ''', args);

    if (sessionRows.isEmpty) return [];

    final sessionIds = sessionRows.map((r) => r['id'] as String).toList();
    final placeIds = sessionRows
        .map((r) => r['place_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();

    final placeMap = <String, PlaceModel>{};
    if (placeIds.isNotEmpty) {
      final pHolders = List.filled(placeIds.length, '?').join(',');
      final placeRows = await db.rawQuery(
        'SELECT * FROM places WHERE id IN ($pHolders)',
        placeIds,
      );
      for (final pr in placeRows) {
        final pm = PlaceModel.fromMap(pr);
        placeMap[pm.id] = pm;
      }
    }

    final sHolders = List.filled(sessionIds.length, '?').join(',');
    final itemRows = await db.rawQuery('''
      SELECT mi.*,
        COALESCE(f.canonical_name, cf.name, 'Makanan') AS display_name,
        COALESCE(f.category_id, cf.category_id, 'nasi_serealia') AS resolved_category_id
      FROM meal_items mi
      LEFT JOIN foods f ON f.id = mi.food_id
      LEFT JOIN custom_foods cf ON cf.id = mi.custom_food_id
      WHERE mi.session_id IN ($sHolders)
      ORDER BY mi.created_at ASC
    ''', sessionIds);

    final itemsBySession = <String, List<MealItemRecord>>{};
    for (final ir in itemRows) {
      final sid = ir['session_id'] as String;
      itemsBySession.putIfAbsent(sid, () => []).add(
            MealItemRecord(
              id: ir['id'] as String,
              sessionId: sid,
              foodId: ir['food_id'] as String?,
              customFoodId: ir['custom_food_id'] as String?,
              displayName: ir['display_name'] as String,
              categoryId: ir['resolved_category_id'] as String,
              priceMinor: (ir['price_minor'] as num?)?.toInt(),
              currency: (ir['currency'] as String?) ?? 'IDR',
              quantity: (ir['quantity'] as num?)?.toInt() ?? 1,
              rating: (ir['rating'] as num?)?.toInt(),
              photoPath: ir['photo_path'] as String?,
              description: ir['description'] as String?,
              createdAt: DateTime.parse(ir['created_at'] as String),
            ),
          );
    }

    return sessionRows.map((sr) {
      final sid = sr['id'] as String;
      final pid = sr['place_id'] as String?;
      return MealSessionRecord(
        id: sid,
        profileId: sr['profile_id'] as String,
        occurredAt: DateTime.parse(sr['occurred_at'] as String),
        localDate: sr['local_date'] as String,
        mealType: MealType.fromCode(sr['meal_type'] as String),
        placeId: pid,
        placeMode: PlaceMode.fromCode((sr['place_mode'] as String?) ?? 'none'),
        place: pid != null ? placeMap[pid] : null,
        notes: sr['notes'] as String?,
        isRewardEligible: (sr['is_reward_eligible'] as int? ?? 1) == 1,
        createdAt: DateTime.parse(sr['created_at'] as String),
        items: itemsBySession[sid] ?? const [],
      );
    }).toList();
  }

  Future<MealSessionRecord?> getMealSessionById(String sessionId) async {
    final sessions = await getMealSessions();
    for (final s in sessions) {
      if (s.id == sessionId) return s;
    }
    return null;
  }

  Future<List<MealSessionRecord>> getSessionsForFood(String foodId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT ms.id
      FROM meal_sessions ms
      INNER JOIN meal_items mi ON mi.session_id = ms.id
      WHERE ms.profile_id = ? AND mi.food_id = ?
      ORDER BY ms.occurred_at DESC
    ''', [defaultProfileId, foodId]);
    final ids = rows.map((r) => r['id'] as String).toSet();
    if (ids.isEmpty) return [];
    final all = await getMealSessions();
    return all.where((s) => ids.contains(s.id)).toList();
  }

  Future<FoodPriceStats> getFoodPriceStats(String foodId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT mi.price_minor
      FROM meal_items mi
      INNER JOIN meal_sessions ms ON ms.id = mi.session_id
      WHERE ms.profile_id = ? AND mi.food_id = ?
      ORDER BY mi.price_minor ASC
    ''', [defaultProfileId, foodId]);

    final totalLogs = rows.length;
    final prices = rows
        .map((r) => (r['price_minor'] as num?)?.toInt())
        .whereType<int>()
        .toList()
      ..sort();

    if (prices.isEmpty) {
      return FoodPriceStats(totalLogs: totalLogs, pricedLogs: 0);
    }

    final mid = prices.length ~/ 2;
    final median = prices.length.isOdd
        ? prices[mid]
        : ((prices[mid - 1] + prices[mid]) / 2).round();

    return FoodPriceStats(
      totalLogs: totalLogs,
      pricedLogs: prices.length,
      medianPriceMinor: median,
      minPriceMinor: prices.first,
      maxPriceMinor: prices.last,
    );
  }

  // ============================================================
  // MONSTERS, BOND & EGGS
  // ============================================================

  Future<List<MonsterWithSpecies>> getAllMonstersWithStatus() async {
    final db = await database;
    final speciesRows = await db.query('monster_species', orderBy: 'sort_order ASC');
    final ownedRows = await db.query(
      'user_monsters',
      where: 'profile_id = ?',
      whereArgs: [defaultProfileId],
    );
    final eggRows = await db.query(
      'monster_eggs',
      where: 'profile_id = ?',
      whereArgs: [defaultProfileId],
    );
    final masteries = await _computeAllCategoryMasteriesTxn(db);

    final ownedBySpecies = {
      for (final r in ownedRows) r['species_id'] as String: UserMonster.fromMap(r),
    };
    final eggBySpecies = {
      for (final r in eggRows) r['species_id'] as String: MonsterEgg.fromMap(r),
    };

    return speciesRows.map((raw) {
      final sp = MonsterSpecies.fromMap(raw);
      return MonsterWithSpecies(
        species: sp,
        owned: ownedBySpecies[sp.id],
        categoryMastery: masteries[sp.categoryId],
        egg: eggBySpecies[sp.id],
      );
    }).toList();
  }

  Future<MonsterWithSpecies?> getActiveMonster() async {
    final all = await getAllMonstersWithStatus();
    for (final m in all) {
      if (m.owned?.isActive == true) return m;
    }
    for (final m in all) {
      if (m.owned != null) return m;
    }
    return null;
  }

  Future<void> setActiveMonster(String userMonsterId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'user_monsters',
        {'is_active': 0},
        where: 'profile_id = ?',
        whereArgs: [defaultProfileId],
      );
      await txn.update(
        'user_monsters',
        {'is_active': 1},
        where: 'id = ? AND profile_id = ?',
        whereArgs: [userMonsterId, defaultProfileId],
      );
    });
    _notify();
  }

  /// Section 8.4: Cosmetic Bond tap with cooldown, never decreases.
  Future<({bool gained, int newBond})> tapMonsterBond(String userMonsterId) async {
    final db = await database;
    final now = clock.now();
    final rows = await db.query(
      'user_monsters',
      where: 'id = ? AND profile_id = ?',
      whereArgs: [userMonsterId, defaultProfileId],
    );
    if (rows.isEmpty) return (gained: false, newBond: 0);
    final monster = UserMonster.fromMap(rows.first);
    if (!monster.canTapBond(now)) {
      return (gained: false, newBond: monster.bond);
    }
    final nextBond = (monster.bond + GameRules.bondTapGain).clamp(0, GameRules.maxBond);
    await db.update(
      'user_monsters',
      {
        'bond': nextBond,
        'last_bond_at': now.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [userMonsterId],
    );
    _notify();
    return (gained: true, newBond: nextBond);
  }

  Future<List<MonsterEgg>> getAllEggs() async {
    final db = await database;
    final rows = await db.query(
      'monster_eggs',
      where: 'profile_id = ?',
      whereArgs: [defaultProfileId],
      orderBy: 'granted_at ASC',
    );
    return rows.map(MonsterEgg.fromMap).toList();
  }

  Future<MonsterEgg?> getActiveIncubatingEgg() async {
    final eggs = await getAllEggs();
    for (final e in eggs) {
      if (e.status.isActiveInIncubator) return e;
    }
    return null;
  }

  /// Moves a queued egg into the single active incubator slot.
  Future<bool> startEggIncubation(String eggId) async {
    final db = await database;
    final nowIso = clock.now().toIso8601String();
    bool started = false;

    await db.transaction((txn) async {
      final active = await txn.query(
        'monster_eggs',
        where: "profile_id = ? AND status IN ('incubating', 'cracked', 'ready')",
        whereArgs: [defaultProfileId],
      );
      if (active.isNotEmpty) return;

      final target = await txn.query(
        'monster_eggs',
        where: "id = ? AND profile_id = ? AND status = 'queued'",
        whereArgs: [eggId, defaultProfileId],
      );
      if (target.isEmpty) return;

      await txn.update(
        'monster_eggs',
        {
          'status': EggStatus.incubating.code,
          'hatch_progress': 0,
          'incubated_at': nowIso,
        },
        where: 'id = ?',
        whereArgs: [eggId],
      );
      started = true;
    });

    if (started) _notify();
    return started;
  }

  /// Atomically hatches a READY (3/3) egg into a Level 1 Baby user_monster.
  /// Crash-safe: commits unlocked monster before animation finishes so reward is never lost.
  Future<({UserMonster monster, MonsterSpecies species})?> hatchEgg(String eggId) async {
    final db = await database;
    final nowIso = clock.now().toIso8601String();
    UserMonster? unlocked;
    MonsterSpecies? species;

    await db.transaction((txn) async {
      final eggRows = await txn.query(
        'monster_eggs',
        where: 'id = ? AND profile_id = ?',
        whereArgs: [eggId, defaultProfileId],
      );
      if (eggRows.isEmpty) return;
      final egg = MonsterEgg.fromMap(eggRows.first);

      if (egg.status != EggStatus.ready && egg.status != EggStatus.hatched) {
        return;
      }

      final spRows = await txn.query(
        'monster_species',
        where: 'id = ?',
        whereArgs: [egg.speciesId],
      );
      if (spRows.isEmpty) return;
      species = MonsterSpecies.fromMap(spRows.first);

      if (egg.status == EggStatus.ready) {
        await txn.update(
          'monster_eggs',
          {
            'status': EggStatus.hatched.code,
            'hatched_at': nowIso,
          },
          where: 'id = ?',
          whereArgs: [eggId],
        );
      }

      final existingOwned = await txn.query(
        'user_monsters',
        where: 'profile_id = ? AND species_id = ?',
        whereArgs: [defaultProfileId, egg.speciesId],
      );
      if (existingOwned.isEmpty) {
        final monsterId = _uuid.v4();
        await txn.insert('user_monsters', {
          'id': monsterId,
          'profile_id': defaultProfileId,
          'species_id': egg.speciesId,
          'level': 1,
          'xp_total': 0,
          'bond': 0,
          'last_bond_at': null,
          'is_active': 0,
          'unlocked_at': nowIso,
          'evolved_young_at': null,
          'evolved_adult_at': null,
          'mastery_points': 0,
        });
        final mRow = await txn.query('user_monsters', where: 'id = ?', whereArgs: [monsterId]);
        unlocked = UserMonster.fromMap(mRow.first);
      } else {
        unlocked = UserMonster.fromMap(existingOwned.first);
      }
    });

    if (unlocked == null || species == null) return null;
    _notify();
    return (monster: unlocked!, species: species!);
  }

  // ============================================================
  // PERSONAL STATS (LOCAL-ONLY KPIs — SECTION 19.2)
  // ============================================================

  Future<UserPersonalStats> getPersonalStats() async {
    final db = await database;
    final totalSessions = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM meal_sessions WHERE profile_id = ?',
          [defaultProfileId],
        )) ??
        0;
    final totalItems = Sqflite.firstIntValue(await db.rawQuery('''
          SELECT COUNT(*) FROM meal_items mi
          INNER JOIN meal_sessions ms ON ms.id = mi.session_id
          WHERE ms.profile_id = ?
        ''', [defaultProfileId])) ??
        0;
    final masterDiscovered = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM food_discoveries WHERE profile_id = ?',
          [defaultProfileId],
        )) ??
        0;
    final customDiscovered = Sqflite.firstIntValue(await db.rawQuery('''
          SELECT COUNT(DISTINCT cf.id)
          FROM custom_foods cf
          INNER JOIN meal_items mi ON mi.custom_food_id = cf.id
          INNER JOIN meal_sessions ms ON ms.id = mi.session_id
          WHERE cf.profile_id = ? AND ms.profile_id = ? AND cf.mapped_food_id IS NULL
        ''', [defaultProfileId, defaultProfileId])) ??
        0;
    final uniqueDiscovered = masterDiscovered + customDiscovered;
    final totalMasterFoods = Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(*) FROM foods WHERE status = 'active'",
        )) ??
        0;
    final placesVisited = Sqflite.firstIntValue(await db.rawQuery('''
          SELECT COUNT(DISTINCT place_id) FROM meal_sessions
          WHERE profile_id = ? AND place_id IS NOT NULL
        ''', [defaultProfileId])) ??
        0;

    final masteries = await _computeAllCategoryMasteriesTxn(db);
    final categories = await getCategories();
    final catNames = {for (final c in categories) c.id: c.name};

    String? topCatName;
    int topCatCount = 0;
    for (final m in masteries.values) {
      if (m.uniqueDiscoveredFoods > topCatCount) {
        topCatCount = m.uniqueDiscoveredFoods;
        topCatName = catNames[m.categoryId];
      }
    }

    final ownedMonsters = await db.query(
      'user_monsters',
      where: 'profile_id = ?',
      whereArgs: [defaultProfileId],
    );
    int baby = 0, young = 0, adult = 0;
    for (final r in ownedMonsters) {
      final phase = GameRules.phaseForLevel((r['level'] as int?) ?? 1);
      if (phase == EvolutionPhase.baby) baby++;
      if (phase == EvolutionPhase.young) young++;
      if (phase == EvolutionPhase.adult) adult++;
    }

    final totalSpecies = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM monster_species'),
        ) ??
        20;

    final spendRows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN mi.price_minor IS NOT NULL THEN mi.price_minor * mi.quantity ELSE 0 END), 0) AS total_spend,
        SUM(CASE WHEN mi.price_minor IS NOT NULL THEN 1 ELSE 0 END) AS priced_cnt,
        SUM(CASE WHEN mi.price_minor IS NULL THEN 1 ELSE 0 END) AS unpriced_cnt
      FROM meal_items mi
      INNER JOIN meal_sessions ms ON ms.id = mi.session_id
      WHERE ms.profile_id = ?
    ''', [defaultProfileId]);

    final totalSpend = (spendRows.first['total_spend'] as num?)?.toInt() ?? 0;
    final pricedCnt = (spendRows.first['priced_cnt'] as num?)?.toInt() ?? 0;
    final unpricedCnt = (spendRows.first['unpriced_cnt'] as num?)?.toInt() ?? 0;

    // Weekly average since first session
    double avgPerWeek = 0;
    if (totalSessions > 0) {
      final firstRows = await db.rawQuery(
        'SELECT MIN(occurred_at) AS first_occ FROM meal_sessions WHERE profile_id = ?',
        [defaultProfileId],
      );
      final firstStr = firstRows.first['first_occ'] as String?;
      if (firstStr != null) {
        final firstDt = DateTime.parse(firstStr);
        final daysSpan = clock.now().difference(firstDt).inDays.clamp(1, 36500);
        final weeks = (daysSpan / 7.0).clamp(1.0, 5200.0);
        avgPerWeek = totalSessions / weeks;
      }
    }

    return UserPersonalStats(
      totalSessions: totalSessions,
      totalItemsLogged: totalItems,
      uniqueFoodsDiscovered: uniqueDiscovered,
      totalMasterFoods: totalMasterFoods,
      mostDiverseCategoryName: topCatName,
      mostDiverseCategoryCount: topCatCount,
      placesVisitedCount: placesVisited,
      monstersUnlocked: ownedMonsters.length,
      totalSpecies: totalSpecies,
      babyCount: baby,
      youngCount: young,
      adultCount: adult,
      avgSessionsPerWeek: avgPerWeek,
      totalSpendMinor: totalSpend,
      pricedItemsCount: pricedCnt,
      unpricedItemsCount: unpricedCnt,
    );
  }

  /// Explicitly resets all personal journal/monster/egg/place data while keeping
  /// the curated master catalog intact.
  Future<void> resetAllUserData() async {
    final db = await database;
    final nowIso = clock.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.delete('egg_incubation_events');
      await txn.delete('monster_eggs');
      await txn.delete('user_monsters');
      await txn.delete('reward_ledger');
      await txn.delete('food_discoveries');
      await txn.delete('meal_items');
      await txn.delete('meal_sessions');
      await txn.delete('custom_foods');
      await txn.delete('places');
      await txn.update(
        'profiles',
        {
          'display_name': '',
          'starter_selected': 0,
          'starter_species_id': null,
          'updated_at': nowIso,
        },
        where: 'id = ?',
        whereArgs: [defaultProfileId],
      );
      await txn.insert(
        'app_settings',
        {'key': 'tutorial_completed', 'value': 'false', 'updated_at': nowIso},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete('app_settings', where: "key = 'last_recorded_local_date'");
    });
    _notify();
  }
}
