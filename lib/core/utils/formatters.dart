import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MamPetFormatters {
  static final NumberFormat _idrFormat = NumberFormat('#,###', 'id_ID');

  static String formatRupiah(int? amountMinor, {String currency = 'IDR'}) {
    if (amountMinor == null) return 'Tanpa harga';
    if (currency == 'IDR') {
      return 'Rp${_idrFormat.format(amountMinor)}';
    }
    return '$currency ${_idrFormat.format(amountMinor)}';
  }

  static String formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '${local.day} ${months[local.month - 1]} ${local.year}, $h:$min';
  }

  static String formatDateShort(DateTime dt) {
    final local = dt.toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }

  static String formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$h:$min';
  }

  static String formatSpeciesNumber(String speciesId) {
    final n = int.tryParse(speciesId) ?? 0;
    return '#${n.toString().padLeft(3, '0')}';
  }

  static Color parseHexColor(String hex, {Color fallback = const Color(0xFFE86A33)}) {
    final clean = hex.replaceAll('#', '').trim();
    if (clean.length == 6) {
      return Color(int.parse('FF$clean', radix: 16));
    }
    if (clean.length == 8) {
      return Color(int.parse(clean, radix: 16));
    }
    return fallback;
  }

  static IconData categoryIcon(String iconName) {
    switch (iconName) {
      case 'rice_bowl':
        return Icons.rice_bowl_rounded;
      case 'ramen_dining':
        return Icons.ramen_dining_rounded;
      case 'bakery_dining':
        return Icons.bakery_dining_rounded;
      case 'soup_kitchen':
        return Icons.soup_kitchen_rounded;
      case 'kebab_dining':
        return Icons.kebab_dining_rounded;
      case 'set_meal':
        return Icons.set_meal_rounded;
      case 'eco':
        return Icons.eco_rounded;
      case 'tapas':
        return Icons.tapas_rounded;
      case 'cake':
        return Icons.cake_rounded;
      case 'nutrition':
        return Icons.spa_rounded;
      case 'local_cafe':
        return Icons.local_cafe_rounded;
      case 'local_drink':
        return Icons.local_drink_rounded;
      default:
        return Icons.restaurant_rounded;
    }
  }
}
