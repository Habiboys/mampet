import 'enums.dart';
import 'game_rules.dart';

class UserProfile {
  final String id;
  final String displayName;
  final String locale;
  final String timezone;
  final String currency;
  final bool starterSelected;
  final String? starterSpeciesId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserProfile({
    required this.id,
    required this.displayName,
    required this.locale,
    required this.timezone,
    required this.currency,
    required this.starterSelected,
    this.starterSpeciesId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserProfile.fromMap(Map<String, Object?> m) {
    return UserProfile(
      id: m['id'] as String,
      displayName: (m['display_name'] as String?) ?? '',
      locale: (m['locale'] as String?) ?? 'id_ID',
      timezone: (m['timezone'] as String?) ?? 'Asia/Jakarta',
      currency: (m['currency'] as String?) ?? 'IDR',
      starterSelected: (m['starter_selected'] as int? ?? 0) == 1,
      starterSpeciesId: m['starter_species_id'] as String?,
      createdAt: DateTime.parse(m['created_at'] as String),
      updatedAt: DateTime.parse(m['updated_at'] as String),
    );
  }
}

class FoodCategory {
  final String id;
  final String slug;
  final String name;
  final String icon;
  final String colorHex;
  final int sortOrder;

  const FoodCategory({
    required this.id,
    required this.slug,
    required this.name,
    required this.icon,
    required this.colorHex,
    required this.sortOrder,
  });

  factory FoodCategory.fromMap(Map<String, Object?> m) {
    return FoodCategory(
      id: m['id'] as String,
      slug: m['slug'] as String,
      name: m['name'] as String,
      icon: (m['icon'] as String?) ?? 'restaurant',
      colorHex: (m['color_hex'] as String?) ?? '#E86A33',
      sortOrder: (m['sort_order'] as int?) ?? 0,
    );
  }
}

class MasterFood {
  final String id;
  final String categoryId;
  final String canonicalName;
  final String normalizedName;
  final String locale;
  final String description;
  final String originRegion;
  final String status;
  final List<String> aliases;

  const MasterFood({
    required this.id,
    required this.categoryId,
    required this.canonicalName,
    required this.normalizedName,
    required this.locale,
    required this.description,
    required this.originRegion,
    required this.status,
    this.aliases = const [],
  });

  factory MasterFood.fromMap(
    Map<String, Object?> m, {
    List<String> aliases = const [],
  }) {
    return MasterFood(
      id: m['id'] as String,
      categoryId: m['category_id'] as String,
      canonicalName: m['canonical_name'] as String,
      normalizedName: m['normalized_name'] as String,
      locale: (m['locale'] as String?) ?? 'id_ID',
      description: (m['description'] as String?) ?? '',
      originRegion: (m['origin_region'] as String?) ?? '',
      status: (m['status'] as String?) ?? 'active',
      aliases: aliases,
    );
  }
}

class CustomFood {
  final String id;
  final String profileId;
  final String name;
  final String normalizedName;
  final String categoryId;
  final String? mappedFoodId;
  final DateTime createdAt;

  const CustomFood({
    required this.id,
    required this.profileId,
    required this.name,
    required this.normalizedName,
    required this.categoryId,
    this.mappedFoodId,
    required this.createdAt,
  });

  factory CustomFood.fromMap(Map<String, Object?> m) {
    return CustomFood(
      id: m['id'] as String,
      profileId: m['profile_id'] as String,
      name: m['name'] as String,
      normalizedName: m['normalized_name'] as String,
      categoryId: m['category_id'] as String,
      mappedFoodId: m['mapped_food_id'] as String?,
      createdAt: DateTime.parse(m['created_at'] as String),
    );
  }
}

class PlaceModel {
  final String id;
  final String profileId;
  final String displayName;
  final double? lat;
  final double? lng;
  final String? address;
  final String source;
  final String privacy;
  final DateTime createdAt;

  const PlaceModel({
    required this.id,
    required this.profileId,
    required this.displayName,
    this.lat,
    this.lng,
    this.address,
    this.source = 'manual',
    this.privacy = 'private',
    required this.createdAt,
  });

  bool get hasCoordinates => lat != null && lng != null;

  factory PlaceModel.fromMap(Map<String, Object?> m) {
    return PlaceModel(
      id: m['id'] as String,
      profileId: m['profile_id'] as String,
      displayName: m['display_name'] as String,
      lat: (m['lat'] as num?)?.toDouble(),
      lng: (m['lng'] as num?)?.toDouble(),
      address: m['address'] as String?,
      source: (m['source'] as String?) ?? 'manual',
      privacy: (m['privacy'] as String?) ?? 'private',
      createdAt: DateTime.parse(m['created_at'] as String),
    );
  }
}

class MealItemDraft {
  final String? id;
  final String? foodId;
  final String? customFoodId;
  final String displayName;
  final String categoryId;
  final bool isCustom;
  final int? priceMinor;
  final int quantity;
  final int? rating;
  final String? photoPath;
  final String? description;

  const MealItemDraft({
    this.id,
    this.foodId,
    this.customFoodId,
    required this.displayName,
    required this.categoryId,
    this.isCustom = false,
    this.priceMinor,
    this.quantity = 1,
    this.rating,
    this.photoPath,
    this.description,
  });

  MealItemDraft copyWith({
    String? id,
    String? foodId,
    String? customFoodId,
    String? displayName,
    String? categoryId,
    bool? isCustom,
    int? priceMinor,
    bool clearPrice = false,
    int? quantity,
    int? rating,
    bool clearRating = false,
    String? photoPath,
    bool clearPhoto = false,
    String? description,
  }) {
    return MealItemDraft(
      id: id ?? this.id,
      foodId: foodId ?? this.foodId,
      customFoodId: customFoodId ?? this.customFoodId,
      displayName: displayName ?? this.displayName,
      categoryId: categoryId ?? this.categoryId,
      isCustom: isCustom ?? this.isCustom,
      priceMinor: clearPrice ? null : (priceMinor ?? this.priceMinor),
      quantity: quantity ?? this.quantity,
      rating: clearRating ? null : (rating ?? this.rating),
      photoPath: clearPhoto ? null : (photoPath ?? this.photoPath),
      description: description ?? this.description,
    );
  }
}

class MealItemRecord {
  final String id;
  final String sessionId;
  final String? foodId;
  final String? customFoodId;
  final String displayName;
  final String categoryId;
  final int? priceMinor;
  final String currency;
  final int quantity;
  final int? rating;
  final String? photoPath;
  final String? description;
  final DateTime createdAt;

  const MealItemRecord({
    required this.id,
    required this.sessionId,
    this.foodId,
    this.customFoodId,
    required this.displayName,
    required this.categoryId,
    this.priceMinor,
    this.currency = 'IDR',
    this.quantity = 1,
    this.rating,
    this.photoPath,
    this.description,
    required this.createdAt,
  });

  bool get isMasterFood => foodId != null;

  MealItemDraft toDraft() => MealItemDraft(
        id: id,
        foodId: foodId,
        customFoodId: customFoodId,
        displayName: displayName,
        categoryId: categoryId,
        isCustom: customFoodId != null,
        priceMinor: priceMinor,
        quantity: quantity,
        rating: rating,
        photoPath: photoPath,
        description: description,
      );
}

class MealSessionRecord {
  final String id;
  final String profileId;
  final DateTime occurredAt;
  final String localDate;
  final MealType mealType;
  final String? placeId;
  final PlaceMode placeMode;
  final PlaceModel? place;
  final String? notes;
  final bool isRewardEligible;
  final DateTime createdAt;
  final List<MealItemRecord> items;

  const MealSessionRecord({
    required this.id,
    required this.profileId,
    required this.occurredAt,
    required this.localDate,
    required this.mealType,
    this.placeId,
    required this.placeMode,
    this.place,
    this.notes,
    required this.isRewardEligible,
    required this.createdAt,
    this.items = const [],
  });

  int? get totalPriceMinor {
    final priced = items.where((e) => e.priceMinor != null).toList();
    if (priced.isEmpty) return null;
    return priced.fold<int>(0, (sum, e) => sum + (e.priceMinor! * e.quantity));
  }

  bool get hasPartialMissingPrices {
    final pricedCount = items.where((e) => e.priceMinor != null).length;
    return pricedCount > 0 && pricedCount < items.length;
  }

  String get placeDisplayLabel {
    if (place != null) return place!.displayName;
    if (placeMode == PlaceMode.home) return 'Rumah (tanpa pin)';
    return 'Tanpa lokasi';
  }
}

class MonsterSpecies {
  final String id;
  final String slug;
  final String displayName;
  final String categoryId;
  final MonsterElement element;
  final MonsterRarity rarity;
  final String flavorText;
  final int unlockUniqueFoods;
  final int unlockCategoryDays;
  final bool isStarter;
  final String assetBaby;
  final String assetYoung;
  final String assetAdult;
  final int sortOrder;

  const MonsterSpecies({
    required this.id,
    required this.slug,
    required this.displayName,
    required this.categoryId,
    required this.element,
    required this.rarity,
    required this.flavorText,
    required this.unlockUniqueFoods,
    required this.unlockCategoryDays,
    required this.isStarter,
    required this.assetBaby,
    required this.assetYoung,
    required this.assetAdult,
    required this.sortOrder,
  });

  String assetForPhase(EvolutionPhase phase) {
    switch (phase) {
      case EvolutionPhase.baby:
        return assetBaby;
      case EvolutionPhase.young:
        return assetYoung;
      case EvolutionPhase.adult:
        return assetAdult;
    }
  }

  factory MonsterSpecies.fromMap(Map<String, Object?> m) {
    return MonsterSpecies(
      id: m['id'] as String,
      slug: m['slug'] as String,
      displayName: m['display_name'] as String,
      categoryId: m['category_id'] as String,
      element: MonsterElement.fromCode(m['element_id'] as String),
      rarity: MonsterRarity.fromCode(m['rarity_id'] as String),
      flavorText: (m['flavor_text'] as String?) ?? '',
      unlockUniqueFoods: (m['unlock_unique_foods'] as int?) ?? 3,
      unlockCategoryDays: (m['unlock_category_days'] as int?) ?? 2,
      isStarter: (m['is_starter'] as int? ?? 0) == 1,
      assetBaby: m['asset_baby'] as String,
      assetYoung: m['asset_young'] as String,
      assetAdult: m['asset_adult'] as String,
      sortOrder: (m['sort_order'] as int?) ?? 0,
    );
  }
}

class UserMonster {
  final String id;
  final String profileId;
  final String speciesId;
  final int level;
  final int xpTotal;
  final int bond;
  final DateTime? lastBondAt;
  final bool isActive;
  final DateTime unlockedAt;
  final DateTime? evolvedYoungAt;
  final DateTime? evolvedAdultAt;
  final int masteryPoints;

  const UserMonster({
    required this.id,
    required this.profileId,
    required this.speciesId,
    required this.level,
    required this.xpTotal,
    required this.bond,
    this.lastBondAt,
    required this.isActive,
    required this.unlockedAt,
    this.evolvedYoungAt,
    this.evolvedAdultAt,
    this.masteryPoints = 0,
  });

  EvolutionPhase get phase => GameRules.phaseForLevel(level);

  bool canTapBond(DateTime now) {
    if (bond >= GameRules.maxBond) return false;
    if (lastBondAt == null) return true;
    return now.difference(lastBondAt!) >= GameRules.bondTapCooldown;
  }

  factory UserMonster.fromMap(Map<String, Object?> m) {
    return UserMonster(
      id: m['id'] as String,
      profileId: m['profile_id'] as String,
      speciesId: m['species_id'] as String,
      level: (m['level'] as int?) ?? 1,
      xpTotal: (m['xp_total'] as int?) ?? 0,
      bond: (m['bond'] as int?) ?? 0,
      lastBondAt: m['last_bond_at'] != null
          ? DateTime.parse(m['last_bond_at'] as String)
          : null,
      isActive: (m['is_active'] as int? ?? 0) == 1,
      unlockedAt: DateTime.parse(m['unlocked_at'] as String),
      evolvedYoungAt: m['evolved_young_at'] != null
          ? DateTime.parse(m['evolved_young_at'] as String)
          : null,
      evolvedAdultAt: m['evolved_adult_at'] != null
          ? DateTime.parse(m['evolved_adult_at'] as String)
          : null,
      masteryPoints: (m['mastery_points'] as int?) ?? 0,
    );
  }
}

class MonsterWithSpecies {
  final MonsterSpecies species;
  final UserMonster? owned;
  final CategoryMastery? categoryMastery;
  final MonsterEgg? egg;

  const MonsterWithSpecies({
    required this.species,
    this.owned,
    this.categoryMastery,
    this.egg,
  });

  bool get isUnlocked => owned != null;
  EvolutionPhase get currentPhase => owned?.phase ?? EvolutionPhase.baby;
  String get currentAsset => species.assetForPhase(currentPhase);
  CategoryGrade get grade => categoryMastery?.grade ?? CategoryGrade.c;
}

class MonsterEgg {
  final String id;
  final String profileId;
  final String speciesId;
  final MonsterElement element;
  final EggStatus status;
  final int hatchProgress;
  final DateTime grantedAt;
  final DateTime? incubatedAt;
  final DateTime? hatchedAt;

  const MonsterEgg({
    required this.id,
    required this.profileId,
    required this.speciesId,
    required this.element,
    required this.status,
    required this.hatchProgress,
    required this.grantedAt,
    this.incubatedAt,
    this.hatchedAt,
  });

  String get currentAsset =>
      status.usesCrackedAsset ? element.crackedEggAsset : element.intactEggAsset;

  factory MonsterEgg.fromMap(Map<String, Object?> m) {
    return MonsterEgg(
      id: m['id'] as String,
      profileId: m['profile_id'] as String,
      speciesId: m['species_id'] as String,
      element: MonsterElement.fromCode(m['element_id'] as String),
      status: EggStatus.fromCode(m['status'] as String),
      hatchProgress: (m['hatch_progress'] as int?) ?? 0,
      grantedAt: DateTime.parse(m['granted_at'] as String),
      incubatedAt: m['incubated_at'] != null
          ? DateTime.parse(m['incubated_at'] as String)
          : null,
      hatchedAt: m['hatched_at'] != null
          ? DateTime.parse(m['hatched_at'] as String)
          : null,
    );
  }
}

class CategoryMastery {
  final String categoryId;
  final int totalMasterFoods;
  final int uniqueDiscoveredFoods;
  final int categoryDays;
  final int distinctPlaces;
  final int totalLogs;
  final CategoryGrade grade;

  const CategoryMastery({
    required this.categoryId,
    required this.totalMasterFoods,
    required this.uniqueDiscoveredFoods,
    required this.categoryDays,
    required this.distinctPlaces,
    required this.totalLogs,
    required this.grade,
  });
}

class DailyXpStatus {
  final String localDate;
  final Set<MealType> claimedSlots;
  final int discoveryBonusesClaimed;
  final int totalXpToday;

  const DailyXpStatus({
    required this.localDate,
    required this.claimedSlots,
    required this.discoveryBonusesClaimed,
    required this.totalXpToday,
  });
}

class SaveMealResult {
  final String sessionId;
  final int sessionXpAwarded;
  final int discoveryXpAwarded;
  final List<MasterFood> newlyDiscoveredFoods;
  final List<MonsterEgg> newlyGrantedEggs;
  final List<String> starterMasteryBonusSpeciesIds;
  final bool eggProgressed;
  final MonsterEgg? updatedIncubatingEgg;
  final UserMonster? activeMonsterBefore;
  final UserMonster? activeMonsterAfter;
  final MonsterSpecies? activeMonsterSpecies;
  final EvolutionPhase? evolvedFrom;
  final EvolutionPhase? evolvedTo;
  final List<({String categoryName, CategoryGrade oldGrade, CategoryGrade newGrade})>
      gradeUpgrades;
  final bool wasBackdated;
  final bool clockWarning;

  const SaveMealResult({
    required this.sessionId,
    required this.sessionXpAwarded,
    required this.discoveryXpAwarded,
    this.newlyDiscoveredFoods = const [],
    this.newlyGrantedEggs = const [],
    this.starterMasteryBonusSpeciesIds = const [],
    this.eggProgressed = false,
    this.updatedIncubatingEgg,
    this.activeMonsterBefore,
    this.activeMonsterAfter,
    this.activeMonsterSpecies,
    this.evolvedFrom,
    this.evolvedTo,
    this.gradeUpgrades = const [],
    this.wasBackdated = false,
    this.clockWarning = false,
  });

  int get totalXpAwarded => sessionXpAwarded + discoveryXpAwarded;
  bool get leveledUp =>
      activeMonsterBefore != null &&
      activeMonsterAfter != null &&
      activeMonsterAfter!.level > activeMonsterBefore!.level;
  bool get didEvolve => evolvedFrom != null && evolvedTo != null && evolvedFrom != evolvedTo;
}

class AppSettingsModel {
  final bool reduceMotion;
  final String themeMode; // 'system' | 'light' | 'dark'
  final String? lastBackupAt;
  final bool tutorialCompleted;
  final String? lastRecordedLocalDate;

  const AppSettingsModel({
    this.reduceMotion = false,
    this.themeMode = 'light',
    this.lastBackupAt,
    this.tutorialCompleted = false,
    this.lastRecordedLocalDate,
  });
}

class FoodPriceStats {
  final int totalLogs;
  final int pricedLogs;
  final int? medianPriceMinor;
  final int? minPriceMinor;
  final int? maxPriceMinor;

  const FoodPriceStats({
    required this.totalLogs,
    required this.pricedLogs,
    this.medianPriceMinor,
    this.minPriceMinor,
    this.maxPriceMinor,
  });
}

class UserPersonalStats {
  final int totalSessions;
  final int totalItemsLogged;
  final int uniqueFoodsDiscovered;
  final int totalMasterFoods;
  final String? mostDiverseCategoryName;
  final int mostDiverseCategoryCount;
  final int placesVisitedCount;
  final int monstersUnlocked;
  final int totalSpecies;
  final int babyCount;
  final int youngCount;
  final int adultCount;
  final double avgSessionsPerWeek;
  final int totalSpendMinor;
  final int pricedItemsCount;
  final int unpricedItemsCount;

  const UserPersonalStats({
    required this.totalSessions,
    required this.totalItemsLogged,
    required this.uniqueFoodsDiscovered,
    required this.totalMasterFoods,
    this.mostDiverseCategoryName,
    this.mostDiverseCategoryCount = 0,
    required this.placesVisitedCount,
    required this.monstersUnlocked,
    required this.totalSpecies,
    required this.babyCount,
    required this.youngCount,
    required this.adultCount,
    required this.avgSessionsPerWeek,
    required this.totalSpendMinor,
    required this.pricedItemsCount,
    required this.unpricedItemsCount,
  });
}
