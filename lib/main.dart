import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/bootstrap.dart';
import 'core/db/mampet_database.dart';
import 'core/db/seed_loader.dart';
import 'core/providers/app_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final seed = await SeedDataBundle.loadFromAssets();
  final db = MamPetDatabase();
  await db.init(seed);
  final profile = await db.getProfile();

  runApp(
    ProviderScope(
      overrides: [
        seedBundleProvider.overrideWithValue(seed),
        databaseProvider.overrideWithValue(db),
      ],
      child: MamPetApp(onboardingDone: profile.starterSelected),
    ),
  );
}
