import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/services/app_update_service.dart';

/// Asks Google Play for an update once the app is up.
///
/// Play shows its own full-screen mandatory update. If the user backs out of
/// it, this gate puts a modal dialog on the root navigator that cannot be
/// dismissed, so the app cannot be used until the user updates or quits.
class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  /// Root navigator key, so the blocking dialog sits above every route.
  final GlobalKey<NavigatorState> navigatorKey;

  final Widget child;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate> {
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    AppUpdateService.listen();
    AppUpdateService.onUpdateCancelled = _requireUpdate;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppUpdateService.startImmediateUpdate();
    });
  }

  @override
  void dispose() {
    AppUpdateService.onUpdateCancelled = null;
    super.dispose();
  }

  void _requireUpdate() {
    if (!mounted || _dialogOpen) return;
    final navigatorContext = widget.navigatorKey.currentContext;
    if (navigatorContext == null) return;

    _dialogOpen = true;
    showDialog<void>(
      context: navigatorContext,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => _UpdateRequiredDialog(
        onUpdate: _retryUpdate,
        onExit: () => SystemNavigator.pop(),
      ),
    ).whenComplete(() => _dialogOpen = false);
  }

  Future<void> _retryUpdate() async {
    final status = await AppUpdateService.startImmediateUpdate();
    if (status == AppUpdateStatus.unavailable) {
      await AppUpdateService.openPlayStore();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _UpdateRequiredDialog extends StatelessWidget {
  const _UpdateRequiredDialog({required this.onUpdate, required this.onExit});

  final Future<void> Function() onUpdate;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      child: AlertDialog(
        icon: Icon(
          Icons.system_update_rounded,
          size: 40,
          color: theme.colorScheme.primary,
        ),
        title: const Text('Update MamPet dulu ya', textAlign: TextAlign.center),
        content: const Text(
          'Versi baru MamPet sudah tersedia. Update diperlukan supaya catatan '
          'kuliner dan koleksi monster kamu tetap aman dan bisa dibuka.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(onPressed: onExit, child: const Text('Keluar')),
          FilledButton.icon(
            onPressed: onUpdate,
            icon: const Icon(Icons.download_rounded),
            label: const Text('Update sekarang'),
          ),
        ],
      ),
    );
  }
}
