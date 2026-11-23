import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/domain/enums.dart';
import '../../core/domain/game_rules.dart';
import '../../core/domain/models.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/home_widget_service.dart';
import '../../core/services/meal_share_service.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/egg_sprite.dart';
import '../../core/widgets/element_chip.dart';
import '../../core/widgets/game_ui.dart';
import '../../core/widgets/grade_badge.dart';
import '../../core/widgets/monster_sprite.dart';
import '../../core/widgets/rarity_badge.dart';
import '../../core/widgets/roaming_pet_stage.dart';
import '../monsters/animation/monster_animation_controller.dart';
import '../monsters/animation/monster_animation_state.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _bondFeedback;
  int _heartTrigger = 0;
  String? _lastSyncedWidgetKey;
  late final MonsterAnimationController _petController;

  @override
  void initState() {
    super.initState();
    _petController = MonsterAnimationController();
  }

  @override
  void dispose() {
    _petController.dispose();
    super.dispose();
  }

  void _consumePendingReaction() {
    final pending = ref.read(pendingMonsterReactionProvider);
    if (pending == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(pendingMonsterReactionProvider.notifier).state = null;
      _petController.play(pending);
      setState(() {
        _heartTrigger++;
        _bondFeedback = pending == MonsterAnimation.eat
            ? 'Nyam nyam! Energi makanan masuk! ✨'
            : pending == MonsterAnimation.evolve
                ? 'Kekuatan evolusi bersinar! ★'
                : 'Yeay! Naik level bareng! ♥';
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _bondFeedback = null);
      });
    });
  }

  String _partReactionText(String part, MonsterAnimation reaction) {
    if (reaction == MonsterAnimation.special) {
      return 'Wih! Jurus spesial andalan! ✨';
    }
    if (reaction == MonsterAnimation.pet) {
      return 'Hehe enak banget dielus! ♥';
    }
    if (reaction == MonsterAnimation.play) {
      return 'Yeay! Ayo main lagi! ✨';
    }
    if (part.contains('wing') || part.contains('flipper')) {
      return 'Kepak-kepak! Ayo main! ✨';
    }
    if (part == 'tail') {
      return 'Ekornya bergoyang senang! ♥';
    }
    return 'Hehe geli! Elus lagi dong ♥';
  }

  String _timeGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 4 && hour < 11) return 'Selamat pagi';
    if (hour >= 11 && hour < 15) return 'Selamat siang';
    if (hour >= 15 && hour < 18) return 'Selamat sore';
    return 'Selamat malam';
  }

  String _petSpeech(DailyXpStatus? daily, MonsterWithSpecies monster) {
    final hour = DateTime.now().hour;
    if (daily != null && daily.totalXpToday >= GameRules.maxDailyXp) {
      return 'Mantap! Target XP hari ini penuh! ★';
    }
    if (hour >= 5 && hour < 11 && !(daily?.claimedSlots.contains(MealType.breakfast) ?? false)) {
      return 'Pagi! Sudah sarapan enak belum?';
    }
    if (hour >= 11 && hour < 15 && !(daily?.claimedSlots.contains(MealType.lunch) ?? false)) {
      return 'Waktunya makan siang bareng!';
    }
    if (hour >= 18 && hour < 22 && !(daily?.claimedSlots.contains(MealType.dinner) ?? false)) {
      return 'Makan malam apa kita hari ini?';
    }
    return 'Ketuk aku untuk elus Bond ♥';
  }

  void _syncHomeWidgetIfNeeded(MonsterWithSpecies? monster, bool reduceMotion) {
    if (monster == null || monster.owned == null) return;
    final key =
        '${monster.species.id}:${monster.owned!.level}:${monster.owned!.xpTotal}:${monster.owned!.bond}:$reduceMotion';
    if (_lastSyncedWidgetKey == key) return;
    _lastSyncedWidgetKey = key;
    HomeWidgetService.syncActiveMonster(
      monster: monster,
      reduceMotion: reduceMotion,
    );
  }

  Future<void> _pinHomeWidget(
      MonsterWithSpecies monster, bool reduceMotion) async {
    HapticFeedback.mediumImpact();
    await HomeWidgetService.syncActiveMonster(
      monster: monster,
      reduceMotion: reduceMotion,
    );
    final pinned = await HomeWidgetService.requestPinToHomeScreen();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          pinned
              ? 'Konfirmasi penambahan widget MamPet di layar utamamu!'
              : 'Tekan tahan layar utama Android → Widget → pilih "MamPet Partner"!',
        ),
      ),
    );
  }

  Future<void> _onTapActiveMonster(
    UserMonster owned, {
    String? part,
    MonsterAnimation? reaction,
  }) async {
    HapticFeedback.lightImpact();
    setState(() => _heartTrigger++);
    final res = await ref.read(databaseProvider).tapMonsterBond(owned.id);
    if (!mounted) return;
    setState(() {
      _bondFeedback = res.gained
          ? 'Bond +${GameRules.bondTapGain}! (${res.newBond}/100) ♥'
          : owned.bond >= GameRules.maxBond
              ? 'Bond sudah maksimal! ♥'
              : (part != null && reaction != null)
                  ? _partReactionText(part, reaction)
                  : 'Hehe geli! Elus lagi dong ♥';
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _bondFeedback = null);
    });
  }

  void _showSwitchMonsterSheet(
    BuildContext context,
    List<MonsterWithSpecies> allMonsters,
    bool reduceMotion,
  ) {
    final ownedList = allMonsters.where((m) => m.isUnlocked).toList();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ganti Monster Aktif',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                const Text(
                  'XP sesi makan berikutnya akan diberikan ke monster aktif yang kamu pilih.',
                  style: TextStyle(fontSize: 13, color: MamPetColors.cocoaMuted),
                ),
                const SizedBox(height: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 380),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: ownedList.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, idx) {
                      final m = ownedList[idx];
                      final isActive = m.owned!.isActive;
                      return GamePanel(
                        borderColor: isActive
                            ? MamPetColors.coralPrimary
                            : MamPetColors.warmOutline,
                        lipColor: isActive
                            ? MamPetColors.coralDeep
                            : const Color(0xFFE2D2C0),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            MonsterSpriteWidget(
                              assetPath: m.currentAsset,
                              size: 52,
                              reduceMotion: reduceMotion,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    m.species.displayName,
                                    style: const TextStyle(
                                      fontFamily: 'Fredoka',
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    'Lv ${m.owned!.level} • ${m.currentPhase.label} • Grade ${m.grade.code}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: MamPetColors.cocoaMuted,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isActive)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: MamPetColors.coralSoft,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: const Text(
                                  'AKTIF',
                                  style: TextStyle(
                                    fontFamily: 'Fredoka',
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: MamPetColors.coralPrimary,
                                  ),
                                ),
                              )
                            else
                              GameButton(
                                label: 'Pilih',
                                compact: true,
                                height: 40,
                                onPressed: () async {
                                  await ref
                                      .read(databaseProvider)
                                      .setActiveMonster(m.owned!.id);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                },
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final reduceMotion = settings?.reduceMotion ?? false;
    final activeMonster = ref.watch(activeMonsterProvider).valueOrNull;
    final allMonsters = ref.watch(allMonstersProvider).valueOrNull ?? const [];
    final dailyXp = ref.watch(dailyXpStatusProvider).valueOrNull;
    final allEggs = ref.watch(allEggsProvider).valueOrNull ?? const [];
    final activeEgg = ref.watch(activeEggProvider).valueOrNull;
    final recentSessions =
        ref.watch(recentMealSessionsProvider).valueOrNull ?? const [];
    final discoveredIds =
        ref.watch(discoveredFoodIdsProvider).valueOrNull ?? const {};
    final discoveredCustom =
        ref.watch(discoveredCustomFoodsProvider).valueOrNull ?? const [];
    final allFoodsCount =
        ref.watch(allMasterFoodsProvider).valueOrNull?.length ?? 612;
    ref.watch(pendingMonsterReactionProvider);
    _consumePendingReaction();

    _syncHomeWidgetIfNeeded(activeMonster, reduceMotion);

    final unlockedMonstersCount =
        allMonsters.where((m) => m.isUnlocked).length;
    final queuedCount =
        allEggs.where((e) => e.status == EggStatus.queued).length;
    final greetingName = (profile?.displayName.isNotEmpty == true)
        ? profile!.displayName
        : 'Penjelajah';

    Widget maybeAnimate(Widget child, int delayMs) {
      if (reduceMotion) return child;
      return child
          .animate()
          .fadeIn(delay: delayMs.ms, duration: 320.ms)
          .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic);
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_timeGreeting()},',
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: MamPetColors.cocoaMuted,
              ),
            ),
            Text(
              '$greetingName!',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Fredoka',
                fontSize: 21,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        actions: [
          IconButton.filledTonal(
            tooltip: 'Galeri Foto Makanan',
            onPressed: () => context.push('/history?tab=gallery'),
            icon: const Icon(Icons.photo_library_rounded),
          ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton.filledTonal(
              tooltip: 'Profil, Widget & Backup',
              onPressed: () => context.push('/settings'),
              icon: const Icon(Icons.settings_rounded),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dbRevisionProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
          children: [
            // 1. Game HUD Counters Strip
            maybeAnimate(
              Row(
                children: [
                  _GameHudPill(
                    icon: Icons.menu_book_rounded,
                    color: MamPetColors.coralPrimary,
                    label: '${discoveredIds.length + discoveredCustom.length}/$allFoodsCount',
                    caption: 'FoodDex',
                    onTap: () => context.go('/fooddex'),
                  ),
                  const SizedBox(width: 8),
                  _GameHudPill(
                    icon: Icons.pets_rounded,
                    color: MamPetColors.skyAccent,
                    label: '$unlockedMonstersCount/20',
                    caption: 'Monster',
                    onTap: () => context.go('/monsterdex'),
                  ),
                  const SizedBox(width: 8),
                  _GameHudPill(
                    icon: Icons.bolt_rounded,
                    color: MamPetColors.honeySecondary,
                    label:
                        '${dailyXp?.totalXpToday ?? 0}/${GameRules.maxDailyXp}',
                    caption: 'XP Harian',
                    onTap: () => context.go('/log'),
                  ),
                ],
              ),
              0,
            ),

            const SizedBox(height: 14),

            if (settings != null &&
                !settings.tutorialCompleted &&
                recentSessions.isEmpty)
              maybeAnimate(_buildTutorialCard(context), 40),

            // 2. Living 2D Habitat Hero Monster Card
            if (activeMonster != null && activeMonster.owned != null)
              maybeAnimate(
                _buildHeroMonsterCard(
                  context,
                  activeMonster,
                  allMonsters,
                  dailyXp,
                  reduceMotion,
                ),
                80,
              ),

            const SizedBox(height: 16),

            // 3. Daily Quest Meal Slots
            if (dailyXp != null)
              maybeAnimate(_buildDailyQuestCard(context, dailyXp), 140),

            const SizedBox(height: 16),

            // 4. Cozy Incubator Banner
            maybeAnimate(
              _buildEggCard(context, activeEgg, queuedCount, reduceMotion),
              200,
            ),

            const SizedBox(height: 16),

            // 4b. Prominent Culinary Documentation Hub (Rekap Harian/Bulanan & Galeri Foto)
            maybeAnimate(
              Row(
                children: [
                  Expanded(
                    child: GamePanel(
                      radius: 20,
                      borderColor: MamPetColors.coralPrimary.withValues(alpha: 0.55),
                      lipColor: MamPetColors.coralDeep.withValues(alpha: 0.45),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      onTap: () => context.push('/history'),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: MamPetColors.coralSoft,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.bar_chart_rounded,
                              color: MamPetColors.coralPrimary,
                              size: 21,
                            ),
                          ),
                          const SizedBox(width: 9),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Rekap Makan',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Fredoka',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                  ),
                                ),
                                Text(
                                  'Harian • Bulanan',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: MamPetColors.cocoaMuted,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GamePanel(
                      radius: 20,
                      borderColor: MamPetColors.skyAccent.withValues(alpha: 0.55),
                      lipColor: const Color(0xFF0369A1).withValues(alpha: 0.45),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      onTap: () => context.push('/history?tab=gallery'),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: MamPetColors.skySoft,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.photo_library_rounded,
                              color: MamPetColors.skyAccent,
                              size: 21,
                            ),
                          ),
                          const SizedBox(width: 9),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Galeri Foto',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Fredoka',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                  ),
                                ),
                                Text(
                                  'Album & Share WA',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: MamPetColors.cocoaMuted,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              230,
            ),

            const SizedBox(height: 20),

            // 5. Recent Culinary Journal
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Jurnal Makan Terbaru',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 17,
                      ),
                ),
                TextButton.icon(
                  onPressed: () => context.push('/history'),
                  icon: const Icon(Icons.history_rounded, size: 17),
                  label: const Text('Semua'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (recentSessions.isEmpty)
              GamePanel(
                padding: const EdgeInsets.all(22),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: const BoxDecoration(
                        color: MamPetColors.coralSoft,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.restaurant_rounded,
                        size: 30,
                        color: MamPetColors.coralPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Belum ada catatan makan hari ini',
                      style: TextStyle(
                        fontFamily: 'Fredoka',
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Mulai catat sarapan, makan siang, malam, atau camilanmu untuk memberi XP pada MamPet!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: MamPetColors.cocoaMuted,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    GameButton(
                      label: 'Catat Makanan Pertama',
                      icon: Icons.add_rounded,
                      onPressed: () => context.go('/log'),
                    ),
                  ],
                ),
              )
            else
              ...recentSessions.take(5).map(
                    (session) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MealSessionSummaryCard(
                        session: session,
                        onTap: () => context.push('/log/edit/${session.id}'),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildTutorialCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GamePanel(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFEFE6), Color(0xFFFFF8EE)],
        ),
        borderColor: MamPetColors.coralPrimary,
        lipColor: MamPetColors.coralDeep,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: MamPetColors.coralPrimary.withValues(alpha: 0.4)),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: MamPetColors.coralPrimary,
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Misi Pertamamu!',
                    style: TextStyle(
                      fontFamily: 'Fredoka',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Catat 1 makanan dari katalog untuk meraih XP pertama & membuka FoodDex.',
                    style:
                        TextStyle(fontSize: 12.5, color: MamPetColors.cocoaMuted),
                  ),
                  const SizedBox(height: 10),
                  GameButton(
                    label: 'Catat Sekarang',
                    compact: true,
                    height: 40,
                    onPressed: () => context.go('/log'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroMonsterCard(
    BuildContext context,
    MonsterWithSpecies monster,
    List<MonsterWithSpecies> allMonsters,
    DailyXpStatus? daily,
    bool reduceMotion,
  ) {
    final sp = monster.species;
    final owned = monster.owned!;
    final xpProg = GameRules.xpProgress(owned.xpTotal);

    return GamePanel(
      borderColor: sp.rarity.borderColor,
      lipColor: sp.rarity == MonsterRarity.rare
          ? const Color(0xFF6D28D9)
          : sp.rarity == MonsterRarity.uncommon
              ? const Color(0xFF0F766E)
              : const Color(0xFFCBB69E),
      borderWidth: sp.rarity.borderWidth,
      radius: 28,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Top badges bar
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                RarityBadge(rarity: sp.rarity, compact: true),
                const SizedBox(width: 6),
                ElementChip(element: sp.element, compact: true),
                const Spacer(),
                GradeBadge(grade: monster.grade, compact: true),
              ],
            ),
          ),

          // Living 2D Animated Habitat Playground with Interactive Rigged Pet!
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: RoamingPetStage(
              assetPath: monster.currentAsset,
              monsterSlug: sp.slug,
              evolutionStage: owned.phase,
              monsterController: _petController,
              element: sp.element,
              spriteSize: 158,
              reduceMotion: reduceMotion,
              heartTrigger: _heartTrigger,
              feedbackBanner: _bondFeedback,
              speechText: _petSpeech(daily, monster),
              onTapPet: () => _onTapActiveMonster(owned),
              onPartTap: (part, reaction) => _onTapActiveMonster(
                owned,
                part: part,
                reaction: reaction,
              ),
              semanticLabel:
                  '${sp.displayName} Level ${owned.level}, ketuk untuk interaksi Bond',
            ),
          ),

          // Quick Interactive Pet Controls (Play / Sleep-Wake)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: AnimatedBuilder(
              animation: _petController,
              builder: (_, _) => Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        _petController.play(MonsterAnimation.play);
                        setState(() => _heartTrigger++);
                      },
                      icon: const Icon(Icons.celebration_rounded, size: 16),
                      label: const Text('Main', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        if (_petController.isSleeping) {
                          _petController.wakeUp();
                        } else {
                          _petController.sleep();
                        }
                      },
                      icon: Icon(
                        _petController.isSleeping
                            ? Icons.wb_sunny_rounded
                            : Icons.bedtime_rounded,
                        size: 16,
                      ),
                      label: Text(
                        _petController.isSleeping ? 'Bangunkan' : 'Tidur',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Pet identity & Game XP Bar + Squishy 3D Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      sp.displayName,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontSize: 23,
                          ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 11, vertical: 3),
                      decoration: BoxDecoration(
                        color: MamPetColors.coralPrimary,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: MamPetColors.espresso.withValues(alpha: 0.7),
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        'Lv ${owned.level}',
                        style: const TextStyle(
                          fontFamily: 'Fredoka',
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEEF2),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: const Color(0xFFF43F5E).withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.favorite_rounded,
                              size: 13, color: Color(0xFFF43F5E)),
                          const SizedBox(width: 4),
                          Text(
                            '${owned.bond}',
                            style: const TextStyle(
                              fontFamily: 'Fredoka',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFE11D48),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Fase ${owned.phase.label} • ${GameRules.bondTierTitle(owned.bond)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: MamPetColors.cocoaMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      owned.level >= GameRules.maxLevel
                          ? 'Level Maksimal Tercapai!'
                          : 'XP ke Lv ${owned.level + 1}',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      owned.level >= GameRules.maxLevel
                          ? '${owned.xpTotal} XP'
                          : '${xpProg.current} / ${xpProg.required} XP',
                      style: const TextStyle(
                        fontFamily: 'Fredoka',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: MamPetColors.coralPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                GameProgressBar(
                  progress: xpProg.progress,
                  fillColor: sp.element.color,
                  reduceMotion: reduceMotion,
                ),
                if (owned.level < GameRules.adultEvolutionLevel) ...[
                  const SizedBox(height: 6),
                  Text(
                    owned.level < GameRules.youngEvolutionLevel
                        ? 'Evolusi Young di Lv ${GameRules.youngEvolutionLevel} • Ketuk monster untuk Bond!'
                        : 'Evolusi Adult di Lv ${GameRules.adultEvolutionLevel} • Ketuk monster untuk Bond!',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: MamPetColors.cocoaMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: GameButton.secondary(
                        label: 'Ganti Pet',
                        icon: Icons.swap_horiz_rounded,
                        compact: true,
                        height: 44,
                        onPressed: () => _showSwitchMonsterSheet(
                          context,
                          allMonsters,
                          reduceMotion,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GameButton.sky(
                        label: 'Detail',
                        icon: Icons.auto_stories_rounded,
                        compact: true,
                        height: 44,
                        onPressed: () => context.push('/monster/${sp.id}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Pasang Widget Pet ke Layar Utama',
                      child: GameButton(
                        label: 'Widget',
                        icon: Icons.widgets_rounded,
                        color: MamPetColors.honeySecondary,
                        shadowColor: const Color(0xFFB45309),
                        textColor: MamPetColors.espresso,
                        compact: true,
                        height: 44,
                        onPressed: () => _pinHomeWidget(monster, reduceMotion),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyQuestCard(BuildContext context, DailyXpStatus daily) {
    final slots = [
      MealType.breakfast,
      MealType.lunch,
      MealType.dinner,
      MealType.snack,
    ];
    return GamePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.stars_rounded,
                color: MamPetColors.honeySecondary,
                size: 23,
              ),
              const SizedBox(width: 6),
              const Text(
                'Misi Makan Hari Ini',
                style: TextStyle(
                  fontFamily: 'Fredoka',
                  fontWeight: FontWeight.w700,
                  fontSize: 16.5,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: MamPetColors.coralSoft,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: MamPetColors.coralPrimary.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  '${daily.totalXpToday} / ${GameRules.maxDailyXp} XP',
                  style: const TextStyle(
                    fontFamily: 'Fredoka',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: MamPetColors.coralPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: slots.map((slot) {
              final done = daily.claimedSlots.contains(slot);
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      context.push('/log/new?mealType=${slot.code}');
                    },
                    child: Container(
                      padding: const EdgeInsets.only(bottom: 3.5),
                      decoration: BoxDecoration(
                        color: done
                            ? const Color(0xFF15803D)
                            : const Color(0xFFD8C7B4),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: done
                              ? MamPetColors.sageAccent
                              : MamPetColors.warmOutline,
                          width: 1.5,
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 4),
                        decoration: BoxDecoration(
                          color: done
                              ? MamPetColors.sageSoft
                              : Theme.of(context).colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              done ? Icons.check_circle_rounded : slot.icon,
                              size: 21,
                              color: done
                                  ? MamPetColors.sageAccent
                                  : MamPetColors.coralPrimary,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              slot == MealType.lunch
                                  ? 'Siang'
                                  : slot == MealType.dinner
                                      ? 'Malam'
                                      : slot.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Fredoka',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              done ? 'Klaim ✓' : '+${slot.baseXp} XP',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: done
                                    ? MamPetColors.sageAccent
                                    : MamPetColors.cocoaMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome_rounded,
                    size: 16, color: MamPetColors.honeySecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Bonus hidangan baru hari ini: ${daily.discoveryBonusesClaimed}/${GameRules.maxDailyDiscoveryBonuses} (+5 XP/jenis)',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEggCard(
    BuildContext context,
    MonsterEgg? activeEgg,
    int queuedCount,
    bool reduceMotion,
  ) {
    final isReady = activeEgg?.status == EggStatus.ready;
    return GamePanel(
      gradient: activeEgg != null
          ? LinearGradient(
              colors: [activeEgg.element.softColor, Colors.white],
            )
          : null,
      borderColor: activeEgg != null
          ? activeEgg.element.color
          : MamPetColors.warmOutline,
      lipColor: activeEgg != null
          ? activeEgg.element.color.withValues(alpha: 0.75)
          : const Color(0xFFE2D2C0),
      borderWidth: isReady ? 2.4 : 1.8,
      onTap: () => context.push('/nursery'),
      child: Row(
        children: [
          if (activeEgg != null)
            EggSpriteWidget(
              element: activeEgg.element,
              status: activeEgg.status,
              size: 76,
              reduceMotion: reduceMotion,
            )
          else
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: MamPetColors.skySoft,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: MamPetColors.skyAccent.withValues(alpha: 0.35),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.egg_alt_rounded,
                size: 34,
                color: MamPetColors.skyAccent,
              ),
            ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        activeEgg != null
                            ? 'Inkubator • Telur ${activeEgg.element.label}'
                            : 'Nursery Telur',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Fredoka',
                          fontWeight: FontWeight.w700,
                          fontSize: 15.5,
                        ),
                      ),
                    ),
                    if (queuedCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: MamPetColors.coralPrimary,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '+$queuedCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                if (activeEgg != null) ...[
                  Text(
                    isReady
                        ? 'Telur siap menetas! Ketuk untuk membuka monster baru.'
                        : '${activeEgg.hatchProgress}/${GameRules.sessionsToHatch} sesi makan valid menuju penetasan.',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: MamPetColors.cocoaMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 9),
                  if (isReady)
                    GameButton.sage(
                      label: 'Tetaskan Sekarang!',
                      icon: Icons.auto_awesome_rounded,
                      compact: true,
                      height: 40,
                      onPressed: () =>
                          context.push('/nursery/hatch/${activeEgg.id}'),
                    )
                  else
                    GameProgressBar(
                      progress:
                          activeEgg.hatchProgress / GameRules.sessionsToHatch,
                      fillColor: activeEgg.element.color,
                      height: 11,
                      reduceMotion: reduceMotion,
                    ),
                ] else if (queuedCount > 0)
                  const Text(
                    'Ada telur menunggu di antrean! Ketuk untuk mulai menetaskan.',
                    style: TextStyle(
                        fontSize: 12.5, color: MamPetColors.cocoaMuted),
                  )
                else
                  const Text(
                    'Telur baru muncul setelah kamu menjelajahi makanan dalam kategori.',
                    style: TextStyle(
                        fontSize: 12.5, color: MamPetColors.cocoaMuted),
                  ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: MamPetColors.cocoaMuted),
        ],
      ),
    );
  }
}

class _GameHudPill extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String caption;
  final VoidCallback onTap;

  const _GameHudPill({
    required this.icon,
    required this.color,
    required this.label,
    required this.caption,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GamePanel(
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        onTap: onTap,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Fredoka',
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: MamPetColors.cocoaMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MealSessionSummaryCard extends StatelessWidget {
  final MealSessionRecord session;
  final VoidCallback onTap;

  const _MealSessionSummaryCard({
    required this.session,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final firstPhoto = session.items
        .map((e) => e.photoPath)
        .whereType<String>()
        .firstWhere((p) => File(p).existsSync(), orElse: () => '');
    final dishNames = session.items.map((e) => e.displayName).join(', ');
    final total = session.totalPriceMinor;
    final topRating = session.items
        .map((e) => e.rating)
        .whereType<int>()
        .fold<int?>(null, (a, b) => a == null || b > a ? b : a);

    return GamePanel(
      radius: 20,
      padding: const EdgeInsets.all(13),
      onTap: onTap,
      child: Row(
        children: [
          if (firstPhoto.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.file(
                File(firstPhoto),
                width: 58,
                height: 58,
                fit: BoxFit.cover,
                cacheWidth: 160,
              ),
            )
          else
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: MamPetColors.coralSoft,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: MamPetColors.coralPrimary.withValues(alpha: 0.35),
                ),
              ),
              child: Icon(
                session.mealType.icon,
                color: MamPetColors.coralPrimary,
                size: 26,
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: MamPetColors.coralSoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        session.mealType.label,
                        style: const TextStyle(
                          fontFamily: 'Fredoka',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: MamPetColors.coralPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        MamPetFormatters.formatDateTime(session.occurredAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: MamPetColors.cocoaMuted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  dishNames,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      total != null
                          ? MamPetFormatters.formatRupiah(total)
                          : 'Tanpa harga',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            total != null ? FontWeight.w800 : FontWeight.w600,
                        color: total != null ? null : MamPetColors.cocoaMuted,
                      ),
                    ),
                    if (topRating != null) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.star_rounded,
                          size: 14, color: MamPetColors.honeySecondary),
                      Text(
                        ' $topRating',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                    if (session.place != null ||
                        session.placeMode == PlaceMode.home) ...[
                      const Text(' • ',
                          style: TextStyle(color: MamPetColors.cocoaMuted)),
                      Flexible(
                        child: Text(
                          session.placeDisplayLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: MamPetColors.cocoaMuted,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Bagikan ke WhatsApp',
            visualDensity: VisualDensity.compact,
            onPressed: () => MealShareService.shareToWhatsApp(session: session),
            icon: const Icon(
              Icons.share_rounded,
              size: 19,
              color: Color(0xFF15803D),
            ),
          ),
        ],
      ),
    );
  }
}
