import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class SeedDataBundle {
  final Map<String, dynamic> gameConfig;
  final Map<String, dynamic> foodCatalog;

  const SeedDataBundle({
    required this.gameConfig,
    required this.foodCatalog,
  });

  static Future<SeedDataBundle> loadFromAssets() async {
    final configStr =
        await rootBundle.loadString('assets/data/mampet_game_config_v1.json');
    final foodStr =
        await rootBundle.loadString('assets/data/food_catalog_seed_v1.json');
    return SeedDataBundle(
      gameConfig: jsonDecode(configStr) as Map<String, dynamic>,
      foodCatalog: jsonDecode(foodStr) as Map<String, dynamic>,
    );
  }
}
