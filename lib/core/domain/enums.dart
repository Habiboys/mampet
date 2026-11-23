import 'package:flutter/material.dart';

enum MealType {
  breakfast('breakfast', 'Sarapan', 10, Icons.wb_sunny_outlined),
  lunch('lunch', 'Makan Siang', 10, Icons.light_mode_rounded),
  dinner('dinner', 'Makan Malam', 10, Icons.nights_stay_outlined),
  snack('snack', 'Camilan', 5, Icons.cookie_outlined),
  other('other', 'Lainnya', 0, Icons.restaurant_menu_rounded);

  const MealType(this.code, this.label, this.baseXp, this.icon);
  final String code;
  final String label;
  final int baseXp;
  final IconData icon;

  bool get awardsSessionXp => baseXp > 0;

  static MealType fromCode(String code) {
    return MealType.values.firstWhere(
      (e) => e.code == code,
      orElse: () => MealType.other,
    );
  }

  static MealType defaultForHour(int hour) {
    if (hour >= 5 && hour < 11) return MealType.breakfast;
    if (hour >= 11 && hour < 15) return MealType.lunch;
    if (hour >= 15 && hour < 18) return MealType.snack;
    if (hour >= 18 && hour < 22) return MealType.dinner;
    return MealType.snack;
  }
}

enum MonsterElement {
  fire(
    'fire',
    'Api',
    Color(0xFFEA580C),
    Color(0xFFFFF1E6),
    Icons.local_fire_department_rounded,
    'assets/eggs/01_fire_intact.png',
    'assets/eggs/01_fire_cracked.png',
  ),
  water(
    'water',
    'Air',
    Color(0xFF0284C7),
    Color(0xFFE8F6FE),
    Icons.water_drop_rounded,
    'assets/eggs/02_water_intact.png',
    'assets/eggs/02_water_cracked.png',
  ),
  nature(
    'nature',
    'Alam',
    Color(0xFF16A34A),
    Color(0xFFEAF9EE),
    Icons.eco_rounded,
    'assets/eggs/03_nature_intact.png',
    'assets/eggs/03_nature_cracked.png',
  ),
  wind(
    'wind',
    'Angin',
    Color(0xFF0EA5E9),
    Color(0xFFECF9FF),
    Icons.air_rounded,
    'assets/eggs/04_wind_intact.png',
    'assets/eggs/04_wind_cracked.png',
  ),
  earth(
    'earth',
    'Bumi',
    Color(0xFFB45309),
    Color(0xFFFAF1E4),
    Icons.terrain_rounded,
    'assets/eggs/05_earth_intact.png',
    'assets/eggs/05_earth_cracked.png',
  ),
  mystery(
    'mystery',
    'Misteri',
    Color(0xFF7C3AED),
    Color(0xFFF3ECFF),
    Icons.auto_awesome_rounded,
    'assets/eggs/06_mystery_intact.png',
    'assets/eggs/06_mystery_cracked.png',
  );

  const MonsterElement(
    this.code,
    this.label,
    this.color,
    this.softColor,
    this.icon,
    this.intactEggAsset,
    this.crackedEggAsset,
  );

  final String code;
  final String label;
  final Color color;
  final Color softColor;
  final IconData icon;
  final String intactEggAsset;
  final String crackedEggAsset;

  static MonsterElement fromCode(String code) {
    return MonsterElement.values.firstWhere(
      (e) => e.code == code,
      orElse: () => MonsterElement.nature,
    );
  }
}

enum MonsterRarity {
  common(
    'common',
    'COMMON',
    'Common',
    Color(0xFF94A3B8),
    Color(0xFFF4F1EC),
    Color(0xFF475569),
    2.0,
    Icons.circle,
    3,
    2,
  ),
  uncommon(
    'uncommon',
    'UNCOMMON',
    'Uncommon',
    Color(0xFF14B8A6),
    Color(0xFFECFAF7),
    Color(0xFF0F766E),
    2.0,
    Icons.hexagon_rounded,
    8,
    4,
  ),
  rare(
    'rare',
    'RARE',
    'Rare',
    Color(0xFF8B5CF6),
    Color(0xFFF4EEFF),
    Color(0xFF6D28D9),
    3.0,
    Icons.star_rounded,
    12,
    6,
  );

  const MonsterRarity(
    this.code,
    this.badgeLabel,
    this.displayName,
    this.borderColor,
    this.cardSurface,
    this.textColor,
    this.borderWidth,
    this.shapeIcon,
    this.requiredUniqueFoods,
    this.requiredCategoryDays,
  );

  final String code;
  final String badgeLabel;
  final String displayName;
  final Color borderColor;
  final Color cardSurface;
  final Color textColor;
  final double borderWidth;
  final IconData shapeIcon;
  final int requiredUniqueFoods;
  final int requiredCategoryDays;

  static MonsterRarity fromCode(String code) {
    return MonsterRarity.values.firstWhere(
      (e) => e.code == code,
      orElse: () => MonsterRarity.common,
    );
  }
}

enum EvolutionPhase {
  baby('baby', 'Baby', 1),
  young('young', 'Young', 10),
  adult('adult', 'Adult', 25);

  const EvolutionPhase(this.code, this.label, this.minLevel);
  final String code;
  final String label;
  final int minLevel;
}

enum CategoryGrade {
  c('C', 'Pemula', 0, Color(0xFF78716C), Color(0xFFF5F5F4)),
  b('B', 'Penjelajah', 3, Color(0xFF2563EB), Color(0xFFEFF6FF)),
  a('A', 'Penggemar', 6, Color(0xFF059669), Color(0xFFECFDF5)),
  s('S', 'Ahli', 10, Color(0xFFD97706), Color(0xFFFFFBEB)),
  ss('SS', 'Master Kuliner', 18, Color(0xFFDB2777), Color(0xFFFDF2F8));

  const CategoryGrade(
    this.code,
    this.title,
    this.minUniqueFoods,
    this.color,
    this.surfaceColor,
  );

  final String code;
  final String title;
  final int minUniqueFoods;
  final Color color;
  final Color surfaceColor;

  int get rank => index;

  static CategoryGrade fromCode(String code) {
    return CategoryGrade.values.firstWhere(
      (e) => e.code == code,
      orElse: () => CategoryGrade.c,
    );
  }
}

enum EggStatus {
  queued('queued', 'Di Antrean'),
  incubating('incubating', 'Di Inkubator'),
  cracked('cracked', 'Mulai Retak'),
  ready('ready', 'Siap Menetas!'),
  hatched('hatched', 'Menetas'),
  archived('archived', 'Diarsipkan');

  const EggStatus(this.code, this.label);
  final String code;
  final String label;

  bool get isActiveInIncubator =>
      this == EggStatus.incubating ||
      this == EggStatus.cracked ||
      this == EggStatus.ready;

  bool get usesCrackedAsset =>
      this == EggStatus.cracked || this == EggStatus.ready;

  static EggStatus fromCode(String code) {
    return EggStatus.values.firstWhere(
      (e) => e.code == code,
      orElse: () => EggStatus.queued,
    );
  }
}

enum PlaceMode {
  none('none', 'Tanpa Lokasi'),
  home('home', 'Rumah (tanpa pin)'),
  place('place', 'Tempat Tertentu');

  const PlaceMode(this.code, this.label);
  final String code;
  final String label;

  static PlaceMode fromCode(String code) {
    return PlaceMode.values.firstWhere(
      (e) => e.code == code,
      orElse: () => PlaceMode.none,
    );
  }
}
