import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/theme.dart';
import '../../core/domain/models.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/home_widget_service.dart';
import '../../core/utils/formatters.dart';

class ProfileSettingsScreen extends ConsumerStatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  ConsumerState<ProfileSettingsScreen> createState() =>
      _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends ConsumerState<ProfileSettingsScreen> {
  bool _busyBackup = false;

  Future<void> _editNameDialog(String currentName) async {
    final ctrl = TextEditingController(text: currentName);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ubah Nama Panggilan'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nama panggilan',
            hintText: 'Kosongkan jika ingin "Penjelajah"',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (saved != null) {
      await ref.read(databaseProvider).updateDisplayName(saved);
    }
  }

  Future<void> _exportBackup() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Peringatan Privasi Backup'),
        content: const Text(
          'File cadangan ZIP berisi seluruh riwayat makan, foto makanan, tempat pribadi, dan koleksi monstermu.\n\nSimpan file ini di lokasi aman dan jangan bagikan ke sembarang orang.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Buat Cadangan ZIP'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    setState(() => _busyBackup = true);
    try {
      final res = await ref.read(backupServiceProvider).exportBackupZip();
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Backup ZIP Berhasil Dibuat'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Lokasi file:\n${res.zipFile.path}',
                  style: const TextStyle(fontSize: 12.5)),
              const SizedBox(height: 8),
              Text('Foto disertakan: ${res.photoCount}'),
              Text(
                'Checksum DB: ${res.dbSha256.substring(0, 14)}...',
                style:
                    const TextStyle(fontSize: 12, color: MamPetColors.cocoaMuted),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tutup'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await SharePlus.instance.share(
                  ShareParams(
                    files: [XFile(res.zipFile.path)],
                    subject: 'MamPet Backup ZIP',
                  ),
                );
              },
              icon: const Icon(Icons.share_rounded, size: 18),
              label: const Text('Simpan / Bagikan'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal ekspor backup: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyBackup = false);
    }
  }

  Future<void> _restoreBackup() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    final path = picked.isNotEmpty ? picked.first.path : null;
    if (path == null || !mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pulihkan Data dari Backup?'),
        content: const Text(
          'Data saat ini akan diganti dengan isi file backup. Aplikasi akan memvalidasi checksum & membuat salinan pengaman sementara sebelum memulihkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Pulihkan'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _busyBackup = true);
    try {
      final res = await ref
          .read(backupServiceProvider)
          .restoreFromBackupZip(File(path));
      if (!mounted) return;
      ref.invalidate(dbRevisionProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pemulihan berhasil! (Skema v${res.schemaVersion}, ${res.restoredPhotos} foto dipulihkan)',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memulihkan backup: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyBackup = false);
    }
  }

  Future<void> _confirmResetData() async {
    final confirmCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final match = confirmCtrl.text.trim().toUpperCase() == 'RESET';
            return AlertDialog(
              title: const Text('Reset Semua Data Lokal?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tindakan ini menghapus semua catatan makan, FoodDex, tempat, telur, dan koleksi monster secara permanen dari perangkat ini.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmCtrl,
                    onChanged: (_) => setLocal(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Ketik RESET untuk konfirmasi',
                      hintText: 'RESET',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Batal'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade600),
                  onPressed: match ? () => Navigator.pop(ctx, true) : null,
                  child: const Text('Hapus Semua Data'),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok != true || !mounted) return;

    await ref.read(databaseProvider).resetAllUserData();
    if (mounted) {
      context.go('/onboarding');
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final stats = ref.watch(personalStatsProvider).valueOrNull;

    final displayName = (profile?.displayName.isNotEmpty == true)
        ? profile!.displayName
        : 'Penjelajah MamPet';

    return Scaffold(
      appBar: AppBar(title: const Text('Profil & Pengaturan')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        children: [
          // Branded Profile Hero Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE3F5FF), Color(0xFFFFFBF5)],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: MamPetColors.warmOutline, width: 1.3),
              boxShadow: MamPetColors.softCardShadow(),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.asset(
                    'assets/branding/mampet_logo.png',
                    width: 60,
                    height: 60,
                    cacheWidth: 160,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          color: MamPetColors.espresso,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'MamPet v1.0 • 100% Lokal & Offline-First',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: MamPetColors.cocoaMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Ubah nama',
                  onPressed: () => _editNameDialog(profile?.displayName ?? ''),
                  icon: const Icon(Icons.edit_rounded, size: 19),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          if (stats != null) _buildStatsCard(stats),

          const SizedBox(height: 16),

          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.history_rounded,
                      color: MamPetColors.coralPrimary),
                  title: const Text('Semua Riwayat Catatan Makan',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/history'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.edit_note_rounded,
                      color: MamPetColors.skyAccent),
                  title: const Text('Kelola Makanan Custom',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/fooddex/custom'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Android Home Screen Moving Pet Widget Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.widgets_rounded,
                          color: MamPetColors.skyAccent),
                      SizedBox(width: 8),
                      Text(
                        'Widget Pet Layar Utama Android',
                        style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 15),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Taruh MamPet aktifmu langsung di layar utama HP! Pet akan bergerak-gerak ceria dan bisa diketuk untuk melihat reaksinya.',
                    style: TextStyle(
                        fontSize: 12.5, color: MamPetColors.cocoaMuted),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: () async {
                        final active =
                            ref.read(activeMonsterProvider).valueOrNull;
                        final reduce = settings?.reduceMotion ?? false;
                        if (active != null) {
                          await HomeWidgetService.syncActiveMonster(
                            monster: active,
                            reduceMotion: reduce,
                          );
                        }
                        final ok =
                            await HomeWidgetService.requestPinToHomeScreen();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok
                                  ? 'Konfirmasi dialog launcher untuk menempelkan Widget MamPet!'
                                  : 'Tekan tahan layar utama Android → Widget → pilih "MamPet Partner".',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.add_to_home_screen_rounded),
                      label: const Text('Pasang Widget Pet ke Layar Utama'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.backup_outlined,
                          color: MamPetColors.coralPrimary),
                      SizedBox(width: 8),
                      Text(
                        'Backup & Restore (ZIP)',
                        style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 15),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    settings?.lastBackupAt != null
                        ? 'Backup terakhir: ${MamPetFormatters.formatDateTime(DateTime.parse(settings!.lastBackupAt!))}'
                        : 'Belum pernah membuat cadangan. Disarankan mencadangkan data secara berkala.',
                    style: const TextStyle(
                        fontSize: 12.5, color: MamPetColors.cocoaMuted),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _busyBackup ? null : _exportBackup,
                          icon:
                              const Icon(Icons.upload_file_rounded, size: 18),
                          label: const Text('Ekspor ZIP'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busyBackup ? null : _restoreBackup,
                          icon: const Icon(Icons.restore_rounded, size: 18),
                          label: const Text('Pulihkan ZIP'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.motion_photos_off_rounded),
                  title: const Text('Reduce Motion (Kurangi Animasi)',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: const Text(
                    'Mematikan goyangan terus-menerus dan menyederhanakan animasi penetasan.',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: settings?.reduceMotion ?? false,
                  onChanged: (v) => ref
                      .read(databaseProvider)
                      .setSetting('reduce_motion', v ? 'true' : 'false'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('Tema Tampilan',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  trailing: DropdownButton<String>(
                    value: settings?.themeMode ?? 'light',
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(
                          value: 'light', child: Text('Terang Hangat')),
                      DropdownMenuItem(
                          value: 'dark', child: Text('Gelap Hangat')),
                      DropdownMenuItem(
                          value: 'system', child: Text('Ikuti Sistem')),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        ref
                            .read(databaseProvider)
                            .setSetting('theme_mode', v);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Developer QA Tool: Animation Preview Lab
          Card(
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: MamPetColors.skySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.animation_rounded,
                  color: MamPetColors.skyAccent,
                ),
              ),
              title: const Text(
                'Animation Preview Lab',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'Uji 60 monster, rig layer, hitbox, pivot & FPS (Alat Pengembang)',
                style: TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/dev/animation-preview'),
            ),
          ),

          const SizedBox(height: 16),

          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.shield_outlined,
                          color: MamPetColors.sageAccent),
                      SizedBox(width: 8),
                      Text(
                        'Privasi & Prinsip MamPet',
                        style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 14.5),
                      ),
                    ],
                  ),
                  SizedBox(height: 6),
                  Text(
                    '• Tidak butuh akun, tidak ada iklan, dan tidak ada pengunggahan data otomatis.\n'
                    '• Harga, foto, dan lokasi selalu opsional serta tidak pernah menjadi penentu XP atau rarity.\n'
                    '• Tidak ada hukuman jika kamu melewatkan hari atau makan lebih sedikit.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: MamPetColors.cocoaMuted,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              side: BorderSide(color: Colors.red.shade300),
            ),
            onPressed: _confirmResetData,
            icon: const Icon(Icons.delete_forever_rounded),
            label: const Text('Reset Semua Data Lokal'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard(UserPersonalStats stats) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ringkasan Perjalanan Kulinermu',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2.0,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              children: [
                _kpiBox(Icons.restaurant_rounded, MamPetColors.coralPrimary,
                    'Total Sesi', '${stats.totalSessions} sesi'),
                _kpiBox(Icons.menu_book_rounded, MamPetColors.sageAccent,
                    'FoodDex Unik',
                    '${stats.uniqueFoodsDiscovered}/${stats.totalMasterFoods}'),
                _kpiBox(Icons.pets_rounded, MamPetColors.skyAccent,
                    'Monster',
                    '${stats.monstersUnlocked}/${stats.totalSpecies}'),
                _kpiBox(Icons.place_rounded, MamPetColors.honeySecondary,
                    'Tempat', '${stats.placesVisitedCount} lokasi'),
                _kpiBox(
                  Icons.trending_up_rounded,
                  const Color(0xFF8B5CF6),
                  'Rata-rata/Minggu',
                  '${stats.avgSessionsPerWeek.toStringAsFixed(1)} sesi',
                ),
                _kpiBox(
                  Icons.auto_awesome_rounded,
                  const Color(0xFFEC4899),
                  'Fase B•Y•A',
                  '${stats.babyCount} • ${stats.youngCount} • ${stats.adultCount}',
                ),
              ],
            ),
            if (stats.mostDiverseCategoryName != null) ...[
              const SizedBox(height: 10),
              Text(
                'Kategori paling beragam: ${stats.mostDiverseCategoryName} (${stats.mostDiverseCategoryCount} hidangan unik)',
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w800),
              ),
            ],
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: MamPetColors.warmSurfaceAlt,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total Pengeluaran Tercatat',
                        style: TextStyle(
                            fontSize: 12, color: MamPetColors.cocoaMuted),
                      ),
                      if (stats.unpricedItemsCount > 0)
                        const Text(
                          'sebagian catatan tanpa harga',
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: MamPetColors.cocoaMuted,
                          ),
                        ),
                    ],
                  ),
                  Text(
                    stats.pricedItemsCount > 0
                        ? MamPetFormatters.formatRupiah(stats.totalSpendMinor)
                        : '-',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
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

  Widget _kpiBox(IconData icon, Color color, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: MamPetColors.warmSurfaceAlt,
        borderRadius: BorderRadius.circular(16),
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
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 13.5),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 10.5, color: MamPetColors.cocoaMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
