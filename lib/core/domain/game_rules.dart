import 'enums.dart';

class GameRules {
  static const int maxLevel = 30;
  static const int minLevel = 1;
  static const int youngEvolutionLevel = 10;
  static const int adultEvolutionLevel = 25;

  static const int discoveryBonusXp = 5;
  static const int maxDailyDiscoveryBonuses = 3;
  static const int maxDailyXp = 50;

  static const int sessionsToHatch = 3;
  static const int crackedThreshold = 2;
  static const int maxActiveIncubators = 1;

  static const int maxBond = 100;
  static const int bondTapGain = 5;
  static const Duration bondTapCooldown = Duration(hours: 4);

  static const int starterMasteryBonusPoints = 25;

  /// XP required to advance from level [level] to [level + 1].
  /// Formula: 15 + 3 * (L - 1) for L = 1..29.
  static int xpToNextLevel(int level) {
    if (level < minLevel) return 15;
    if (level >= maxLevel) return 0;
    return 15 + 3 * (level - 1);
  }

  /// Total cumulative XP required to reach [level] from Level 1.
  /// Formula: (N-1)*15 + 3*(N-1)*(N-2)/2.
  static int cumulativeXpForLevel(int level) {
    final clamped = level.clamp(minLevel, maxLevel);
    final n = clamped - 1;
    return n * 15 + (3 * n * (n - 1)) ~/ 2;
  }

  /// Calculates current level (1..30) from [totalXp].
  static int levelFromTotalXp(int totalXp) {
    if (totalXp <= 0) return minLevel;
    int level = minLevel;
    while (level < maxLevel && totalXp >= cumulativeXpForLevel(level + 1)) {
      level++;
    }
    return level;
  }

  /// Returns (xpIntoCurrentLevel, xpNeededForNextLevel) for progress bars.
  static ({int current, int required, double progress}) xpProgress(int totalXp) {
    final level = levelFromTotalXp(totalXp);
    if (level >= maxLevel) {
      return (current: 0, required: 0, progress: 1.0);
    }
    final floorXp = cumulativeXpForLevel(level);
    final need = xpToNextLevel(level);
    final inside = (totalXp - floorXp).clamp(0, need);
    return (
      current: inside,
      required: need,
      progress: need > 0 ? inside / need : 1.0,
    );
  }

  static EvolutionPhase phaseForLevel(int level) {
    if (level >= adultEvolutionLevel) return EvolutionPhase.adult;
    if (level >= youngEvolutionLevel) return EvolutionPhase.young;
    return EvolutionPhase.baby;
  }

  static int sessionXpForMealType(MealType type) => type.baseXp;

  /// Evaluates category Grade from unique master foods, distinct places, and category days.
  /// - C: 0
  /// - B: 3 unique
  /// - A: 6 unique
  /// - S: 10 unique AND (>=2 places OR >=5 category days)
  /// - SS: 18 unique AND (>=4 places OR >=10 category days)
  static CategoryGrade calculateGrade({
    required int uniqueFoods,
    required int distinctPlaces,
    required int categoryDays,
  }) {
    if (uniqueFoods >= 18 && (distinctPlaces >= 4 || categoryDays >= 10)) {
      return CategoryGrade.ss;
    }
    if (uniqueFoods >= 10 && (distinctPlaces >= 2 || categoryDays >= 5)) {
      return CategoryGrade.s;
    }
    if (uniqueFoods >= 6) return CategoryGrade.a;
    if (uniqueFoods >= 3) return CategoryGrade.b;
    return CategoryGrade.c;
  }

  /// Computes next EggStatus given incubation state & valid session count.
  static EggStatus eggStatusForProgress({
    required int progress,
    required bool isIncubating,
  }) {
    if (!isIncubating) return EggStatus.queued;
    if (progress >= sessionsToHatch) return EggStatus.ready;
    if (progress >= crackedThreshold) return EggStatus.cracked;
    return EggStatus.incubating;
  }

  /// Evaluates whether a species unlock rule is satisfied.
  static bool meetsSpeciesUnlock({
    required int requiredUniqueFoods,
    required int requiredCategoryDays,
    required int actualUniqueFoods,
    required int actualCategoryDays,
  }) {
    return actualUniqueFoods >= requiredUniqueFoods &&
        actualCategoryDays >= requiredCategoryDays;
  }

  static String bondTierTitle(int bond) {
    if (bond >= 80) return 'Sobat Kuliner Sejati';
    if (bond >= 50) return 'Ikatan Erat';
    if (bond >= 20) return 'Sahabat Hangat';
    return 'Kenalan Baru';
  }
}
