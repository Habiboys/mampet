import 'package:flutter/services.dart';

import '../domain/game_rules.dart';
import '../domain/models.dart';

class HomeWidgetService {
  static const _channel = MethodChannel('com.mampet.app/home_widget');

  /// Pushes the active pet's latest sprite, level, XP %, bond, and motion
  /// preference to the native Android Home Screen Widget.
  static Future<void> syncActiveMonster({
    required MonsterWithSpecies monster,
    required bool reduceMotion,
  }) async {
    final owned = monster.owned;
    if (owned == null) return;
    final xpPct = (GameRules.xpProgress(owned.xpTotal).progress * 100)
        .round()
        .clamp(0, 100);
    try {
      await _channel.invokeMethod('updatePetWidget', {
        'name': monster.species.displayName,
        'level': owned.level,
        'phase': owned.phase.label,
        'assetPath': monster.currentAsset,
        'xpPercent': xpPct,
        'bond': owned.bond,
        'reduceMotion': reduceMotion,
      });
    } on MissingPluginException {
      // Safe no-op on tests / non-Android platforms
    } catch (_) {}
  }

  /// Opens Android's native 1-tap "Add Widget to Home Screen" pin prompt (Android 8+).
  /// Returns true if the launcher accepted the pin request, false if user should add manually.
  static Future<bool> requestPinToHomeScreen() async {
    try {
      final res = await _channel.invokeMethod<bool>('requestPinWidget');
      return res == true;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
