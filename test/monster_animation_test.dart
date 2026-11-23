import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mampet/core/domain/enums.dart';
import 'package:mampet/core/providers/app_providers.dart';
import 'package:mampet/features/monsters/animation/monster_animation_config.dart';
import 'package:mampet/features/monsters/animation/monster_animation_controller.dart';
import 'package:mampet/features/monsters/animation/monster_animation_state.dart';
import 'package:mampet/features/monsters/models/monster_rig.dart';
import 'package:mampet/features/monsters/openbone/openbone_document.dart';
import 'package:mampet/features/monsters/openbone/openbone_repository.dart';
import 'package:mampet/features/monsters/openbone/openbone_runtime.dart';
import 'package:mampet/features/monsters/screens/animation_preview_screen.dart';
import 'package:mampet/features/monsters/widgets/interactive_monster.dart';
import 'package:mampet/features/monsters/widgets/monster_preview.dart';

void main() {
  group('MonsterRig & MonsterAnimationConfig', () {
    test('resolves numeric species IDs, slugs, and asset paths accurately', () {
      expect(MonsterRig.resolveSlug('01'), 'fire_dragon');
      expect(MonsterRig.resolveSlug('04'), 'fox');
      expect(MonsterRig.resolveSlug('06'), 'leaf_spirit');
      expect(MonsterRig.resolveSlug('07'), 'pink_axolotl');
      expect(MonsterRig.resolveSlug('20'), 'bamboo_panda');
      expect(MonsterRig.resolveSlug('fire_dragon'), 'fire_dragon');
      expect(
        MonsterRig.resolveSlug('assets/monsters/water_slime/baby.png'),
        'water_slime',
      );
      expect(MonsterRig.allSlugs.length, 20);
    });

    test('parses rig.json schema with hierarchy, slots, and hitboxes', () {
      final rig = MonsterRig.fromJson(
        {
          'monster_id': 'fire_dragon',
          'stage': 'baby',
          'rig_tier': 'full_layered',
          'archetype': 'winged_dragon',
          'canvas_size': [1024, 1024],
          'layers': [
            {
              'id': 'head',
              'asset': 'layers/head.png',
              'z_index': 8,
              'pivot': [0.57, 0.56],
              'parent': 'body',
            },
            {
              'id': 'body',
              'asset': 'layers/body.png',
              'z_index': 5,
              'pivot': [0.55, 0.84],
              'parent': null,
            },
            {
              'id': 'eyes_open',
              'asset': 'layers/eyes_open.png',
              'z_index': 9,
              'pivot': [0.57, 0.56],
              'parent': 'head',
              'slot': 'eyes',
              'default_visible': true,
            },
          ],
          'hitboxes': [
            {
              'part': 'head',
              'rect': [0.24, 0.14, 0.60, 0.45],
              'reaction': 'pet',
            },
          ],
          'animations': ['idle', 'happy', 'pet', 'eat', 'sleep', 'play', 'evolve'],
        },
        basePath: 'assets/monsters/fire_dragon/baby',
      );

      expect(rig.rigTier, RigTier.fullLayered);
      expect(rig.hasRigLayers, isTrue);
      expect(rig.sortedLayers.first.id, 'body');
      expect(rig.sortedLayers.last.id, 'eyes_open');
      expect(
        rig.resolveLayerAsset(rig.layerById('head')!),
        'assets/monsters/fire_dragon/baby/layers/head.png',
      );
      expect(rig.hitboxes.single.part, 'head');
    });

    test('KeyframeTrack evaluates smooth endpoints and midpoints', () {
      const track = KeyframeTrack(
        dy: [0.0, -40.0, 0.0],
        rotDeg: [-10.0, 10.0],
      );
      final start = track.evaluate(0.0);
      final mid = track.evaluate(0.5);
      final end = track.evaluate(1.0);

      expect(start.dy, closeTo(0.0, 0.001));
      expect(mid.dy, closeTo(-40.0, 0.001));
      expect(end.dy, closeTo(0.0, 0.001));
      expect(start.rotDeg, closeTo(-10.0, 0.001));
      expect(mid.rotDeg, closeTo(0.0, 0.001));
      expect(end.rotDeg, closeTo(10.0, 0.001));
    });
  });

  group('MonsterAnimationController State Machine', () {
    test('non-looping reactions smoothly return to idle after duration', () {
      final ctrl = MonsterAnimationController(randomSeed: 42);
      expect(ctrl.state, MonsterAnimation.idle);

      ctrl.play(MonsterAnimation.pet);
      expect(ctrl.state, MonsterAnimation.pet);
      expect(ctrl.activeEyesLayerId(), 'eyes_closed');

      // Advance in realistic 30ms steps through the 1350ms pet cycle
      for (int i = 0; i < 50; i++) {
        ctrl.tick(const Duration(milliseconds: 30));
      }
      expect(ctrl.state, MonsterAnimation.idle);
      ctrl.dispose();
    });

    test('sleep loops persistently until wakeUp or tap interaction', () {
      final ctrl = MonsterAnimationController(randomSeed: 7);
      ctrl.sleep();
      expect(ctrl.isSleeping, isTrue);
      expect(ctrl.activeEyesLayerId(), 'eyes_sleep');

      // Advance 6 seconds -> must remain asleep
      for (int i = 0; i < 200; i++) {
        ctrl.tick(const Duration(milliseconds: 30));
      }
      expect(ctrl.isSleeping, isTrue);

      // Tapping any part wakes the monster cheerfully
      final reaction = ctrl.reactToPart('head');
      expect(reaction, MonsterAnimation.happy);
      expect(ctrl.isSleeping, isFalse);
      expect(ctrl.state, MonsterAnimation.happy);
      ctrl.dispose();
    });

    test('eat state alternates chewing mouth layers across cycle', () {
      final ctrl = MonsterAnimationController(randomSeed: 3);
      ctrl.play(MonsterAnimation.eat);

      final seenMouths = <String>{};
      for (int i = 0; i < 45; i++) {
        seenMouths.add(ctrl.activeMouthLayerId());
        ctrl.tick(const Duration(milliseconds: 30));
      }
      expect(seenMouths.contains('mouth_eating'), isTrue);
      expect(seenMouths.contains('mouth_neutral'), isTrue);
      ctrl.dispose();
    });

    test('pause halts animation progress and triggerBlink switches eye layer', () {
      final ctrl = MonsterAnimationController(randomSeed: 1);
      ctrl.triggerBlink();
      expect(ctrl.isBlinking, isTrue);
      expect(ctrl.activeEyesLayerId(), 'eyes_closed');

      ctrl.pause();
      final pBefore = ctrl.normalizedProgress;
      ctrl.tick(const Duration(milliseconds: 40));
      expect(ctrl.normalizedProgress, pBefore);

      ctrl.resume();
      ctrl.setSpeed(2.0);
      expect(ctrl.speed, 2.0);
      ctrl.tick(const Duration(milliseconds: 40));
      expect(ctrl.normalizedProgress, greaterThan(pBefore));
      ctrl.dispose();
    });
  });

  group('Monster Widgets', () {
    testWidgets('InteractiveMonster renders, responds to tap, and disposes cleanly',
        (tester) async {
      final ctrl = MonsterAnimationController(randomSeed: 9);
      String? tappedPart;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: InteractiveMonster(
                monsterId: 'fire_dragon',
                evolutionStage: EvolutionPhase.baby,
                controller: ctrl,
                size: 200,
                reduceMotion: true,
                onPartTap: (part, _) => tappedPart = part,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(InteractiveMonster));
      await tester.pump();
      expect(tappedPart, isNotNull);
      expect(ctrl.state, isNot(MonsterAnimation.idle));

      // Dispose widget cleanly without Ticker leak assertions
      await tester.pumpWidget(const SizedBox.shrink());
      ctrl.dispose();
    });

    testWidgets('MonsterPreview renders unlocked and locked static previews',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                MonsterPreview(
                  monsterId: 'fox',
                  evolutionStage: EvolutionPhase.baby,
                  size: 80,
                ),
                MonsterPreview(
                  monsterId: '01',
                  evolutionStage: EvolutionPhase.adult,
                  size: 80,
                  isLocked: true,
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(MonsterPreview), findsNWidgets(2));
    });

    testWidgets('AnimationPreviewScreen renders controls and state triggers',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            allMonstersProvider.overrideWith((_) async => const []),
          ],
          child: const MaterialApp(
            home: AnimationPreviewScreen(initialMonsterId: 'fire_dragon'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Animation Preview Lab'), findsOneWidget);
      expect(find.text('Pivots'), findsOneWidget);
      expect(find.text('Hitboxes'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();

      expect(find.text('Idle'), findsOneWidget);
      expect(find.text('Sleep'), findsOneWidget);
      expect(find.text('Special'), findsOneWidget);
      expect(find.text('Evolve'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('InteractiveMonster safely handles source_blocked & review_only fallback',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                InteractiveMonster(
                  monsterId: 'leaf_spirit',
                  evolutionStage: EvolutionPhase.young,
                  size: 140,
                  reduceMotion: true,
                ),
                InteractiveMonster(
                  monsterId: 'leaf_spirit',
                  evolutionStage: EvolutionPhase.adult,
                  size: 140,
                  reduceMotion: true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(InteractiveMonster), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox.shrink());
      OpenBoneRepository.clearCache(includeManifest: true);
    });
  });

  group('OpenBone 0.4.8 Runtime & All 58 Exported Packages', () {
    test('decodes all exported .obonb packages cleanly and excludes blocked/review forms',
        () {
      final manifestFile =
          File('assets/animated_monsters/collection_manifest.json');
      expect(manifestFile.existsSync(), isTrue);

      final collection = OpenBoneCollectionManifest.fromJson(
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>,
      );
      expect(collection.totalForms, 60);
      expect(collection.exportedCount, greaterThanOrEqualTo(58));

      final sproutleYoung = collection.lookup('leaf_spirit', 'young');
      expect(sproutleYoung, isNotNull);
      expect(sproutleYoung!.isExported, isFalse);

      final sproutleAdult = collection.lookup('leaf_spirit', 'adult');
      expect(sproutleAdult, isNotNull);
      expect(sproutleAdult!.isExported, isFalse);

      int verifiedCount = 0;
      for (final form in collection.forms) {
        if (!form.isExported) continue;

        final pkgFile = File(form.fullManifestAssetPath!);
        expect(pkgFile.existsSync(), isTrue,
            reason: 'Missing manifest for ${form.key}');
        final baseDir = pkgFile.parent.path.replaceAll('\\', '/');
        final pkg = OpenBonePackageManifest.fromJson(
          jsonDecode(pkgFile.readAsStringSync()) as Map<String, dynamic>,
          baseDirAssetPath: baseDir,
        );

        final obonbFile = File(pkg.exportAssetPath);
        expect(obonbFile.existsSync(), isTrue,
            reason: 'Missing .obonb for ${form.key}');

        final doc = OpenBoneDocument.fromBytes(obonbFile.readAsBytesSync());
        expect(doc.animations.length, 7,
            reason: 'Expected 7 clips in ${form.key}');
        expect(doc.stateMachines.length, 1,
            reason: 'Expected 1 state machine in ${form.key}');
        expect(doc.atlasPages.length, 1,
            reason: 'Expected 1 embedded atlas page in ${form.key}');
        expect(doc.totalMeshVertices, greaterThan(20));

        final player = OpenBonePlayer(doc, stateMachineName: pkg.stateMachineName);
        player.advance(0.1);
        final drawItems = player.skeleton.buildDrawList();
        expect(drawItems, isNotEmpty, reason: 'Empty drawList for ${form.key}');
        for (final item in drawItems) {
          for (final v in item.worldVertices) {
            expect(v.isFinite, isTrue, reason: 'Non-finite vertex in ${form.key}');
          }
        }
        verifiedCount++;
      }

      expect(verifiedCount, collection.exportedCount);
    });

    test('revised expression packages (57/58) use open-eye idle blink & multi-stage eat chew',
        () {
      final manifestFile =
          File('assets/animated_monsters/collection_manifest.json');
      final collection = OpenBoneCollectionManifest.fromJson(
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>,
      );

      int revisedCount = 0;
      for (final form in collection.forms) {
        if (!form.isExported) continue;
        final pkgFile = File(form.fullManifestAssetPath!);
        final baseDir = pkgFile.parent.path.replaceAll('\\', '/');
        final pkg = OpenBonePackageManifest.fromJson(
          jsonDecode(pkgFile.readAsStringSync()) as Map<String, dynamic>,
          baseDirAssetPath: baseDir,
        );
        final rev = pkg.expressionRevision;
        if (rev != null) {
          expect(rev.version, greaterThanOrEqualTo(2));
          expect(rev.defaultEyes, 'eyes_open');
          expect(rev.defaultMouth, 'mouth_relaxed');
          revisedCount++;
        }
      }
      expect(revisedCount, greaterThanOrEqualTo(57));

      // Verify revised fox/young cycles through intermediate blink & chew attachments
      final foxFile =
          File('assets/animated_monsters/fox/young/exports/character.obonb');
      final doc = OpenBoneDocument.fromBytes(foxFile.readAsBytesSync());
      final player = OpenBonePlayer(doc, stateMachineName: 'FoxiliYoung');

      final eyesSlot = doc.slots.indexWhere((s) => s.name == 'eyes');
      final mouthSlot = doc.slots.indexWhere((s) => s.name == 'mouth');
      expect(player.skeleton.slots[eyesSlot].attachmentName, 'eyes_open');
      expect(player.skeleton.slots[mouthSlot].attachmentName, 'mouth_relaxed');

      final idleEyes = <String?>{};
      for (int i = 0; i < 100; i++) {
        idleEyes.add(player.skeleton.slots[eyesSlot].attachmentName);
        player.advance(1 / 30);
      }
      expect(idleEyes, containsAll(<String>['eyes_open', 'eyes_lid_mid', 'eyes_closed']));

      expect(player.fireTrigger('eat'), isTrue);
      final eatMouths = <String?>{};
      for (int i = 0; i < 60; i++) {
        eatMouths.add(player.skeleton.slots[mouthSlot].attachmentName);
        player.advance(1 / 30);
      }
      expect(eatMouths, containsAll(<String>['mouth_relaxed', 'mouth_parted', 'mouth_open', 'mouth_chew']));
    });

    test('OpenBone state machine handles triggers, sleep loop, wake, auto-return & face hitbox',
        () {
      final obonbFile =
          File('assets/animated_monsters/fire_dragon/baby/exports/embergon_baby.obonb');
      final doc = OpenBoneDocument.fromBytes(obonbFile.readAsBytesSync());
      final statesSeen = <String>[];
      final player = OpenBonePlayer(
        doc,
        stateMachineName: 'EmbergonBaby',
        onStateChanged: statesSeen.add,
      );

      expect(player.activeStateName, 'idle');

      // One-shot reaction (pet) runs and auto-returns to idle
      expect(player.fireTrigger('pet'), isTrue);
      expect(player.activeStateName, 'pet');
      for (int i = 0; i < 60; i++) {
        player.advance(1 / 30);
      }
      expect(player.activeStateName, 'idle');

      // Special clip runs and auto-returns to idle
      expect(player.fireTrigger('special'), isTrue);
      expect(player.activeStateName, 'special');
      for (int i = 0; i < 80; i++) {
        player.advance(1 / 30);
      }
      expect(player.activeStateName, 'idle');

      // Sleep loops persistently for > 6 seconds until `wake` trigger
      expect(player.fireTrigger('sleep'), isTrue);
      expect(player.activeStateName, 'sleep');
      for (int i = 0; i < 200; i++) {
        player.advance(1 / 30);
      }
      expect(player.activeStateName, 'sleep');

      expect(player.fireTrigger('wake'), isTrue);
      expect(player.activeStateName, 'idle');

      // Face hitbox tap triggers `pet`; tapping outside returns null
      expect(player.handleArtboardTap(10, 10), isNull);

      // Compute centroid of `touch` boundingBox in artboard space and tap it
      final touchSlotIdx = doc.slots.indexWhere((s) => s.name == 'touch');
      expect(touchSlotIdx, greaterThanOrEqualTo(0));
      final poly = player.skeleton.boundingBoxWorldVertices(touchSlotIdx)!;
      double cx = 0;
      double cy = 0;
      final n = poly.length ~/ 2;
      for (int i = 0; i < poly.length; i += 2) {
        cx += doc.originX + poly[i];
        cy += doc.originY - poly[i + 1];
      }
      cx /= n;
      cy /= n;
      expect(player.handleArtboardTap(cx, cy), 'pet');
      expect(player.activeStateName, 'pet');

      // Verify vertices stay within the 1024x1024 artboard
      for (final item in player.skeleton.buildDrawList()) {
        for (int i = 0; i < item.worldVertices.length; i += 2) {
          final ax = doc.originX + item.worldVertices[i];
          final ay = doc.originY - item.worldVertices[i + 1];
          expect(ax, inInclusiveRange(-5.0, doc.width + 5.0));
          expect(ay, inInclusiveRange(-5.0, doc.height + 5.0));
        }
      }
    });
  });
}
