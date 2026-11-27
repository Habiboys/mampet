import 'package:flutter/services.dart';

/// Result of asking Google Play whether a newer version of MamPet is published.
enum AppUpdateStatus {
  /// Google Play has taken over the screen with the mandatory (IMMEDIATE)
  /// update flow.
  started,

  /// The installed version is already the newest one on Play.
  noUpdate,

  /// Play could not answer: no Play Store, sideloaded build, offline, or a
  /// non-Android platform. The app must keep working in this case.
  unavailable,
}

/// Play Store in-app updates (Android only).
///
/// The native side uses Play Core's IMMEDIATE update type, so Google Play shows
/// a full-screen update that cannot be dismissed. If the user backs out of it,
/// native sends [onUpdateCancelled] and the UI shows a blocking screen instead.
class AppUpdateService {
  AppUpdateService._();

  static const MethodChannel _channel = MethodChannel(
    'com.mampet.app/app_update',
  );

  /// Invoked when the user exits the Play update screen without updating.
  static VoidCallback? onUpdateCancelled;

  /// Starts listening for native update events. Call once at app start.
  static void listen() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'updateCancelled') {
        onUpdateCancelled?.call();
      }
      return null;
    });
  }

  /// Checks Play for an update and starts the mandatory flow when one exists.
  static Future<AppUpdateStatus> startImmediateUpdate() async {
    try {
      final code = await _channel.invokeMethod<String>('startImmediateUpdate');
      switch (code) {
        case 'started':
          return AppUpdateStatus.started;
        case 'no_update':
          return AppUpdateStatus.noUpdate;
        default:
          return AppUpdateStatus.unavailable;
      }
    } on MissingPluginException {
      // Tests, desktop, or builds without the native handler.
      return AppUpdateStatus.unavailable;
    } catch (_) {
      return AppUpdateStatus.unavailable;
    }
  }

  /// Opens the Play Store listing as a fallback when the in-app flow fails.
  static Future<void> openPlayStore() async {
    try {
      await _channel.invokeMethod<bool>('openStore');
    } catch (_) {
      // Nothing else we can do; the blocking screen keeps the app unusable
      // until the user updates or exits.
    }
  }
}
