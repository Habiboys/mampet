import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../app/theme.dart';
import '../../core/domain/models.dart';
import '../../core/providers/app_providers.dart';
import '../../core/utils/formatters.dart';

class CulinaryMapScreen extends ConsumerStatefulWidget {
  const CulinaryMapScreen({super.key});

  @override
  ConsumerState<CulinaryMapScreen> createState() => _CulinaryMapScreenState();
}

class _CulinaryMapScreenState extends ConsumerState<CulinaryMapScreen> {
  bool _showListMode = false;
  bool _hasLocationPermission = false;
  String? _categoryFilter;
  int? _maxPriceFilter; // null = any
  int? _daysFilter; // null = all, 7, 30
  final TextEditingController _searchCtrl = TextEditingController();
  GoogleMapController? _mapController;

  static const _defaultCenter = LatLng(-6.2088, 106.8456);

  @override
  void initState() {
    super.initState();
    _checkLocationPermissionQuietly();
  }

  Future<void> _checkLocationPermissionQuietly() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (!mounted) return;
      setState(() {
        _hasLocationPermission = perm == LocationPermission.always ||
            perm == LocationPermission.whileInUse;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _openPlaceDetailSheet(
    BuildContext context,
    PlaceModel place,
    List<MealSessionRecord> sessionsAtPlace,
  ) {
    final pricedTotals = sessionsAtPlace
        .map((s) => s.totalPriceMinor)
        .whereType<int>()
        .toList()
      ..sort();
    final median = pricedTotals.isEmpty
        ? null
        : pricedTotals.length.isOdd
            ? pricedTotals[pricedTotals.length ~/ 2]
            : ((pricedTotals[pricedTotals.length ~/ 2 - 1] +
                        pricedTotals[pricedTotals.length ~/ 2]) /
                    2)
                .round();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.56,
          minChildSize: 0.35,
          maxChildSize: 0.88,
          expand: false,
          builder: (_, scrollCtrl) {
            return ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: MamPetColors.coralSoft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.place_rounded,
                          color: MamPetColors.coralPrimary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            place.displayName,
                            style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          if (place.address != null)
                            Text(
                              place.address!,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: MamPetColors.cocoaMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _miniStat('Kunjungan', '${sessionsAtPlace.length} sesi'),
                    const SizedBox(width: 8),
                    _miniStat(
                      'Median Sesi',
                      median != null
                          ? MamPetFormatters.formatRupiah(median)
                          : 'Tanpa harga',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Riwayat di Tempat Ini',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                ),
                const SizedBox(height: 8),
                if (sessionsAtPlace.isEmpty)
                  const Text(
                    'Belum ada sesi makan yang cocok dengan filter di tempat ini.',
                    style: TextStyle(color: MamPetColors.cocoaMuted),
                  )
                else
                  ...sessionsAtPlace.map(
                    (s) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(
                          s.items.map((e) => e.displayName).join(', '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '${s.mealType.label} • ${MamPetFormatters.formatDateTime(s.occurredAt)} • ${MamPetFormatters.formatRupiah(s.totalPriceMinor)}',
                        ),
                        trailing: const Icon(Icons.edit_outlined, size: 18),
                        onTap: () {
                          Navigator.pop(ctx);
                          context.push('/log/edit/${s.id}');
                        },
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _miniStat(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MamPetColors.warmSurfaceAlt,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 11.5, color: MamPetColors.cocoaMuted)),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 14.5)),
          ],
        ),
      ),
    );
  }

  void _openFilterSheet(List<FoodCategory> categories) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            void upd(VoidCallback fn) {
              fn();
              setLocal(() {});
              setState(() {});
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Filter Peta Kuliner',
                          style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => upd(() {
                            _categoryFilter = null;
                            _maxPriceFilter = null;
                            _daysFilter = null;
                          }),
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text('Rentang Waktu',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Semua'),
                          selected: _daysFilter == null,
                          onSelected: (_) => upd(() => _daysFilter = null),
                        ),
                        ChoiceChip(
                          label: const Text('7 Hari'),
                          selected: _daysFilter == 7,
                          onSelected: (_) => upd(() => _daysFilter = 7),
                        ),
                        ChoiceChip(
                          label: const Text('30 Hari'),
                          selected: _daysFilter == 30,
                          onSelected: (_) => upd(() => _daysFilter = 30),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('Batas Harga Sesi',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Semua'),
                          selected: _maxPriceFilter == null,
                          onSelected: (_) => upd(() => _maxPriceFilter = null),
                        ),
                        ChoiceChip(
                          label: const Text('≤ Rp25rb'),
                          selected: _maxPriceFilter == 25000,
                          onSelected: (_) => upd(() => _maxPriceFilter = 25000),
                        ),
                        ChoiceChip(
                          label: const Text('≤ Rp50rb'),
                          selected: _maxPriceFilter == 50000,
                          onSelected: (_) => upd(() => _maxPriceFilter = 50000),
                        ),
                        ChoiceChip(
                          label: const Text('≤ Rp100rb'),
                          selected: _maxPriceFilter == 100000,
                          onSelected: (_) =>
                              upd(() => _maxPriceFilter = 100000),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('Kategori',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String?>(
                      initialValue: _categoryFilter,
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Semua Kategori'),
                        ),
                        ...categories.map(
                          (c) => DropdownMenuItem<String?>(
                            value: c.id,
                            child: Text(c.name),
                          ),
                        ),
                      ],
                      onChanged: (v) => upd(() => _categoryFilter = v),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Terapkan'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final places = ref.watch(placesProvider).valueOrNull ?? const [];
    final allSessions =
        ref.watch(allMealSessionsProvider).valueOrNull ?? const [];
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];

    final now = DateTime.now();
    final query = _searchCtrl.text.trim().toLowerCase();

    final filteredSessions = allSessions.where((s) {
      if (s.placeId == null) return false;
      if (_daysFilter != null &&
          now.difference(s.occurredAt).inDays > _daysFilter!) {
        return false;
      }
      if (_categoryFilter != null &&
          !s.items.any((i) => i.categoryId == _categoryFilter)) {
        return false;
      }
      if (_maxPriceFilter != null) {
        final total = s.totalPriceMinor;
        if (total == null || total > _maxPriceFilter!) return false;
      }
      return true;
    }).toList();

    final sessionsByPlace = <String, List<MealSessionRecord>>{};
    for (final s in filteredSessions) {
      sessionsByPlace.putIfAbsent(s.placeId!, () => []).add(s);
    }

    final hasFilters = _categoryFilter != null ||
        _maxPriceFilter != null ||
        _daysFilter != null;

    final visiblePlaces = places.where((p) {
      if (query.isNotEmpty &&
          !p.displayName.toLowerCase().contains(query) &&
          !(p.address?.toLowerCase().contains(query) ?? false)) {
        return false;
      }
      if (hasFilters && !sessionsByPlace.containsKey(p.id)) {
        return false;
      }
      return true;
    }).toList();

    final pinnedPlaces = visiblePlaces.where((p) => p.hasCoordinates).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Peta Kuliner'),
        actions: [
          IconButton(
            tooltip: 'Filter peta',
            onPressed: () => _openFilterSheet(categories),
            icon: Badge(
              isLabelVisible: hasFilters,
              child: const Icon(Icons.tune_rounded),
            ),
          ),
          IconButton(
            tooltip: _showListMode ? 'Tampilan Google Maps' : 'Tampilan Daftar',
            onPressed: () => setState(() => _showListMode = !_showListMode),
            icon:
                Icon(_showListMode ? Icons.map_rounded : Icons.list_alt_rounded),
          ),
        ],
      ),
      body: places.isEmpty
          ? _buildEmptyState(context)
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Cari nama tempat...',
                            prefixIcon: const Icon(Icons.search_rounded),
                            isDense: true,
                            suffixIcon: query.isNotEmpty
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
                      ),
                      const SizedBox(width: 8),
                      SegmentedButton<bool>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                              value: false, icon: Icon(Icons.map_outlined)),
                          ButtonSegment(
                              value: true, icon: Icon(Icons.list_rounded)),
                        ],
                        selected: {_showListMode},
                        onSelectionChanged: (s) =>
                            setState(() => _showListMode = s.first),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _showListMode
                      ? _buildPlacesList(visiblePlaces, sessionsByPlace)
                      : _buildGoogleMapView(
                          pinnedPlaces, visiblePlaces, sessionsByPlace),
                ),
              ],
            ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: const BoxDecoration(
                color: MamPetColors.coralSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add_location_alt_rounded,
                size: 48,
                color: MamPetColors.coralPrimary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Belum Ada Tempat di Peta Kuliner',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tambahkan tempat saat mencatat sesi makan untuk membangun peta kuliner pribadimu dengan Google Maps. Lokasi selalu opsional dan privat.',
              textAlign: TextAlign.center,
              style: TextStyle(color: MamPetColors.cocoaMuted, height: 1.45),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => context.go('/log'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Catat Makanan & Tambah Tempat'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoogleMapView(
    List<PlaceModel> pinnedPlaces,
    List<PlaceModel> visiblePlaces,
    Map<String, List<MealSessionRecord>> sessionsByPlace,
  ) {
    final initialCenter = pinnedPlaces.isNotEmpty
        ? LatLng(pinnedPlaces.first.lat!, pinnedPlaces.first.lng!)
        : _defaultCenter;

    final markers = pinnedPlaces.map((pl) {
      final sessions = sessionsByPlace[pl.id] ?? const [];
      return Marker(
        markerId: MarkerId(pl.id),
        position: LatLng(pl.lat!, pl.lng!),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow(
          title: pl.displayName,
          snippet: '${sessions.length} catatan makan • Ketuk detail',
          onTap: () => _openPlaceDetailSheet(context, pl, sessions),
        ),
        onTap: () => _openPlaceDetailSheet(context, pl, sessions),
      );
    }).toSet();

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: initialCenter,
            zoom: pinnedPlaces.isNotEmpty ? 13.5 : 11.5,
          ),
          markers: markers,
          myLocationEnabled: _hasLocationPermission,
          myLocationButtonEnabled: _hasLocationPermission,
          mapToolbarEnabled: true,
          zoomControlsEnabled: true,
          onMapCreated: (ctrl) => _mapController = ctrl,
        ),
        Positioned(
          top: 10,
          left: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color?.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: MamPetColors.warmOutline),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on_rounded,
                    size: 16, color: MamPetColors.coralPrimary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Google Maps • ${pinnedPlaces.length} pin • ${visiblePlaces.length} tempat. Offline? Pilih tampilan Daftar.',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlacesList(
    List<PlaceModel> visiblePlaces,
    Map<String, List<MealSessionRecord>> sessionsByPlace,
  ) {
    if (visiblePlaces.isEmpty) {
      return const Center(
        child: Text(
          'Tidak ada tempat yang cocok dengan filter.',
          style: TextStyle(color: MamPetColors.cocoaMuted),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
      itemCount: visiblePlaces.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, idx) {
        final pl = visiblePlaces[idx];
        final sessions = sessionsByPlace[pl.id] ?? const [];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: MamPetColors.coralSoft,
              child: Icon(
                pl.hasCoordinates
                    ? Icons.place_rounded
                    : Icons.storefront_rounded,
                color: MamPetColors.coralPrimary,
              ),
            ),
            title: Text(pl.displayName,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(
              '${sessions.length} catatan makan${pl.address != null ? ' • ${pl.address}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _openPlaceDetailSheet(context, pl, sessions),
          ),
        );
      },
    );
  }
}
