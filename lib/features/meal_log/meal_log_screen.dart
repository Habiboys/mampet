import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme.dart';
import '../../core/clock/app_clock.dart';
import '../../core/domain/enums.dart';
import '../../core/domain/models.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/meal_share_service.dart';
import '../../core/utils/formatters.dart';
import 'evolution_dialog.dart';
import 'food_search_sheet.dart';
import 'place_picker_sheet.dart';
import 'reward_summary_sheet.dart';
import '../monsters/animation/monster_animation_state.dart';

class MealLogScreen extends ConsumerStatefulWidget {
  final String? editSessionId;
  final String? preselectedFoodId;
  final String? initialMealTypeCode;

  const MealLogScreen({
    super.key,
    this.editSessionId,
    this.preselectedFoodId,
    this.initialMealTypeCode,
  });

  @override
  ConsumerState<MealLogScreen> createState() => _MealLogScreenState();
}

class _MealLogScreenState extends ConsumerState<MealLogScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _sessionNotesCtrl = TextEditingController();

  late DateTime _occurredAt;
  late MealType _mealType;
  PlaceMode _placeMode = PlaceMode.none;
  PlaceModel? _selectedPlace;
  final List<MealItemDraft> _items = [];
  List<MasterFood> _quickPicks = [];

  bool _loadingEdit = false;
  bool _saving = false;

  bool get _isEditMode => widget.editSessionId != null;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _occurredAt = now;
    _mealType = widget.initialMealTypeCode != null
        ? MealType.fromCode(widget.initialMealTypeCode!)
        : MealType.defaultForHour(now.hour);
    _loadQuickPicks();
    if (_isEditMode) {
      _loadExistingSession();
    } else if (widget.preselectedFoodId != null) {
      _loadPreselectedFood(widget.preselectedFoodId!);
    }
  }

  Future<void> _loadQuickPicks() async {
    final db = ref.read(databaseProvider);
    var picks = await db.getRecentMasterFoods(limit: 6);
    if (picks.length < 6) {
      final all = await db.getAllMasterFoods();
      const popularNames = [
        'Nasi Goreng',
        'Mie Ayam',
        'Ayam Geprek',
        'Bakso Sapi',
        'Es Kopi Susu',
        'Es Teh Manis',
      ];
      final existingIds = picks.map((e) => e.id).toSet();
      for (final name in popularNames) {
        final match = all.where((f) => f.canonicalName == name).firstOrNull;
        if (match != null && !existingIds.contains(match.id)) {
          picks = [...picks, match];
          existingIds.add(match.id);
        }
        if (picks.length >= 6) break;
      }
    }
    if (mounted) {
      setState(() => _quickPicks = picks);
    }
  }

  Future<void> _loadPreselectedFood(String foodId) async {
    final food = await ref.read(databaseProvider).getMasterFoodById(foodId);
    if (food != null && mounted) {
      setState(() {
        _items.add(
          MealItemDraft(
            foodId: food.id,
            displayName: food.canonicalName,
            categoryId: food.categoryId,
          ),
        );
      });
    }
  }

  Future<void> _loadExistingSession() async {
    setState(() => _loadingEdit = true);
    final session = await ref
        .read(databaseProvider)
        .getMealSessionById(widget.editSessionId!);
    if (!mounted) return;
    if (session != null) {
      setState(() {
        _occurredAt = session.occurredAt;
        _mealType = session.mealType;
        _placeMode = session.placeMode;
        _selectedPlace = session.place;
        _sessionNotesCtrl.text = session.notes ?? '';
        _items
          ..clear()
          ..addAll(session.items.map((e) => e.toDraft()));
        _loadingEdit = false;
      });
    } else {
      setState(() => _loadingEdit = false);
    }
  }

  @override
  void dispose() {
    _sessionNotesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _occurredAt.isAfter(now) ? now : _occurredAt,
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredAt),
    );
    if (pickedTime == null || !mounted) return;

    final combined = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    if (combined.isAfter(DateTime.now().add(const Duration(minutes: 2)))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Waktu makan tidak boleh di masa depan.')),
      );
      return;
    }
    setState(() => _occurredAt = combined);
  }

  void _quickAddMasterFood(MasterFood f) {
    HapticFeedback.lightImpact();
    setState(() {
      _items.add(
        MealItemDraft(
          foodId: f.id,
          displayName: f.canonicalName,
          categoryId: f.categoryId,
          isCustom: false,
        ),
      );
    });
  }

  Future<void> _addFoodItem() async {
    final picked = await showFoodSearchSheet(context);
    if (picked == null || !mounted) return;
    HapticFeedback.lightImpact();

    if (picked.masterFood != null) {
      final f = picked.masterFood!;
      setState(() {
        _items.add(
          MealItemDraft(
            foodId: f.id,
            displayName: f.canonicalName,
            categoryId: f.categoryId,
            isCustom: false,
          ),
        );
      });
    } else if (picked.customFood != null) {
      final c = picked.customFood!;
      setState(() {
        _items.add(
          MealItemDraft(
            customFoodId: c.id,
            displayName: c.name,
            categoryId: c.categoryId,
            isCustom: true,
          ),
        );
      });
    }
  }

  Future<void> _pickPhotoForItem(int index) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded,
                  color: MamPetColors.coralPrimary),
              title: const Text('Ambil Foto dari Kamera',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: MamPetColors.skyAccent),
              title: const Text('Pilih dari Galeri',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;

    try {
      final xfile = await _picker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 78,
      );
      if (xfile == null) return;
      final storedPath =
          await ref.read(photoStorageProvider).persistPhotoFile(xfile.path);
      if (!mounted) return;
      setState(() {
        _items[index] = _items[index].copyWith(photoPath: storedPath);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Tidak dapat mengakses kamera/galeri. Catatan tetap dapat disimpan tanpa foto.'),
        ),
      );
    }
  }

  Future<void> _editItemDetailsDialog(int index) async {
    final current = _items[index];
    final priceCtrl = TextEditingController(
      text: current.priceMinor != null ? current.priceMinor.toString() : '',
    );
    final descCtrl = TextEditingController(text: current.description ?? '');
    int qty = current.quantity;
    int? rating = current.rating;

    const quickPrices = [10000, 15000, 20000, 25000, 35000, 50000];

    final updated = await showModalBottomSheet<MealItemDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                4,
                20,
                MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      current.displayName,
                      style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Semua kolom di bawah opsional dan tidak memengaruhi XP.',
                      style:
                          TextStyle(fontSize: 12, color: MamPetColors.cocoaMuted),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: priceCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Harga per porsi (Rp, opsional)',
                        prefixText: 'Rp ',
                        hintText: 'Contoh: 18000',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: quickPrices
                          .map(
                            (p) => ActionChip(
                              label: Text('Rp${p ~/ 1000}rb'),
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                setLocal(() => priceCtrl.text = p.toString());
                              },
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Text('Jumlah porsi',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        const Spacer(),
                        IconButton.outlined(
                          onPressed:
                              qty > 1 ? () => setLocal(() => qty--) : null,
                          icon: const Icon(Icons.remove_rounded),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            '$qty',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton.outlined(
                          onPressed: () => setLocal(() => qty++),
                          icon: const Icon(Icons.add_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('Rating (opsional)',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        const Spacer(),
                        ...List.generate(5, (i) {
                          final starVal = i + 1;
                          final filled = rating != null && starVal <= rating!;
                          return IconButton(
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              setLocal(
                                () => rating =
                                    rating == starVal ? null : starVal,
                              );
                            },
                            icon: Icon(
                              filled
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              size: 28,
                              color: filled
                                  ? MamPetColors.honeySecondary
                                  : MamPetColors.cocoaMuted,
                            ),
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: descCtrl,
                      maxLength: 500,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Catatan rasa / deskripsi (opsional)',
                        hintText: 'Contoh: Sambalnya mantap, porsinya pas!',
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: () {
                        final rawPrice = priceCtrl.text.trim();
                        final parsedPrice =
                            rawPrice.isEmpty ? null : int.tryParse(rawPrice);
                        Navigator.pop(
                          ctx,
                          current.copyWith(
                            priceMinor: parsedPrice,
                            clearPrice: parsedPrice == null,
                            quantity: qty,
                            rating: rating,
                            clearRating: rating == null,
                            description: descCtrl.text.trim(),
                          ),
                        );
                      },
                      child: const Text('Simpan Detail Item'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (updated != null && mounted) {
      setState(() => _items[index] = updated);
    }
  }

  Future<void> _pickPlace() async {
    final res = await showPlacePickerSheet(
      context,
      initialMode: _placeMode,
      initialPlace: _selectedPlace,
    );
    if (res == null || !mounted) return;
    setState(() {
      _placeMode = res.mode;
      _selectedPlace = res.place;
    });
  }

  Future<void> _saveSession() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Tambahkan minimal 1 makanan terlebih dahulu.')),
      );
      return;
    }
    if (_saving) return;
    HapticFeedback.mediumImpact();
    setState(() => _saving = true);

    try {
      final db = ref.read(databaseProvider);
      final reduceMotion =
          ref.read(appSettingsProvider).valueOrNull?.reduceMotion ?? false;

      if (_isEditMode) {
        await db.updateMealSession(
          sessionId: widget.editSessionId!,
          occurredAt: _occurredAt,
          mealType: _mealType,
          items: _items,
          placeMode: _placeMode,
          placeId: _selectedPlace?.id,
          notes: _sessionNotesCtrl.text,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Catatan makan berhasil diperbarui.')),
          );
          context.pop();
        }
      } else {
        final result = await db.saveMealSession(
          occurredAt: _occurredAt,
          mealType: _mealType,
          items: _items,
          placeMode: _placeMode,
          placeId: _selectedPlace?.id,
          notes: _sessionNotesCtrl.text,
        );
        if (!mounted) return;

        setState(() {
          _items.clear();
          _sessionNotesCtrl.clear();
          _placeMode = PlaceMode.none;
          _selectedPlace = null;
          _occurredAt = DateTime.now();
          _mealType = MealType.defaultForHour(_occurredAt.hour);
        });
        _loadQuickPicks();

        await showRewardSummarySheet(
          context,
          result: result,
          reduceMotion: reduceMotion,
        );

        if (mounted &&
            result.didEvolve &&
            result.activeMonsterSpecies != null &&
            result.activeMonsterAfter != null) {
          await showEvolutionCelebrationDialog(
            context,
            species: result.activeMonsterSpecies!,
            fromPhase: result.evolvedFrom!,
            toPhase: result.evolvedTo!,
            newLevel: result.activeMonsterAfter!.level,
            reduceMotion: reduceMotion,
          );
        }

        if (mounted) {
          // Queue living reaction animation on Home Screen when returning!
          if (result.didEvolve) {
            ref.read(pendingMonsterReactionProvider.notifier).state =
                MonsterAnimation.evolve;
          } else if (result.leveledUp) {
            ref.read(pendingMonsterReactionProvider.notifier).state =
                MonsterAnimation.happy;
          } else {
            ref.read(pendingMonsterReactionProvider.notifier).state =
                MonsterAnimation.eat;
          }
          if (Navigator.of(context).canPop()) {
            context.pop();
          } else {
            context.go('/home');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteSession() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Catatan Makan?'),
        content: const Text(
          'Riwayat sesi ini akan dihapus, dan XP / penemuan yang hanya berasal dari sesi ini akan dihitung ulang secara otomatis.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final photos = await ref
        .read(databaseProvider)
        .deleteMealSession(widget.editSessionId!);
    for (final p in photos) {
      await ref.read(photoStorageProvider).deletePhotoIfLocal(p);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Catatan makan dihapus.')),
      );
      context.pop();
    }
  }

  int? get _previewTotalPrice {
    final priced = _items.where((i) => i.priceMinor != null).toList();
    if (priced.isEmpty) return null;
    return priced.fold<int>(0, (sum, i) => sum + (i.priceMinor! * i.quantity));
  }

  bool get _hasPartialPrices {
    final pricedCount = _items.where((i) => i.priceMinor != null).length;
    return pricedCount > 0 && pricedCount < _items.length;
  }

  @override
  Widget build(BuildContext context) {
    final isBackdated = AppClock.formatLocalDate(_occurredAt) !=
        AppClock.formatLocalDate(DateTime.now());
    final dailyXp = ref.watch(dailyXpStatusProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Edit Catatan Makan' : 'Catat Sesi Makan'),
        actions: [
          if (_isEditMode)
            IconButton(
              tooltip: 'Bagikan ke WhatsApp',
              onPressed: () async {
                final session = await ref
                    .read(databaseProvider)
                    .getMealSessionById(widget.editSessionId!);
                if (session != null) {
                  await MealShareService.shareToWhatsApp(session: session);
                }
              },
              icon: const Icon(
                Icons.share_rounded,
                color: Color(0xFF15803D),
              ),
            ),
          if (_isEditMode)
            IconButton(
              tooltip: 'Hapus sesi',
              onPressed: _deleteSession,
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
            ),
        ],
      ),
      body: _loadingEdit
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
              children: [
                // 1. Meal Type selector
                const Text(
                  'Jenis Sesi Makan',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: MealType.values.map((t) {
                    final selected = _mealType == t;
                    final alreadyClaimed = !_isEditMode &&
                        (dailyXp?.claimedSlots.contains(t) ?? false);
                    return ChoiceChip(
                      selected: selected,
                      avatar: Icon(
                        t.icon,
                        size: 17,
                        color: selected
                            ? MamPetColors.coralPrimary
                            : MamPetColors.cocoaMuted,
                      ),
                      label: Text(
                        t.awardsSessionXp
                            ? '${t.label} (${alreadyClaimed ? 'terisi' : '+${t.baseXp} XP'})'
                            : t.label,
                      ),
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        setState(() => _mealType = t);
                      },
                    );
                  }).toList(),
                ),

                const SizedBox(height: 16),

                // 2. Date & Time
                Card(
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: MamPetColors.coralSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.schedule_rounded,
                          color: MamPetColors.coralPrimary),
                    ),
                    title: const Text('Waktu Makan',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                            color: MamPetColors.cocoaMuted)),
                    subtitle: Text(
                      MamPetFormatters.formatDateTime(_occurredAt),
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 15),
                    ),
                    trailing: const Icon(Icons.edit_calendar_rounded),
                    onTap: _pickDateTime,
                  ),
                ),
                if (isBackdated)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                      'Info: Tanggal lampau tersimpan ke riwayat & FoodDex tanpa XP sesi hari ini.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber.shade900,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),

                const SizedBox(height: 20),

                // 3. Meal Items List
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Hidangan (${_items.length})',
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 15.5),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _addFoodItem,
                      icon: const Icon(Icons.search_rounded, size: 18),
                      label: const Text('Cari Katalog'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Quick-pick chips for 2-tap instant logging
                if (!_isEditMode && _quickPicks.isNotEmpty) ...[
                  const Text(
                    'Tambah Cepat:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: MamPetColors.cocoaMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: _quickPicks
                        .map(
                          (f) => ActionChip(
                            avatar: const Icon(Icons.add_circle_outline_rounded,
                                size: 16, color: MamPetColors.coralPrimary),
                            label: Text(f.canonicalName),
                            onPressed: () => _quickAddMasterFood(f),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                ],

                if (_items.isEmpty)
                  InkWell(
                    onTap: _addFoodItem,
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            MamPetColors.coralSoft.withValues(alpha: 0.9),
                            MamPetColors.warmSurfaceAlt,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: MamPetColors.coralPrimary.withValues(alpha: 0.45),
                          width: 1.6,
                        ),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.restaurant_menu_rounded,
                              size: 36, color: MamPetColors.coralPrimary),
                          SizedBox(height: 8),
                          Text(
                            'Ketuk untuk memilih makanan',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15.5,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Cari dari 600+ katalog master (dukung alias seperti "nasgor") atau buat makanan custom.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: MamPetColors.cocoaMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...List.generate(_items.length, (i) {
                    final item = _items[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardTheme.color,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: MamPetColors.warmOutline),
                        boxShadow: MamPetColors.softCardShadow(),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (item.photoPath != null &&
                                    File(item.photoPath!).existsSync())
                                  Padding(
                                    padding: const EdgeInsets.only(right: 12),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(14),
                                      child: Image.file(
                                        File(item.photoPath!),
                                        width: 56,
                                        height: 56,
                                        fit: BoxFit.cover,
                                        cacheWidth: 160,
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              item.displayName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w900,
                                                fontSize: 15.5,
                                              ),
                                            ),
                                          ),
                                          if (item.isCustom) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color:
                                                    MamPetColors.warmSurfaceAlt,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: const Text(
                                                'Custom',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        [
                                          if (item.priceMinor != null)
                                            MamPetFormatters.formatRupiah(
                                                item.priceMinor),
                                          if (item.quantity > 1)
                                            '×${item.quantity}',
                                          if (item.rating != null)
                                            '★ ${item.rating}/5',
                                          if (item.priceMinor == null)
                                            'Harga opsional',
                                        ].join(' • '),
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          color: MamPetColors.cocoaMuted,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Hapus item',
                                  onPressed: () =>
                                      setState(() => _items.removeAt(i)),
                                  icon: const Icon(Icons.close_rounded,
                                      size: 20),
                                ),
                              ],
                            ),
                            if (item.description?.isNotEmpty == true) ...[
                              const SizedBox(height: 6),
                              Text(
                                item.description!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: MamPetColors.cocoaMuted,
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                ActionChip(
                                  avatar: const Icon(Icons.payments_outlined,
                                      size: 16),
                                  label: Text(item.priceMinor != null
                                      ? 'Ubah Harga & Detail'
                                      : 'Harga / Rating / Catatan'),
                                  onPressed: () => _editItemDetailsDialog(i),
                                ),
                                ActionChip(
                                  avatar: Icon(
                                    item.photoPath != null
                                        ? Icons.photo_rounded
                                        : Icons.add_a_photo_outlined,
                                    size: 16,
                                  ),
                                  label: Text(item.photoPath != null
                                      ? 'Ganti Foto'
                                      : 'Foto'),
                                  onPressed: () => _pickPhotoForItem(i),
                                ),
                                if (item.photoPath != null)
                                  ActionChip(
                                    label: const Text('Hapus Foto'),
                                    onPressed: () => setState(
                                      () => _items[i] =
                                          _items[i].copyWith(clearPhoto: true),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),

                const SizedBox(height: 14),

                // 4. Optional Place Picker
                Card(
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: MamPetColors.skySoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _placeMode == PlaceMode.home
                            ? Icons.home_rounded
                            : _placeMode == PlaceMode.place
                                ? Icons.place_rounded
                                : Icons.location_on_outlined,
                        color: MamPetColors.skyAccent,
                      ),
                    ),
                    title: const Text('Tempat Makan (Opsional)',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                            color: MamPetColors.cocoaMuted)),
                    subtitle: Text(
                      _placeMode == PlaceMode.place && _selectedPlace != null
                          ? _selectedPlace!.displayName
                          : _placeMode.label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 14.5),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _pickPlace,
                  ),
                ),

                const SizedBox(height: 14),

                // 5. Optional session notes
                TextField(
                  controller: _sessionNotesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Catatan sesi (opsional)',
                    hintText: 'Contoh: Makan siang bareng teman kantor',
                  ),
                ),

                if (_items.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: MamPetColors.warmOutline),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Total Pengeluaran Sesi',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: MamPetColors.cocoaMuted)),
                            if (_hasPartialPrices)
                              const Text(
                                'Sebagian catatan tanpa harga',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: MamPetColors.cocoaMuted,
                                ),
                              ),
                          ],
                        ),
                        Text(
                          MamPetFormatters.formatRupiah(_previewTotalPrice),
                          style: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _saving ? null : _saveSession,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_circle_outline_rounded),
            label: Text(_isEditMode
                ? 'Simpan Perubahan'
                : 'Simpan Sesi Makan${_items.isNotEmpty ? ' (${_items.length} item)' : ''}'),
          ),
        ),
      ),
    );
  }
}
