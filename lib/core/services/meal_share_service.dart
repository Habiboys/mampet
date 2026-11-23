import 'dart:io';

import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/enums.dart';
import '../domain/models.dart';
import '../utils/formatters.dart';

/// Builds rich culinary share messages (food title, description, rating, price,
/// dining place, and clickable Google Maps link) and shares photo + caption
/// directly to WhatsApp on Android with graceful fallback to system Share Sheet.
class MealShareService {
  MealShareService._();

  static const MethodChannel _channel = MethodChannel('com.mampet.app/share');

  /// Generates a direct Google Maps URL from coordinates if pinned,
  /// otherwise falls back to a Google Maps search query for the place name/address.
  static String? googleMapsUrlForPlace(PlaceModel? place) {
    if (place == null) return null;
    if (place.hasCoordinates) {
      final lat = place.lat!.toStringAsFixed(6);
      final lng = place.lng!.toStringAsFixed(6);
      return 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    }
    final query = [
      place.displayName,
      if (place.address != null && place.address!.trim().isNotEmpty)
        place.address!.trim(),
    ].join(', ');
    if (query.trim().isEmpty) return null;
    return 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}';
  }

  /// Builds a clean, friendly WhatsApp caption containing food name, description,
  /// dining place, Google Maps link, rating, and price.
  static String buildCaption({
    required MealSessionRecord session,
    MealItemRecord? focusItem,
  }) {
    final buf = StringBuffer();

    if (focusItem != null) {
      final stars = focusItem.rating != null ? ' (${'★' * focusItem.rating!} ${focusItem.rating}/5)' : '';
      buf.writeln('🍽️ ${focusItem.displayName}$stars');
    } else {
      final names = session.items.map((e) => e.displayName).join(', ');
      buf.writeln('🍽️ $names');
    }

    buf.writeln(
      '📅 ${MamPetFormatters.formatDateTime(session.occurredAt)} • ${session.mealType.label}',
    );

    // Location + Google Maps link
    if (session.place != null) {
      final place = session.place!;
      buf.writeln('📍 Makan di: ${place.displayName}');
      if (place.address != null && place.address!.trim().isNotEmpty) {
        buf.writeln('🏠 Alamat: ${place.address!.trim()}');
      }
      final gmaps = googleMapsUrlForPlace(place);
      if (gmaps != null) {
        buf.writeln('🗺️ Google Maps: $gmaps');
      }
    } else if (session.placeMode == PlaceMode.home) {
      buf.writeln('📍 Makan di: Rumah');
    }

    // Price
    final priceMinor = focusItem != null
        ? (focusItem.priceMinor != null
            ? focusItem.priceMinor! * focusItem.quantity
            : null)
        : session.totalPriceMinor;
    if (priceMinor != null) {
      buf.writeln('💰 Harga: ${MamPetFormatters.formatRupiah(priceMinor)}');
    }

    // Description / tasting notes
    final notesParts = <String>[];
    if (focusItem != null &&
        focusItem.description != null &&
        focusItem.description!.trim().isNotEmpty) {
      notesParts.add(focusItem.description!.trim());
    } else if (focusItem == null) {
      for (final item in session.items) {
        if (item.description != null && item.description!.trim().isNotEmpty) {
          notesParts.add('${item.displayName}: ${item.description!.trim()}');
        }
      }
    }
    if (session.notes != null && session.notes!.trim().isNotEmpty) {
      notesParts.add(session.notes!.trim());
    }
    if (notesParts.isNotEmpty) {
      buf.writeln('📝 ${notesParts.join('\n')}');
    }

    buf.write('\nDicatat pakai MamPet 🐾');
    return buf.toString();
  }

  static String? _resolvePhotoPath(
    MealSessionRecord session,
    MealItemRecord? focusItem,
  ) {
    if (focusItem?.photoPath != null && File(focusItem!.photoPath!).existsSync()) {
      return focusItem.photoPath;
    }
    for (final item in session.items) {
      if (item.photoPath != null && File(item.photoPath!).existsSync()) {
        return item.photoPath;
      }
    }
    return null;
  }

  /// Shares photo + caption directly to WhatsApp if installed on Android,
  /// automatically falling back to the system Share Sheet otherwise.
  static Future<void> shareToWhatsApp({
    required MealSessionRecord session,
    MealItemRecord? focusItem,
  }) async {
    final caption = buildCaption(session: session, focusItem: focusItem);
    final photoPath = _resolvePhotoPath(session, focusItem);

    bool openedDirectly = false;
    try {
      final res = await _channel.invokeMethod<bool>('shareToWhatsApp', {
        'text': caption,
        'photoPath': photoPath,
      });
      openedDirectly = res == true;
    } catch (_) {
      openedDirectly = false;
    }

    if (!openedDirectly) {
      await shareViaSystemSheet(session: session, focusItem: focusItem);
    }
  }

  /// Opens the standard OS Share Sheet with photo + caption.
  static Future<void> shareViaSystemSheet({
    required MealSessionRecord session,
    MealItemRecord? focusItem,
  }) async {
    final caption = buildCaption(session: session, focusItem: focusItem);
    final photoPath = _resolvePhotoPath(session, focusItem);

    if (photoPath != null) {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(photoPath)],
          text: caption,
          subject: 'Catatan Kuliner MamPet',
        ),
      );
    } else {
      await SharePlus.instance.share(
        ShareParams(
          text: caption,
          subject: 'Catatan Kuliner MamPet',
        ),
      );
    }
  }

  /// Opens a dining place directly in the Google Maps app / browser.
  static Future<bool> openInGoogleMaps(PlaceModel place) async {
    final url = googleMapsUrlForPlace(place);
    if (url == null) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('openExternalUrl', {
        'url': url,
      });
      return ok == true;
    } catch (_) {
      return false;
    }
  }
}
