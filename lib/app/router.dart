import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/eggs/hatch_animation_screen.dart';
import '../features/eggs/nursery_screen.dart';
import '../features/food_dex/custom_foods_screen.dart';
import '../features/food_dex/food_category_detail_screen.dart';
import '../features/food_dex/food_detail_screen.dart';
import '../features/food_dex/food_dex_screen.dart';
import '../features/home/home_screen.dart';
import '../features/map/culinary_map_screen.dart';
import '../features/meal_log/meal_log_screen.dart';
import '../features/monster_dex/monster_detail_screen.dart';
import '../features/monster_dex/monster_dex_screen.dart';
import '../features/monsters/screens/animation_preview_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/profile_backup/meal_history_screen.dart';
import '../features/profile_backup/profile_settings_screen.dart';
import '../features/splash/splash_screen.dart';
import 'app_shell.dart';

GoRouter createMamPetRouter({
  required bool onboardingDone,
  bool showSplash = true,
}) {
  final rootNavigatorKey = GlobalKey<NavigatorState>();

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: showSplash
        ? '/splash'
        : (onboardingDone ? '/home' : '/onboarding'),
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, _) => SplashScreen(onboardingDone: onboardingDone),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (_, _) => const OnboardingScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (_, _) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/log',
                builder: (_, _) => const MealLogScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/fooddex',
                builder: (_, _) => const FoodDexScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/monsterdex',
                builder: (_, _) => const MonsterDexScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/map',
                builder: (_, _) => const CulinaryMapScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/log/new',
        builder: (_, state) => MealLogScreen(
          preselectedFoodId: state.uri.queryParameters['foodId'],
          initialMealTypeCode: state.uri.queryParameters['mealType'],
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/log/edit/:id',
        builder: (_, state) => MealLogScreen(
          editSessionId: state.pathParameters['id'],
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/fooddex/category/:id',
        builder: (_, state) => FoodCategoryDetailScreen(
          categoryId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/fooddex/food/:id',
        builder: (_, state) => FoodDetailScreen(
          foodId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/fooddex/custom',
        builder: (_, _) => const CustomFoodsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/monster/:id',
        builder: (_, state) => MonsterDetailScreen(
          speciesId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/nursery',
        builder: (_, _) => const NurseryScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/nursery/hatch/:id',
        builder: (_, state) => HatchAnimationScreen(
          eggId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/settings',
        builder: (_, _) => const ProfileSettingsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/history',
        builder: (_, state) => MealHistoryScreen(
          initialTabIndex: state.uri.queryParameters['tab'] == 'gallery' ? 1 : 0,
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/dev/animation-preview',
        builder: (_, state) => AnimationPreviewScreen(
          initialMonsterId: state.uri.queryParameters['monster'],
        ),
      ),
    ],
  );
}
