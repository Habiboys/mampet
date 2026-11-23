import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/domain/enums.dart';
import '../core/providers/app_providers.dart';
import 'theme.dart';

class AppShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({super.key, required this.navigationShell});

  void _onSelect(int index) {
    HapticFeedback.lightImpact();
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eggs = ref.watch(allEggsProvider).valueOrNull ?? const [];
    final hasReadyOrQueuedEgg = eggs.any(
      (e) => e.status == EggStatus.ready || e.status == EggStatus.queued,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final current = navigationShell.currentIndex;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? MamPetColors.darkSurface : MamPetColors.warmSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          border: Border(
            top: BorderSide(
              color: isDark ? MamPetColors.darkOutline : MamPetColors.warmOutline,
              width: 2.0,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: MamPetColors.espresso.withValues(alpha: isDark ? 0.35 : 0.08),
              blurRadius: 18,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: Row(
              children: [
                _NavTabItem(
                  label: 'Beranda',
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  selected: current == 0,
                  onTap: () => _onSelect(0),
                ),
                _NavTabItem(
                  label: 'FoodDex',
                  icon: Icons.menu_book_outlined,
                  activeIcon: Icons.menu_book_rounded,
                  selected: current == 2,
                  onTap: () => _onSelect(2),
                ),
                // Chunky 3D squishy center Catat Game Button
                Expanded(
                  child: GestureDetector(
                    onTap: () => _onSelect(1),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.only(bottom: 4),
                          decoration: BoxDecoration(
                            color: MamPetColors.coralDeep,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: MamPetColors.espresso.withValues(alpha: 0.78),
                              width: 1.8,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: MamPetColors.coralPrimary.withValues(
                                    alpha: current == 1 ? 0.45 : 0.28),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0xFFFF884D),
                                  MamPetColors.coralPrimary,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Catat',
                          style: TextStyle(
                            fontFamily: 'Fredoka',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: current == 1
                                ? MamPetColors.coralPrimary
                                : MamPetColors.cocoaMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _NavTabItem(
                  label: 'Monster',
                  icon: Icons.pets_outlined,
                  activeIcon: Icons.pets_rounded,
                  selected: current == 3,
                  showBadge: hasReadyOrQueuedEgg,
                  onTap: () => _onSelect(3),
                ),
                _NavTabItem(
                  label: 'Peta',
                  icon: Icons.map_outlined,
                  activeIcon: Icons.map_rounded,
                  selected: current == 4,
                  onTap: () => _onSelect(4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTabItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool selected;
  final bool showBadge;
  final VoidCallback onTap;

  const _NavTabItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.selected,
    this.showBadge = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor =
        isDark ? const Color(0xFFFF8652) : MamPetColors.coralPrimary;
    final inactiveColor = isDark ? Colors.white60 : MamPetColors.cocoaMuted;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: selected ? 1.1 : 1.0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected
                        ? activeColor.withValues(alpha: isDark ? 0.24 : 0.16)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(15),
                    border: selected
                        ? Border.all(
                            color: activeColor.withValues(alpha: 0.35),
                            width: 1.4,
                          )
                        : null,
                  ),
                  child: Badge(
                    isLabelVisible: showBadge,
                    child: Icon(
                      selected ? activeIcon : icon,
                      size: 23,
                      color: selected ? activeColor : inactiveColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Fredoka',
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? activeColor : inactiveColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
