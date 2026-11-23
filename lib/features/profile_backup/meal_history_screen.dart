import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/domain/enums.dart';
import '../../core/domain/models.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/meal_share_service.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/game_ui.dart';

enum _HistoryPeriod {
  daily('Harian'),
  monthly('Bulanan'),
  yearly('Tahunan'),
  all('Semua');

  const _HistoryPeriod(this.label);
  final String label;
}

class _GalleryPhotoEntry {
  final MealSessionRecord session;
  final MealItemRecord item;
  final String photoPath;

  const _GalleryPhotoEntry({
    required this.session,
    required this.item,
    required this.photoPath,
  });
}

/// Dedicated Culinary Journal, Daily/Monthly/Yearly Summary & Food Photo Gallery.
class MealHistoryScreen extends ConsumerStatefulWidget {
  /// 0 = Riwayat & Rekap, 1 = Galeri Foto
  final int initialTabIndex;

  const MealHistoryScreen({super.key, this.initialTabIndex = 0});

  @override
  ConsumerState<MealHistoryScreen> createState() => _MealHistoryScreenState();
}

class _MealHistoryScreenState extends ConsumerState<MealHistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  _HistoryPeriod _period = _HistoryPeriod.monthly;
  DateTime _anchorDate = DateTime.now();
  MealType? _typeFilter;
  String? _galleryCategoryFilter;
  bool _galleryFiveStarOnly = false;
  final TextEditingController _searchCtrl = TextEditingController();

  static const _monthNames = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];

  static const _monthShort = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _shiftAnchor(int delta) {
    setState(() {
      switch (_period) {
        case _HistoryPeriod.daily:
          _anchorDate = _anchorDate.add(Duration(days: delta));
        case _HistoryPeriod.monthly:
          _anchorDate = DateTime(_anchorDate.year, _anchorDate.month + delta, 1);
        case _HistoryPeriod.yearly:
          _anchorDate = DateTime(_anchorDate.year + delta, 1, 1);
        case _HistoryPeriod.all:
          break;
      }
    });
  }

  String _periodHeaderLabel() {
    switch (_period) {
      case _HistoryPeriod.daily:
        return '${_anchorDate.day} ${_monthNames[_anchorDate.month - 1]} ${_anchorDate.year}';
      case _HistoryPeriod.monthly:
        return '${_monthNames[_anchorDate.month - 1]} ${_anchorDate.year}';
      case _HistoryPeriod.yearly:
        return 'Tahun ${_anchorDate.year}';
      case _HistoryPeriod.all:
        return 'Seluruh Riwayat';
    }
  }

  bool _matchesPeriod(DateTime dt) {
    switch (_period) {
      case _HistoryPeriod.daily:
        return dt.year == _anchorDate.year &&
            dt.month == _anchorDate.month &&
            dt.day == _anchorDate.day;
      case _HistoryPeriod.monthly:
        return dt.year == _anchorDate.year && dt.month == _anchorDate.month;
      case _HistoryPeriod.yearly:
        return dt.year == _anchorDate.year;
      case _HistoryPeriod.all:
        return true;
    }
  }

  Future<void> _shareSessionWa(
    MealSessionRecord session, {
    MealItemRecord? focusItem,
  }) async {
    HapticFeedback.lightImpact();
    await MealShareService.shareToWhatsApp(
      session: session,
      focusItem: focusItem,
    );
  }

  void _openPhotoViewer(
    List<_GalleryPhotoEntry> allPhotos,
    int initialIndex,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FoodPhotoGalleryViewer(
          entries: allPhotos,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(allMealSessionsProvider).valueOrNull ?? const [];
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final catNames = {for (final c in categories) c.id: c.name};

    final query = _searchCtrl.text.trim().toLowerCase();

    final periodSessions = sessions.where((s) => _matchesPeriod(s.occurredAt)).toList();

    final filteredSessions = periodSessions.where((s) {
      if (_typeFilter != null && s.mealType != _typeFilter) return false;
      if (query.isEmpty) return true;
      final inItems = s.items.any(
        (i) =>
            i.displayName.toLowerCase().contains(query) ||
            (i.description?.toLowerCase().contains(query) ?? false),
      );
      final inPlace = s.placeDisplayLabel.toLowerCase().contains(query);
      final inNotes = s.notes?.toLowerCase().contains(query) ?? false;
      return inItems || inPlace || inNotes;
    }).toList();

    // Collect all meal photos (newest first) across all sessions or current filter
    final allPhotos = <_GalleryPhotoEntry>[];
    for (final s in sessions) {
      for (final item in s.items) {
        final p = item.photoPath;
        if (p != null && p.isNotEmpty && File(p).existsSync()) {
          allPhotos.add(_GalleryPhotoEntry(session: s, item: item, photoPath: p));
        }
      }
    }

    final filteredPhotos = allPhotos.where((e) {
      if (_galleryCategoryFilter != null &&
          e.item.categoryId != _galleryCategoryFilter) {
        return false;
      }
      if (_galleryFiveStarOnly && (e.item.rating ?? 0) < 5) return false;
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Jurnal & Galeri Makan'),
        actions: [
          IconButton(
            tooltip: 'Catat Makan Baru',
            onPressed: () => context.push('/log/new'),
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(
              icon: Icon(Icons.bar_chart_rounded, size: 20),
              text: 'Riwayat & Rekap',
            ),
            Tab(
              icon: const Icon(Icons.photo_library_rounded, size: 20),
              text: 'Galeri Foto (${allPhotos.length})',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildHistoryTab(
            context,
            periodSessions: periodSessions,
            filteredSessions: filteredSessions,
            allPhotos: allPhotos,
            catNames: catNames,
          ),
          _buildGalleryTab(
            context,
            allPhotos: allPhotos,
            filteredPhotos: filteredPhotos,
            categories: categories,
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab(
    BuildContext context, {
    required List<MealSessionRecord> periodSessions,
    required List<MealSessionRecord> filteredSessions,
    required List<_GalleryPhotoEntry> allPhotos,
    required Map<String, String> catNames,
  }) {
    // Compute summary metrics for selected period
    int totalItems = 0;
    int totalSpend = 0;
    int pricedItems = 0;
    int totalPhotosInPeriod = 0;
    int ratingSum = 0;
    int ratingCount = 0;
    final catCounts = <String, int>{};

    for (final s in periodSessions) {
      for (final item in s.items) {
        totalItems += item.quantity;
        if (item.priceMinor != null) {
          totalSpend += item.priceMinor! * item.quantity;
          pricedItems++;
        }
        if (item.photoPath != null &&
            item.photoPath!.isNotEmpty &&
            File(item.photoPath!).existsSync()) {
          totalPhotosInPeriod++;
        }
        if (item.rating != null) {
          ratingSum += item.rating!;
          ratingCount++;
        }
        catCounts[item.categoryId] = (catCounts[item.categoryId] ?? 0) + 1;
      }
    }

    String? topCatName;
    int topCatHits = 0;
    catCounts.forEach((cid, cnt) {
      if (cnt > topCatHits) {
        topCatHits = cnt;
        topCatName = catNames[cid] ?? cid;
      }
    });
    final avgRating = ratingCount > 0 ? ratingSum / ratingCount : null;
    final avgSpendPerSession =
        periodSessions.isNotEmpty && pricedItems > 0
            ? (totalSpend / periodSessions.length).round()
            : null;

    // Group filteredSessions by localDate
    final grouped = <String, List<MealSessionRecord>>{};
    for (final s in filteredSessions) {
      grouped.putIfAbsent(s.localDate, () => []).add(s);
    }
    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
      children: [
        // 1. Period Segmented Selector (Harian / Bulanan / Tahunan / Semua)
        SegmentedButton<_HistoryPeriod>(
          showSelectedIcon: false,
          segments: _HistoryPeriod.values
              .map(
                (p) => ButtonSegment(
                  value: p,
                  label: Text(
                    p.label,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                  ),
                ),
              )
              .toList(),
          selected: {_period},
          onSelectionChanged: (s) {
            setState(() {
              _period = s.first;
              _anchorDate = DateTime.now();
            });
          },
        ),

        // 2. Date / Month / Year Stepper
        if (_period != _HistoryPeriod.all) ...[
          const SizedBox(height: 10),
          GamePanel(
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Sebelumnya',
                  onPressed: () => _shiftAnchor(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        _periodHeaderLabel(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Fredoka',
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _anchorDate = DateTime.now()),
                  child: const Text('Sekarang', style: TextStyle(fontSize: 12)),
                ),
                IconButton(
                  tooltip: 'Berikutnya',
                  onPressed: () => _shiftAnchor(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 12),

        // 3. Total Summary Stats Panel
        GamePanel(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFF2E8), Color(0xFFFFFAF2)],
          ),
          borderColor: MamPetColors.coralPrimary,
          lipColor: MamPetColors.coralDeep,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.insights_rounded,
                      color: MamPetColors.coralPrimary, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    'Rekap ${_periodHeaderLabel()}',
                    style: const TextStyle(
                      fontFamily: 'Fredoka',
                      fontWeight: FontWeight.w700,
                      fontSize: 15.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StatMiniTile(
                      icon: Icons.restaurant_rounded,
                      color: MamPetColors.coralPrimary,
                      value: '${periodSessions.length} sesi',
                      caption: '$totalItems porsi menu',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatMiniTile(
                      icon: Icons.payments_rounded,
                      color: MamPetColors.sageAccent,
                      value: pricedItems > 0
                          ? MamPetFormatters.formatRupiah(totalSpend)
                          : 'Rp 0',
                      caption: avgSpendPerSession != null
                          ? 'Rata² ${MamPetFormatters.formatRupiah(avgSpendPerSession)}/sesi'
                          : 'Belum ada harga',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _StatMiniTile(
                      icon: Icons.photo_camera_rounded,
                      color: MamPetColors.skyAccent,
                      value: '$totalPhotosInPeriod foto',
                      caption: avgRating != null
                          ? 'Rata² ★ ${avgRating.toStringAsFixed(1)}/5'
                          : 'Belum ada rating',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatMiniTile(
                      icon: Icons.favorite_rounded,
                      color: MamPetColors.honeySecondary,
                      value: topCatName ?? '-',
                      caption: topCatName != null
                          ? 'Kategori terbanyak ($topCatHits×)'
                          : 'Kategori favorit',
                    ),
                  ),
                ],
              ),
              // Interactive breakdown bars for Monthly / Yearly
              if (_period == _HistoryPeriod.yearly && periodSessions.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text(
                  'Tren Sesi per Bulan (ketuk bulan untuk detail):',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: MamPetColors.cocoaMuted,
                  ),
                ),
                const SizedBox(height: 8),
                _buildYearlyBarChart(periodSessions),
              ] else if (_period == _HistoryPeriod.monthly &&
                  periodSessions.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text(
                  'Sebaran Makan per Minggu:',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: MamPetColors.cocoaMuted,
                  ),
                ),
                const SizedBox(height: 8),
                _buildMonthlyWeekBars(periodSessions),
              ],
            ],
          ),
        ),

        const SizedBox(height: 14),

        // 4. Search + Meal Type Filter
        TextField(
          controller: _searchCtrl,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Cari makanan, tempat, atau catatan...',
            prefixIcon: const Icon(Icons.search_rounded),
            isDense: true,
            suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.close_rounded),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: const Text('Semua'),
                  selected: _typeFilter == null,
                  onSelected: (_) => setState(() => _typeFilter = null),
                ),
              ),
              ...MealType.values.map(
                (t) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(t.label),
                    selected: _typeFilter == t,
                    onSelected: (_) => setState(() => _typeFilter = t),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 5. Grouped Session List
        if (sortedDates.isEmpty)
          GamePanel(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(Icons.receipt_long_rounded,
                    size: 40, color: MamPetColors.cocoaMuted),
                const SizedBox(height: 8),
                Text(
                  'Belum ada catatan makan di ${_periodHeaderLabel()}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Fredoka',
                    fontWeight: FontWeight.w700,
                    fontSize: 15.5,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Mulai dokumentasikan makanan beserta foto & tempatnya!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: MamPetColors.cocoaMuted),
                ),
                const SizedBox(height: 12),
                GameButton(
                  label: 'Catat Makan Sekarang',
                  icon: Icons.add_rounded,
                  compact: true,
                  height: 42,
                  onPressed: () => context.push('/log/new'),
                ),
              ],
            ),
          )
        else
          for (final dateStr in sortedDates) ...[
            _buildDayHeader(dateStr, grouped[dateStr]!),
            const SizedBox(height: 6),
            for (final s in grouped[dateStr]!)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildSessionCard(context, s, allPhotos),
              ),
            const SizedBox(height: 6),
          ],
      ],
    );
  }

  Widget _buildDayHeader(String dateStr, List<MealSessionRecord> daySessions) {
    final dayTotalSpend = daySessions.fold<int>(
      0,
      (sum, s) => sum + (s.totalPriceMinor ?? 0),
    );
    final dt = daySessions.first.occurredAt;
    final label = '${dt.day} ${_monthShort[dt.month - 1]} ${dt.year}';
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Fredoka',
            fontWeight: FontWeight.w700,
            fontSize: 14.5,
            color: MamPetColors.espresso,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${daySessions.length} sesi',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: MamPetColors.cocoaMuted,
          ),
        ),
        const Spacer(),
        if (dayTotalSpend > 0)
          Text(
            MamPetFormatters.formatRupiah(dayTotalSpend),
            style: const TextStyle(
              fontFamily: 'Fredoka',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: MamPetColors.sageAccent,
            ),
          ),
      ],
    );
  }

  Widget _buildSessionCard(
    BuildContext context,
    MealSessionRecord s,
    List<_GalleryPhotoEntry> allPhotos,
  ) {
    final firstPhotoItem = s.items
        .where((i) => i.photoPath != null && File(i.photoPath!).existsSync())
        .firstOrNull;
    final photoPath = firstPhotoItem?.photoPath;

    final ratings = s.items.map((e) => e.rating).whereType<int>().toList();
    final avgStar = ratings.isEmpty
        ? null
        : ratings.reduce((a, b) => a + b) / ratings.length;

    final notesPreview = s.items
            .map((e) => e.description)
            .where((d) => d != null && d.trim().isNotEmpty)
            .firstOrNull ??
        s.notes;

    return GamePanel(
      radius: 20,
      padding: const EdgeInsets.all(12),
      onTap: () => context.push('/log/edit/${s.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo thumbnail (tappable for full gallery view) or meal icon
              GestureDetector(
                onTap: photoPath != null
                    ? () {
                        final idx = allPhotos.indexWhere(
                          (e) =>
                              e.session.id == s.id &&
                              e.item.id == firstPhotoItem!.id,
                        );
                        if (idx >= 0) _openPhotoViewer(allPhotos, idx);
                      }
                    : null,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: photoPath != null
                      ? Image.file(
                          File(photoPath),
                          width: 62,
                          height: 62,
                          fit: BoxFit.cover,
                          cacheWidth: 180,
                        )
                      : Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: MamPetColors.coralSoft,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            s.mealType.icon,
                            color: MamPetColors.coralPrimary,
                            size: 26,
                          ),
                        ),
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
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: MamPetColors.coralSoft,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            s.mealType.label,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: MamPetColors.coralPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          MamPetFormatters.formatTime(s.occurredAt),
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: MamPetColors.cocoaMuted,
                          ),
                        ),
                        if (avgStar != null) ...[
                          const Spacer(),
                          const Icon(Icons.star_rounded,
                              size: 14, color: MamPetColors.honeySecondary),
                          Text(
                            avgStar.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.items.map((e) => e.displayName).join(', '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${s.placeDisplayLabel}${s.totalPriceMinor != null ? ' • ${MamPetFormatters.formatRupiah(s.totalPriceMinor)}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: MamPetColors.cocoaMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (notesPreview != null && notesPreview.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        notesPreview.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic,
                          color: MamPetColors.cocoaMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (s.place != null)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () => MealShareService.openInGoogleMaps(s.place!),
                  icon: const Icon(Icons.map_rounded, size: 15),
                  label: const Text('GMaps', style: TextStyle(fontSize: 12)),
                ),
              const Spacer(),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF15803D),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                onPressed: () => _shareSessionWa(s),
                icon: const Icon(Icons.share_rounded, size: 16),
                label: const Text(
                  'Share WA',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: () => context.push('/log/edit/${s.id}'),
                icon: const Icon(Icons.edit_outlined, size: 15),
                label: const Text('Edit', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildYearlyBarChart(List<MealSessionRecord> yearSessions) {
    final counts = List<int>.filled(12, 0);
    for (final s in yearSessions) {
      counts[s.occurredAt.month - 1]++;
    }
    final maxCount = counts.reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: 86,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(12, (idx) {
          final cnt = counts[idx];
          final frac = maxCount > 0 ? cnt / maxCount : 0.0;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _period = _HistoryPeriod.monthly;
                  _anchorDate = DateTime(_anchorDate.year, idx + 1, 1);
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (cnt > 0)
                      Text(
                        '$cnt',
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: MamPetColors.coralPrimary,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Container(
                      height: (46 * frac).clamp(4.0, 46.0),
                      decoration: BoxDecoration(
                        color: cnt > 0
                            ? MamPetColors.coralPrimary
                            : MamPetColors.warmOutline.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _monthShort[idx],
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: MamPetColors.cocoaMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildMonthlyWeekBars(List<MealSessionRecord> monthSessions) {
    final weekCounts = List<int>.filled(5, 0);
    final weekSpend = List<int>.filled(5, 0);
    for (final s in monthSessions) {
      final w = ((s.occurredAt.day - 1) ~/ 7).clamp(0, 4);
      weekCounts[w]++;
      weekSpend[w] += s.totalPriceMinor ?? 0;
    }
    final maxCount = weekCounts.reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: 76,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(5, (idx) {
          final cnt = weekCounts[idx];
          final frac = maxCount > 0 ? cnt / maxCount : 0.0;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    cnt > 0 ? '${cnt}×' : '-',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: MamPetColors.coralPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    height: (36 * frac).clamp(4.0, 36.0),
                    decoration: BoxDecoration(
                      color: cnt > 0
                          ? MamPetColors.coralPrimary
                          : MamPetColors.warmOutline.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Mg ${idx + 1}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: MamPetColors.cocoaMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildGalleryTab(
    BuildContext context, {
    required List<_GalleryPhotoEntry> allPhotos,
    required List<_GalleryPhotoEntry> filteredPhotos,
    required List<FoodCategory> categories,
  }) {
    return Column(
      children: [
        // Gallery filter bar
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  selected: _galleryCategoryFilter == null && !_galleryFiveStarOnly,
                  label: Text('Semua (${allPhotos.length})'),
                  onSelected: (_) => setState(() {
                    _galleryCategoryFilter = null;
                    _galleryFiveStarOnly = false;
                  }),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  avatar: const Icon(Icons.star_rounded,
                      size: 16, color: MamPetColors.honeySecondary),
                  selected: _galleryFiveStarOnly,
                  label: const Text('5 Bintang'),
                  onSelected: (v) => setState(() => _galleryFiveStarOnly = v),
                ),
              ),
              ...categories.map((c) {
                final sel = _galleryCategoryFilter == c.id;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    selected: sel,
                    label: Text(c.name),
                    onSelected: (_) => setState(
                      () => _galleryCategoryFilter = sel ? null : c.id,
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: filteredPhotos.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: const BoxDecoration(
                            color: MamPetColors.coralSoft,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.photo_camera_back_rounded,
                            size: 40,
                            color: MamPetColors.coralPrimary,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          allPhotos.isEmpty
                              ? 'Galeri Foto Makananmu Masih Kosong'
                              : 'Tidak ada foto yang cocok dengan filter ini',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Fredoka',
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Tambahkan foto saat mencatat makan agar seluruh kenangan kulinermu tersimpan rapi di sini dan siap dibagikan ke WhatsApp!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: MamPetColors.cocoaMuted,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 16),
                        GameButton(
                          label: 'Catat & Foto Makanan',
                          icon: Icons.camera_alt_rounded,
                          compact: true,
                          height: 44,
                          onPressed: () => context.push('/log/new'),
                        ),
                      ],
                    ),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                    childAspectRatio: 0.92,
                  ),
                  itemCount: filteredPhotos.length,
                  itemBuilder: (context, idx) {
                    final entry = filteredPhotos[idx];
                    final dt = entry.session.occurredAt;
                    return GestureDetector(
                      onTap: () => _openPhotoViewer(filteredPhotos, idx),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(
                              File(entry.photoPath),
                              fit: BoxFit.cover,
                              cacheWidth: 320,
                            ),
                            // Subtle dark bottom gradient for readable caption
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(6, 16, 6, 5),
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Colors.transparent, Colors.black87],
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      entry.item.displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 11,
                                      ),
                                    ),
                                    Text(
                                      '${dt.day} ${_monthShort[dt.month - 1]}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 9.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (entry.item.rating != null)
                              Positioned(
                                top: 5,
                                right: 5,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.star_rounded,
                                          size: 11,
                                          color: MamPetColors.honeySecondary),
                                      Text(
                                        '${entry.item.rating}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _StatMiniTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String caption;

  const _StatMiniTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Fredoka',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: MamPetColors.espresso,
                  ),
                ),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: MamPetColors.cocoaMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen interactive food photo viewer with pinch-to-zoom, swipe between
/// photos, full meal notes/place info, Google Maps launcher, and direct WhatsApp share!
class _FoodPhotoGalleryViewer extends StatefulWidget {
  final List<_GalleryPhotoEntry> entries;
  final int initialIndex;

  const _FoodPhotoGalleryViewer({
    required this.entries,
    required this.initialIndex,
  });

  @override
  State<_FoodPhotoGalleryViewer> createState() => _FoodPhotoGalleryViewerState();
}

class _FoodPhotoGalleryViewerState extends State<_FoodPhotoGalleryViewer> {
  late final PageController _pageCtrl;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entries[_currentIndex];
    final session = entry.session;
    final item = entry.item;

    return Scaffold(
      backgroundColor: const Color(0xFF14110F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(
          '${_currentIndex + 1} / ${widget.entries.length}',
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
        actions: [
          IconButton(
            tooltip: 'Edit Catatan',
            onPressed: () {
              Navigator.pop(context);
              context.push('/log/edit/${session.id}');
            },
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Bagikan ke Aplikasi Lain',
            onPressed: () => MealShareService.shareViaSystemSheet(
              session: session,
              focusItem: item,
            ),
            icon: const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageCtrl,
              itemCount: widget.entries.length,
              onPageChanged: (i) => setState(() => _currentIndex = i),
              itemBuilder: (_, i) {
                return InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 4.0,
                  child: Center(
                    child: Image.file(
                      File(widget.entries[i].photoPath),
                      fit: BoxFit.contain,
                    ),
                  ),
                );
              },
            ),
          ),
          // Rich bottom culinary info & direct WhatsApp Share action bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
            decoration: const BoxDecoration(
              color: Color(0xFF1F1916),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.displayName,
                          style: const TextStyle(
                            fontFamily: 'Fredoka',
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (item.rating != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(
                            5,
                            (sIdx) => Icon(
                              sIdx < item.rating!
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              size: 16,
                              color: MamPetColors.honeySecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${session.mealType.label} • ${MamPetFormatters.formatDateTime(session.occurredAt)}${item.priceMinor != null ? ' • ${MamPetFormatters.formatRupiah(item.priceMinor! * item.quantity)}' : ''}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.place_rounded,
                          size: 15, color: MamPetColors.coralPrimary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          session.place != null
                              ? '${session.place!.displayName}${session.place!.address != null ? ' — ${session.place!.address}' : ''}'
                              : session.placeDisplayLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      if (session.place != null)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: MamPetColors.skyAccent,
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () =>
                              MealShareService.openInGoogleMaps(session.place!),
                          icon: const Icon(Icons.map_rounded, size: 15),
                          label: const Text('Buka GMaps',
                              style: TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                  if ((item.description?.trim().isNotEmpty ?? false) ||
                      (session.notes?.trim().isNotEmpty ?? false)) ...[
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (item.description?.trim().isNotEmpty ?? false)
                          item.description!.trim(),
                        if (session.notes?.trim().isNotEmpty ?? false)
                          session.notes!.trim(),
                      ].join(' • '),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => MealShareService.shareToWhatsApp(
                        session: session,
                        focusItem: item,
                      ),
                      icon: const Icon(Icons.share_rounded),
                      label: const Text(
                        'Bagikan Foto & Lokasi ke WhatsApp',
                        style: TextStyle(
                          fontFamily: 'Fredoka',
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
