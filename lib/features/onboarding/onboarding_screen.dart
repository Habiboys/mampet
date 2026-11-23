import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/domain/enums.dart';
import '../../core/domain/models.dart';
import '../../core/providers/app_providers.dart';
import '../../core/widgets/element_chip.dart';
import '../../core/widgets/game_ui.dart';
import '../../core/widgets/grade_badge.dart';
import '../../core/widgets/monster_sprite.dart';
import '../../core/widgets/rarity_badge.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  final TextEditingController _nameController = TextEditingController();

  int _step = 0; // 0..2 intro, 3 starter selection
  String? _selectedStarterId;
  bool _saving = false;

  static const _introSlides = [
    (
      tag: 'JURNAL CEPAT',
      title: 'Catat Pengalaman Makanmu',
      subtitle:
          'Simpan hidangan, foto, harga, dan tempat favorit dalam beberapa ketukan. Semua data aman di ponsel dan tetap bekerja offline.',
      asset: 'assets/branding/mampet_logo.png',
      isLogo: true,
      bgTop: Color(0xFFE3F5FF),
      bgBottom: Color(0xFFFFFBF5),
    ),
    (
      tag: '600+ HIDANGAN',
      title: 'Lengkapi FoodDex 12 Kategori',
      subtitle:
          'Temukan hidangan nusantara & dunia. Pencarian pintar mengenali alias seperti "nasgor" atau "kopsu", dan setiap menu baru menaikkan Grade!',
      asset: 'assets/monsters/leaf_spirit/baby.png',
      isLogo: false,
      bgTop: Color(0xFFEAF9EE),
      bgBottom: Color(0xFFFFFBF5),
    ),
    (
      tag: '20 MONSTER & 6 ELEMEN',
      title: 'Tetaskan & Evolusikan MamPet',
      subtitle:
          'Penjelajahan kulinermu membuka telur 6 elemen. Tiga sesi makan valid menetaskan monster Baby hingga berevolusi menjadi Adult!',
      asset: 'assets/eggs/02_water_intact.png',
      isLogo: false,
      bgTop: Color(0xFFFFEFE6),
      bgBottom: Color(0xFFFFFBF5),
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _skipToStarter() {
    HapticFeedback.selectionClick();
    setState(() => _step = 3);
  }

  Future<void> _confirmStarter() async {
    if (_selectedStarterId == null || _saving) return;
    HapticFeedback.mediumImpact();
    setState(() => _saving = true);
    try {
      await ref.read(databaseProvider).completeOnboarding(
            displayName: _nameController.text.trim(),
            starterSpeciesId: _selectedStarterId!,
          );
      if (mounted) {
        context.go('/home');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final reduceMotion = settings?.reduceMotion ?? false;
    final allMonstersAsync = ref.watch(allMonstersProvider);
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];

    return Scaffold(
      body: _step < 3
          ? _buildIntroView(context, reduceMotion)
          : _buildStarterSelectionView(
              context,
              allMonstersAsync,
              categories,
              reduceMotion,
            ),
    );
  }

  Widget _buildIntroView(BuildContext context, bool reduceMotion) {
    final activeSlide = _introSlides[_step.clamp(0, 2)];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [activeSlide.bgTop, activeSlide.bgBottom],
          stops: const [0.0, 0.6],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Image.asset(
                          'assets/branding/mampet_logo.png',
                          width: 36,
                          height: 36,
                          cacheWidth: 96,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'MamPet',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                          color: MamPetColors.espresso,
                        ),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: _skipToStarter,
                    child: const Text(
                      'Lewati',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _introSlides.length,
                onPageChanged: (idx) => setState(() => _step = idx),
                itemBuilder: (context, index) {
                  final slide = _introSlides[index];
                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 216,
                            height: 216,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.9),
                              border: Border.all(
                                color: MamPetColors.warmOutline,
                                width: 2,
                              ),
                              boxShadow: MamPetColors.softCardShadow(),
                            ),
                            alignment: Alignment.center,
                            child: slide.isLogo
                                ? Image.asset(
                                    slide.asset,
                                    width: 154,
                                    height: 154,
                                    cacheWidth: 384,
                                  )
                                : MonsterSpriteWidget(
                                    assetPath: slide.asset,
                                    size: 162,
                                    animateIdle: true,
                                    reduceMotion: reduceMotion,
                                  ),
                          ),
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: MamPetColors.coralSoft,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              slide.tag,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                                color: MamPetColors.coralPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            slide.title,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.4,
                                ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            slide.subtitle,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(
                                  color: MamPetColors.cocoaMuted,
                                  height: 1.48,
                                ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_introSlides.length, (i) {
                      final active = i == _step;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: active ? 28 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: active
                              ? MamPetColors.coralPrimary
                              : MamPetColors.warmOutline,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: GameButton(
                      label:
                          _step < 2 ? 'Lanjut' : 'Pilih Partner Pertamamu',
                      icon: _step < 2
                          ? Icons.arrow_forward_rounded
                          : Icons.pets_rounded,
                      onPressed: () {
                        if (_step < _introSlides.length - 1) {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                          );
                        } else {
                          _skipToStarter();
                        }
                      },
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

  Widget _buildStarterSelectionView(
    BuildContext context,
    AsyncValue<List<MonsterWithSpecies>> allMonstersAsync,
    List<FoodCategory> categories,
    bool reduceMotion,
  ) {
    final starters = allMonstersAsync.valueOrNull
            ?.where((m) => m.species.isStarter)
            .toList() ??
        [];
    final catMap = {for (final c in categories) c.id: c.name};

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF4E6), MamPetColors.creamBg],
          stops: [0.0, 0.3],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                children: [
                  Row(
                    children: [
                      Image.asset(
                        'assets/branding/mampet_logo.png',
                        width: 48,
                        height: 48,
                        cacheWidth: 128,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Mulai di MamPet!',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const Text(
                              'Tanpa akun • Data tersimpan aman di ponselmu',
                              style: TextStyle(
                                fontSize: 12,
                                color: MamPetColors.cocoaMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nama panggilanmu (opsional)',
                      hintText: 'Contoh: Budi, Rani, Kakak',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Text(
                        'Pilih 1 Monster Starter',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: MamPetColors.coralSoft,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Text(
                          'Lv 1 • Grade C',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: MamPetColors.coralPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (starters.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else
                    ...starters.map((m) {
                      final sp = m.species;
                      final selected = _selectedStarterId == sp.id;
                      final catName = catMap[sp.categoryId] ?? sp.categoryId;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() => _selectedStarterId = sp.id);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              gradient: selected
                                  ? LinearGradient(
                                      colors: [sp.element.softColor, Colors.white],
                                    )
                                  : null,
                              color: selected ? null : Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: selected
                                    ? sp.element.color
                                    : MamPetColors.warmOutline,
                                width: selected ? 2.6 : 1.3,
                              ),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: sp.element.color
                                            .withValues(alpha: 0.22),
                                        blurRadius: 16,
                                        offset: const Offset(0, 6),
                                      ),
                                    ]
                                  : MamPetColors.softCardShadow(),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 92,
                                  height: 92,
                                  decoration: BoxDecoration(
                                    color: sp.element.softColor
                                        .withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  alignment: Alignment.center,
                                  child: MonsterSpriteWidget(
                                    assetPath: sp.assetBaby,
                                    size: 82,
                                    animateIdle: selected,
                                    reduceMotion: reduceMotion,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            sp.displayName,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          const Spacer(),
                                          if (selected)
                                            Icon(
                                              Icons.check_circle_rounded,
                                              color: sp.element.color,
                                              size: 24,
                                            )
                                          else
                                            Icon(
                                              Icons.radio_button_unchecked_rounded,
                                              color: MamPetColors.warmOutline,
                                              size: 22,
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 5),
                                      Wrap(
                                        spacing: 5,
                                        runSpacing: 4,
                                        children: [
                                          ElementChip(
                                              element: sp.element, compact: true),
                                          const RarityBadge(
                                            rarity: MonsterRarity.common,
                                            compact: true,
                                          ),
                                          const GradeBadge(
                                            grade: CategoryGrade.c,
                                            compact: true,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Favorit: $catName',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w800,
                                          color: sp.element.color,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        sp.flavorText,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: MamPetColors.cocoaMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: GameButton(
                  label: _selectedStarterId == null
                      ? 'Pilih Salah Satu Starter'
                      : 'Mulai Petualangan MamPet!',
                  icon: Icons.auto_awesome_rounded,
                  loading: _saving,
                  onPressed: _selectedStarterId == null || _saving
                      ? null
                      : _confirmStarter,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
