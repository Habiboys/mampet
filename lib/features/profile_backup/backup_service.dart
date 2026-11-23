import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/db/mampet_database.dart';
import '../../core/db/seed_loader.dart';
import '../../core/files/photo_storage.dart';

class BackupExportResult {
  final File zipFile;
  final int photoCount;
  final String dbSha256;

  const BackupExportResult({
    required this.zipFile,
    required this.photoCount,
    required this.dbSha256,
  });
}

class BackupRestoreResult {
  final int restoredPhotos;
  final int schemaVersion;
  final String backupCreatedAt;

  const BackupRestoreResult({
    required this.restoredPhotos,
    required this.schemaVersion,
    required this.backupCreatedAt,
  });
}

class BackupService {
  final MamPetDatabase db;
  final PhotoStorageService photoStorage;
  final SeedDataBundle seed;

  BackupService({
    required this.db,
    required this.photoStorage,
    required this.seed,
  });

  /// Exports SQLite DB + local photos + manifest.json with SHA-256 checksums into a ZIP.
  Future<BackupExportResult> exportBackupZip({Directory? targetDirectory}) async {
    final dbPath = db.databasePath;
    if (dbPath == null) {
      throw StateError('Database path tidak ditemukan.');
    }

    // Flush database cleanly by reopening or closing briefly
    await db.close();
    late List<int> dbBytes;
    try {
      dbBytes = await File(dbPath).readAsBytes();
    } finally {
      await db.init(seed);
    }

    final dbHash = sha256.convert(dbBytes).toString();
    final archive = Archive();
    archive.addFile(ArchiveFile('mampet_v1.db', dbBytes.length, dbBytes));

    final photos = await photoStorage.listAllStoredPhotos();
    final photoHashes = <String, String>{};
    for (final photo in photos) {
      final bytes = await photo.readAsBytes();
      final name = p.basename(photo.path);
      photoHashes[name] = sha256.convert(bytes).toString();
      archive.addFile(ArchiveFile('photos/$name', bytes.length, bytes));
    }

    final nowIso = DateTime.now().toIso8601String();
    final manifest = {
      'app': 'MamPet',
      'app_version': '1.0.0',
      'schema_version': MamPetDatabase.currentSchemaVersion,
      'created_at': nowIso,
      'db_file': 'mampet_v1.db',
      'db_sha256': dbHash,
      'photos': photoHashes,
    };
    final manifestBytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest));
    archive.addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));

    final zipData = ZipEncoder().encode(archive);
    final dir = targetDirectory ?? await getApplicationDocumentsDirectory();
    final backupDir = Directory(p.join(dir.path, 'mampet_backups'));
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }

    final stamp = nowIso.replaceAll(':', '-').split('.').first;
    final zipFile = File(p.join(backupDir.path, 'mampet_backup_$stamp.zip'));
    await zipFile.writeAsBytes(zipData, flush: true);

    await db.setSetting('last_backup_at', nowIso);

    return BackupExportResult(
      zipFile: zipFile,
      photoCount: photos.length,
      dbSha256: dbHash,
    );
  }

  /// Validates manifest, schema version, and SHA-256 checksums, creates a safety
  /// backup of the current database, then atomically restores DB and photos.
  Future<BackupRestoreResult> restoreFromBackupZip(File zipFile) async {
    final dbPath = db.databasePath;
    if (dbPath == null) {
      throw StateError('Database path tidak ditemukan.');
    }

    final zipBytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(zipBytes);

    ArchiveFile? manifestEntry;
    ArchiveFile? dbEntry;
    final photoEntries = <ArchiveFile>[];

    for (final file in archive.files) {
      if (!file.isFile) continue;
      if (file.name == 'manifest.json') {
        manifestEntry = file;
      } else if (file.name == 'mampet_v1.db') {
        dbEntry = file;
      } else if (file.name.startsWith('photos/')) {
        photoEntries.add(file);
      }
    }

    if (manifestEntry == null || dbEntry == null) {
      throw FormatException('File backup tidak valid: manifest atau database tidak ditemukan.');
    }

    final manifestJson = jsonDecode(utf8.decode(manifestEntry.content as List<int>))
        as Map<String, dynamic>;
    if (manifestJson['app'] != 'MamPet') {
      throw FormatException('File ini bukan backup MamPet yang sah.');
    }

    final schemaVersion = (manifestJson['schema_version'] as num?)?.toInt() ?? 0;
    if (schemaVersion <= 0 || schemaVersion > MamPetDatabase.currentSchemaVersion) {
      throw FormatException(
        'Versi skema backup ($schemaVersion) tidak kompatibel dengan aplikasi ini.',
      );
    }

    final expectedDbHash = manifestJson['db_sha256'] as String?;
    final restoredDbBytes = dbEntry.content as List<int>;
    final actualDbHash = sha256.convert(restoredDbBytes).toString();
    if (expectedDbHash == null || expectedDbHash != actualDbHash) {
      throw FormatException('Checksum database rusak atau tidak cocok.');
    }

    final expectedPhotos = (manifestJson['photos'] as Map<String, dynamic>? ?? {});
    for (final pe in photoEntries) {
      final name = p.basename(pe.name);
      final bytes = pe.content as List<int>;
      final expectedHash = expectedPhotos[name] as String?;
      if (expectedHash != null && sha256.convert(bytes).toString() != expectedHash) {
        throw FormatException('Checksum foto "$name" rusak.');
      }
    }

    // Create temporary safety backup of current live DB before overwriting
    final safetyBackup = File('$dbPath.safety_bak');
    await db.close();
    try {
      if (await File(dbPath).exists()) {
        await File(dbPath).copy(safetyBackup.path);
      }

      await File(dbPath).writeAsBytes(restoredDbBytes, flush: true);

      // Restore photos cleanly into local photos dir
      final photosDir = await photoStorage.getPhotosDirectory();
      int restoredPhotoCount = 0;
      for (final pe in photoEntries) {
        final name = p.basename(pe.name);
        final outFile = File(p.join(photosDir.path, name));
        await outFile.writeAsBytes(pe.content as List<int>, flush: true);
        restoredPhotoCount++;
      }

      // Reopen database & remap photo_path directories so restored photos resolve on this device
      await db.reopen(seed);
      final liveDb = await db.database;
      final photoItems = await liveDb.query(
        'meal_items',
        columns: ['id', 'photo_path'],
        where: 'photo_path IS NOT NULL',
      );
      for (final item in photoItems) {
        final oldPath = item['photo_path'] as String;
        final fileName = p.basename(oldPath);
        final localCandidate = File(p.join(photosDir.path, fileName));
        if (await localCandidate.exists() && oldPath != localCandidate.path) {
          await liveDb.update(
            'meal_items',
            {'photo_path': localCandidate.path},
            where: 'id = ?',
            whereArgs: [item['id']],
          );
        }
      }

      if (await safetyBackup.exists()) {
        await safetyBackup.delete();
      }

      return BackupRestoreResult(
        restoredPhotos: restoredPhotoCount,
        schemaVersion: schemaVersion,
        backupCreatedAt: (manifestJson['created_at'] as String?) ?? '',
      );
    } catch (e) {
      // Rollback to safety backup
      if (await safetyBackup.exists()) {
        await safetyBackup.copy(dbPath);
        await safetyBackup.delete();
      }
      await db.reopen(seed);
      rethrow;
    }
  }
}
