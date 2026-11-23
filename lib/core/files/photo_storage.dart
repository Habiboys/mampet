import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class PhotoStorageService {
  static const _uuid = Uuid();

  Future<Directory> getPhotosDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'mampet_photos'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Copies a picked/compressed image into app-private documents directory
  /// and returns its relative file name so backup/restore remains portable.
  Future<String> persistPhotoFile(String sourcePath) async {
    final dir = await getPhotosDirectory();
    final ext = p.extension(sourcePath).isNotEmpty
        ? p.extension(sourcePath).toLowerCase()
        : '.jpg';
    final fileName = 'meal_${_uuid.v4()}$ext';
    final targetPath = p.join(dir.path, fileName);
    await File(sourcePath).copy(targetPath);
    return targetPath;
  }

  Future<void> deletePhotoIfLocal(String? photoPath) async {
    if (photoPath == null || photoPath.isEmpty) return;
    try {
      final f = File(photoPath);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {
      // Non-fatal cleanup
    }
  }

  Future<List<File>> listAllStoredPhotos() async {
    final dir = await getPhotosDirectory();
    if (!await dir.exists()) return [];
    final entities = await dir.list().toList();
    return entities.whereType<File>().toList();
  }
}
