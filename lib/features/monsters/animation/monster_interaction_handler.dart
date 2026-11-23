import 'package:flutter/material.dart';

import '../models/monster_rig.dart';
import 'monster_animation_controller.dart';
import 'monster_animation_state.dart';

/// Maps zero-latency single tap (with body-part hitbox detection) and rapid
/// double tap onto [MonsterAnimationController] reactions.
///
/// Uses a lightweight timestamp window instead of Flutter's competing
/// `onDoubleTap` recognizer so single taps fire with **0 ms arena delay**.
class MonsterInteractionHandler extends StatefulWidget {
  final MonsterRig rig;
  final MonsterAnimationController controller;
  final double size;
  final bool enabled;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final void Function(String part, MonsterAnimation reaction)? onPartTap;
  final Widget child;

  const MonsterInteractionHandler({
    super.key,
    required this.rig,
    required this.controller,
    required this.size,
    this.enabled = true,
    this.onTap,
    this.onDoubleTap,
    this.onPartTap,
    required this.child,
  });

  @override
  State<MonsterInteractionHandler> createState() =>
      _MonsterInteractionHandlerState();
}

class _MonsterInteractionHandlerState extends State<MonsterInteractionHandler> {
  DateTime? _lastTapAt;
  static const Duration _doubleTapWindow = Duration(milliseconds: 320);

  /// Finds the best matching hitbox for normalized canvas point `(nx, ny)`.
  /// Prefers more specific (smaller area) hitboxes such as `head`, `wing_left`,
  /// `tail`, or `ears` over the broader `body` fallback hitbox.
  RigHitbox? _hitTest(Offset localPos) {
    if (widget.size <= 0 || widget.rig.hitboxes.isEmpty) return null;
    final nx = (localPos.dx / widget.size).clamp(0.0, 1.0);
    final ny = (localPos.dy / widget.size).clamp(0.0, 1.0);
    final pt = Offset(nx, ny);

    final matches = <RigHitbox>[];
    for (final hb in widget.rig.hitboxes) {
      if (hb.rect.contains(pt)) {
        matches.add(hb);
      }
    }
    if (matches.isEmpty) return null;
    matches.sort(
      (a, b) => (a.rect.width * a.rect.height)
          .compareTo(b.rect.width * b.rect.height),
    );
    return matches.first;
  }

  void _handleTapUp(TapUpDetails details) {
    if (!widget.enabled) return;
    final now = DateTime.now();
    final isDoubleTap =
        _lastTapAt != null && now.difference(_lastTapAt!) <= _doubleTapWindow;
    _lastTapAt = isDoubleTap ? null : now;

    if (isDoubleTap) {
      if (widget.controller.isSleeping) {
        widget.controller.wakeUp();
        widget.onPartTap?.call('body', MonsterAnimation.happy);
      } else {
        widget.controller.play(MonsterAnimation.play);
        widget.onPartTap?.call('double_tap', MonsterAnimation.play);
      }
      widget.onDoubleTap?.call();
      return;
    }

    final hit = _hitTest(details.localPosition);
    final part = hit?.part ?? 'body';
    final reaction = widget.controller.reactToPart(
      part,
      preferredReaction: hit?.reaction,
    );
    widget.onPartTap?.call(part, reaction);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: _handleTapUp,
      child: widget.child,
    );
  }
}
