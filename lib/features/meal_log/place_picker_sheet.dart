import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../app/theme.dart';
import '../../core/domain/enums.dart';
import '../../core/domain/models.dart';
import '../../core/providers/app_providers.dart';

class PlaceSelectionResult {
  final PlaceMode mode;
  final PlaceModel? place;

  const PlaceSelectionResult({required this.mode, this.place});
}

Future<PlaceSelectionResult?> showPlacePickerSheet(
  BuildContext context, {
  PlaceMode initialMode = PlaceMode.none,
  PlaceModel? initialPlace,
}) {
  return showModalBottomSheet<PlaceSelectionResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: false, // Prevents bottom sheet drag from stealing Google Maps pan/zoom gestures!
    showDragHandle: false,
    builder: (_) => _PlacePickerBody(
      initialMode: initialMode,
      initialPlace: initialPlace,
    ),
  );
}

class _PlacePickerBody extends ConsumerStatefulWidget {
  final PlaceMode initialMode;
  final PlaceModel? initialPlace;

  const _PlacePickerBody({
    required this.initialMode,
    this.initialPlace,
  });

  @override
  ConsumerState<_PlacePickerBody> createState() => _PlacePickerBodyState();
}

class _PlacePickerBodyState extends ConsumerState<_PlacePickerBody> {
  bool _creatingNew = false;
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  LatLng? _pickedPoint;
  GoogleMapController? _pickerMapCtrl;
  bool _locating = false;
  String? _locationNotice;

  static const _defaultCenter = LatLng(-6.2088, 106.8456);

  /// Eager gesture recognizer so GoogleMap inside a ListView/BottomSheet
  /// receives 100% of pinch-zoom, double-tap zoom, and pan gestures smoothly.
  static final Set<Factory<OneSequenceGestureRecognizer>> _mapGestures = {
    Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
  };

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _pickerMapCtrl?.dispose();
    super.dispose();
  }

  Future<void> _tryCurrentGps() async {
    setState(() {
      _locating = true;
      _locationNotice = null;
    });
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _locationNotice =
            'Layanan lokasi mati. Kamu tetap bisa mengetuk peta atau menyimpan tanpa pin GPS.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() => _locationNotice =
            'Izin lokasi ditolak. Tidak masalah — isi nama tempat manual atau ketuk peta.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      final pt = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _pickedPoint = pt;
        _locationNotice = 'Titik lokasi saat ini berhasil diambil!';
      });
      await _pickerMapCtrl?.animateCamera(CameraUpdate.newLatLngZoom(pt, 16.5));
    } catch (_) {
      setState(() => _locationNotice =
          'Gagal mengambil GPS. Kamu tetap bisa simpan tempat secara manual.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _openFullScreenMapPicker() async {
    final chosen = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullScreenPinPickerPage(
          initialPoint: _pickedPoint ?? _defaultCenter,
          hasInitialPin: _pickedPoint != null,
        ),
      ),
    );
    if (chosen != null && mounted) {
      setState(() => _pickedPoint = chosen);
      await _pickerMapCtrl?.animateCamera(CameraUpdate.newLatLngZoom(chosen, 16.5));
    }
  }

  Future<void> _saveNewPlace() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Isi nama tempat terlebih dahulu.')),
      );
      return;
    }
    final created = await ref.read(databaseProvider).createPlace(
          displayName: name,
          lat: _pickedPoint?.latitude,
          lng: _pickedPoint?.longitude,
          address: _addressCtrl.text.trim(),
          source: _pickedPoint != null ? 'device' : 'manual',
        );
    if (mounted) {
      Navigator.pop(
        context,
        PlaceSelectionResult(mode: PlaceMode.place, place: created),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final places = ref.watch(placesProvider).valueOrNull ?? const [];

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.88,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
            child: Row(
              children: [
                if (_creatingNew)
                  IconButton(
                    onPressed: () => setState(() => _creatingNew = false),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                Expanded(
                  child: Text(
                    _creatingNew
                        ? 'Tambah Tempat Baru'
                        : 'Pilih Lokasi Makan (Opsional)',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'Tutup',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _creatingNew ? _buildCreatePlaceForm() : _buildPickList(places),
          ),
        ],
      ),
    );
  }

  Widget _buildPickList(List<PlaceModel> places) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        const Text(
          'Lokasi tidak wajib dan tidak memengaruhi XP. Koordinat rumah tidak pernah disimpan.',
          style: TextStyle(fontSize: 12.5, color: MamPetColors.cocoaMuted),
        ),
        const SizedBox(height: 14),
        ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: widget.initialMode == PlaceMode.none
                  ? MamPetColors.coralPrimary
                  : MamPetColors.warmOutline,
            ),
          ),
          leading: const Icon(Icons.location_off_outlined),
          title: const Text('Tanpa lokasi',
              style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Catat makanan tanpa menautkan tempat'),
          onTap: () => Navigator.pop(
            context,
            const PlaceSelectionResult(mode: PlaceMode.none),
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: widget.initialMode == PlaceMode.home
                  ? MamPetColors.coralPrimary
                  : MamPetColors.warmOutline,
            ),
          ),
          leading:
              const Icon(Icons.home_outlined, color: MamPetColors.sageAccent),
          title: const Text('Rumah (tanpa pin)',
              style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Privasi terjaga — koordinat GPS tidak disimpan'),
          onTap: () => Navigator.pop(
            context,
            const PlaceSelectionResult(mode: PlaceMode.home),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Tempat Tersimpan',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            FilledButton.tonalIcon(
              onPressed: () => setState(() => _creatingNew = true),
              icon: const Icon(Icons.add_location_alt_outlined, size: 18),
              label: const Text('Tempat Baru'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (places.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'Belum ada tempat kuliner tersimpan. Tekan "Tempat Baru" untuk menambah warung, kafe, atau restoran.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: MamPetColors.cocoaMuted),
            ),
          )
        else
          ...places.map((pl) {
            final selected = widget.initialPlace?.id == pl.id;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: selected
                        ? MamPetColors.coralPrimary
                        : MamPetColors.warmOutline,
                    width: selected ? 2 : 1,
                  ),
                ),
                leading: Icon(
                  pl.hasCoordinates
                      ? Icons.place_rounded
                      : Icons.storefront_rounded,
                  color: MamPetColors.coralPrimary,
                ),
                title: Text(pl.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  pl.address ??
                      (pl.hasCoordinates
                          ? 'Pin Google Maps tersimpan'
                          : 'Tanpa pin koordinat'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(
                  context,
                  PlaceSelectionResult(mode: PlaceMode.place, place: pl),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildCreatePlaceForm() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        TextField(
          controller: _nameCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nama tempat *',
            hintText: 'Contoh: Warung Nasi Telur Pak Budi',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _addressCtrl,
          decoration: const InputDecoration(
            labelText: 'Alamat / catatan lokasi (opsional)',
            hintText: 'Contoh: Jl. Merdeka No. 12',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _locating ? null : _tryCurrentGps,
                icon: _locating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location_rounded, size: 18),
                label: const Text('GPS Saat Ini'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _openFullScreenMapPicker,
              icon: const Icon(Icons.open_in_full_rounded, size: 17),
              label: const Text('Layar Penuh'),
            ),
            if (_pickedPoint != null) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Hapus pin',
                onPressed: () => setState(() => _pickedPoint = null),
                icon: const Icon(Icons.clear_rounded),
              ),
            ],
          ],
        ),
        if (_locationNotice != null) ...[
          const SizedBox(height: 8),
          Text(
            _locationNotice!,
            style: const TextStyle(fontSize: 12, color: MamPetColors.cocoaMuted),
          ),
        ],
        const SizedBox(height: 10),
        const Text(
          'Cubitan 2 jari untuk zoom, geser peta, lalu ketuk untuk menaruh pin:',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: 268,
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _pickedPoint ?? _defaultCenter,
                    zoom: 14.0,
                  ),
                  gestureRecognizers: _mapGestures,
                  zoomGesturesEnabled: true,
                  scrollGesturesEnabled: true,
                  rotateGesturesEnabled: true,
                  tiltGesturesEnabled: false,
                  zoomControlsEnabled: false, // Using crisp custom zoom buttons below
                  mapToolbarEnabled: false,
                  onMapCreated: (ctrl) => _pickerMapCtrl = ctrl,
                  onTap: (latLng) => setState(() => _pickedPoint = latLng),
                  markers: _pickedPoint != null
                      ? {
                          Marker(
                            markerId: const MarkerId('picked_pin'),
                            position: _pickedPoint!,
                            draggable: true,
                            onDragEnd: (pos) =>
                                setState(() => _pickedPoint = pos),
                            icon: BitmapDescriptor.defaultMarkerWithHue(
                              BitmapDescriptor.hueOrange,
                            ),
                          ),
                        }
                      : const {},
                ),
                // Reliable +/- zoom buttons accessible with one thumb
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _MapMiniButton(
                        icon: Icons.add_rounded,
                        tooltip: 'Perbesar Peta',
                        onTap: () =>
                            _pickerMapCtrl?.animateCamera(CameraUpdate.zoomIn()),
                      ),
                      const SizedBox(height: 6),
                      _MapMiniButton(
                        icon: Icons.remove_rounded,
                        tooltip: 'Perkecil Peta',
                        onTap: () =>
                            _pickerMapCtrl?.animateCamera(CameraUpdate.zoomOut()),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_pickedPoint != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Pin: ${_pickedPoint!.latitude.toStringAsFixed(5)}, ${_pickedPoint!.longitude.toStringAsFixed(5)}',
              style:
                  const TextStyle(fontSize: 11.5, color: MamPetColors.cocoaMuted),
            ),
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _saveNewPlace,
          icon: const Icon(Icons.check_rounded),
          label: const Text('Simpan & Gunakan Tempat Ini'),
        ),
      ],
    );
  }
}

class _MapMiniButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _MapMiniButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.94),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(icon, size: 22, color: MamPetColors.espresso),
          ),
        ),
      ),
    );
  }
}

class _FullScreenPinPickerPage extends StatefulWidget {
  final LatLng initialPoint;
  final bool hasInitialPin;

  const _FullScreenPinPickerPage({
    required this.initialPoint,
    required this.hasInitialPin,
  });

  @override
  State<_FullScreenPinPickerPage> createState() =>
      _FullScreenPinPickerPageState();
}

class _FullScreenPinPickerPageState extends State<_FullScreenPinPickerPage> {
  LatLng? _pin;
  GoogleMapController? _ctrl;

  @override
  void initState() {
    super.initState();
    _pin = widget.hasInitialPin ? widget.initialPoint : null;
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pilih Titik Google Maps'),
        actions: [
          FilledButton(
            onPressed: _pin == null ? null : () => Navigator.pop(context, _pin),
            child: const Text('Pakai Pin'),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: widget.initialPoint,
              zoom: 15.0,
            ),
            zoomGesturesEnabled: true,
            scrollGesturesEnabled: true,
            rotateGesturesEnabled: true,
            zoomControlsEnabled: false,
            onMapCreated: (c) => _ctrl = c,
            onTap: (p) => setState(() => _pin = p),
            markers: _pin != null
                ? {
                    Marker(
                      markerId: const MarkerId('fs_pin'),
                      position: _pin!,
                      draggable: true,
                      onDragEnd: (p) => setState(() => _pin = p),
                      icon: BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueOrange,
                      ),
                    ),
                  }
                : const {},
          ),
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Material(
              color: Colors.white.withValues(alpha: 0.94),
              elevation: 2,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Text(
                  _pin == null
                      ? 'Cubitan 2 jari untuk zoom, lalu ketuk peta untuk menaruh pin.'
                      : 'Pin terpilih: ${_pin!.latitude.toStringAsFixed(5)}, ${_pin!.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: MamPetColors.espresso,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 14,
            bottom: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MapMiniButton(
                  icon: Icons.add_rounded,
                  tooltip: 'Perbesar',
                  onTap: () => _ctrl?.animateCamera(CameraUpdate.zoomIn()),
                ),
                const SizedBox(height: 8),
                _MapMiniButton(
                  icon: Icons.remove_rounded,
                  tooltip: 'Perkecil',
                  onTap: () => _ctrl?.animateCamera(CameraUpdate.zoomOut()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
