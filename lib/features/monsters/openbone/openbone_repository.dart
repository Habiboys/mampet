import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import '../../../core/domain/enums.dart';
import '../models/monster_rig.dart';
import 'openbone_document.dart';
import 'openbone_renderer.dart';

/// Loaded, GPU-ready OpenBone character package with ref-counted texture lifecycle.
class LoadedOpenBonePackage {
  final OpenBoneFormEntry formEntry;
  final OpenBonePackageManifest packageManifest;
  final OpenBoneDocument document;
  final Map<String, OpenBoneGpuTexture> textures;

  int _refCount = 0;
  bool _disposed = false;

  LoadedOpenBonePackage({
    required this.formEntry,
    required this.packageManifest,
    required this.document,
    required this.textures,
  });

  bool get isDisposed => _disposed;
  int get refCount => _refCount;

  void retain() {
    if (!_disposed) _refCount++;
  }

  void release() {
    if (_refCount > 0) _refCount--;
  }

  void disposeTextures() {
    if (_disposed) return;
    _disposed = true;
    for (final tex in textures.values) {
      tex.dispose();
    }
    textures.clear();
  }
}

/// Result of attempting to load an OpenBone package for a `(slug, stage)` pair.
class OpenBoneLoadResult {
  final OpenBoneFormEntry? formEntry;
  final LoadedOpenBonePackage? package;

  const OpenBoneLoadResult({this.formEntry, this.package});

  bool get isReady => package != null && !package!.isDisposed;
}

/// Ref-counted LRU repository for MamPet's OpenBone 0.4.8 animated monster packages.
///
/// Strictly follows `ANIMATION_INTEGRATION_GUIDE.md`:
/// - Reads `assets/animated_monsters/collection_manifest.json` once.
/// - Only loads packages with `status == "exported"` into production runtime.
/// - Excludes `review_only` (e.g. `leaf_spirit/adult`) and `source_blocked`
///   (e.g. `leaf_spirit/young`) so callers fall back safely to static sprites.
class OpenBoneRepository {
  OpenBoneRepository._();

  static const String collectionManifestAsset =
      'assets/animated_monsters/collection_manifest.json';

  /// Keep up to 6 decoded GPU atlas packages hot for instant Home/Dex switching
  /// while bounding Android texture memory usage.
  static const int maxCachedPackages = 6;

  static OpenBoneCollectionManifest? _collectionManifest;
  static Future<OpenBoneCollectionManifest?>? _manifestFuture;

  // Insertion-ordered map acting as an LRU cache (most recently used at the end).
  static final Map<String, LoadedOpenBonePackage> _lruCache = {};
  static final Map<String, Future<OpenBoneLoadResult>> _inFlight = {};

  static String _key(String slug, EvolutionPhase stage) => '$slug/${stage.code}';

  /// Loads (and caches) `assets/animated_monsters/collection_manifest.json`.
  static Future<OpenBoneCollectionManifest?> loadCollectionManifest({
    AssetBundle? bundle,
  }) {
    if (_collectionManifest != null) return Future.value(_collectionManifest);
    if (_manifestFuture != null) return _manifestFuture!;

    final b = bundle ?? rootBundle;
    final fut = () async {
      try {
        final raw = await b.loadString(collectionManifestAsset);
        final parsed = OpenBoneCollectionManifest.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        _collectionManifest = parsed;
        return parsed;
      } catch (_) {
        return null;
      } finally {
        _manifestFuture = null;
      }
    }();
    _manifestFuture = fut;
    return fut;
  }

  /// Synchronous peek into the cached collection manifest (if already loaded).
  static OpenBoneCollectionManifest? get cachedCollectionManifest =>
      _collectionManifest;

  /// Synchronous peek into the hot LRU cache for instant mount without flicker.
  static OpenBoneLoadResult? getCached(
    String monsterIdOrSlug,
    EvolutionPhase stage,
  ) {
    final slug = MonsterRig.resolveSlug(monsterIdOrSlug);
    final key = _key(slug, stage);
    final cached = _lruCache[key];
    if (cached != null && !cached.isDisposed) {
      // Touch LRU position
      _lruCache.remove(key);
      _lruCache[key] = cached;
      return OpenBoneLoadResult(formEntry: cached.formEntry, package: cached);
    }
    final entry = _collectionManifest?.lookup(slug, stage.code);
    if (entry != null && !entry.isExported) {
      return OpenBoneLoadResult(formEntry: entry, package: null);
    }
    return null;
  }

  /// Loads an exported OpenBone package (`.obonb` + embedded PNG atlas).
  /// Returns `OpenBoneLoadResult(package: null)` if the form is `review_only`,
  /// `source_blocked`, or unavailable in the asset bundle.
  static Future<OpenBoneLoadResult> load(
    String monsterIdOrSlug,
    EvolutionPhase stage, {
    AssetBundle? bundle,
  }) async {
    final slug = MonsterRig.resolveSlug(monsterIdOrSlug);
    final key = _key(slug, stage);

    final cached = _lruCache[key];
    if (cached != null && !cached.isDisposed) {
      _lruCache.remove(key);
      _lruCache[key] = cached;
      return OpenBoneLoadResult(formEntry: cached.formEntry, package: cached);
    }

    final pending = _inFlight[key];
    if (pending != null) return pending;

    final b = bundle ?? rootBundle;
    final future = _loadInternal(slug, stage, b).then((res) {
      _inFlight.remove(key);
      if (res.package != null) {
        _lruCache.remove(key);
        _lruCache[key] = res.package!;
        _evictUnusedIfNeeded();
      }
      return res;
    });
    _inFlight[key] = future;
    return future;
  }

  static Future<OpenBoneLoadResult> _loadInternal(
    String slug,
    EvolutionPhase stage,
    AssetBundle bundle,
  ) async {
    final manifest = await loadCollectionManifest(bundle: bundle);
    final entry = manifest?.lookup(slug, stage.code);

    // Explicitly exclude `review_only` and `source_blocked` from production loading.
    if (entry == null || !entry.isExported) {
      return OpenBoneLoadResult(formEntry: entry, package: null);
    }

    try {
      final manifestPath = entry.fullManifestAssetPath!;
      final rawPkg = await bundle.loadString(manifestPath);
      final baseDir = manifestPath.substring(0, manifestPath.lastIndexOf('/'));
      final pkgManifest = OpenBonePackageManifest.fromJson(
        jsonDecode(rawPkg) as Map<String, dynamic>,
        baseDirAssetPath: baseDir,
      );

      final byteData = await bundle.load(pkgManifest.exportAssetPath);
      final bytes = Uint8List.sublistView(byteData);
      final doc = OpenBoneDocument.fromBytes(bytes);

      final textures = <String, OpenBoneGpuTexture>{};
      for (final page in doc.atlasPages) {
        final codec = await ui.instantiateImageCodec(page.imageBytes);
        final frame = await codec.getNextFrame();
        codec.dispose();
        textures[page.id] = OpenBoneGpuTexture(
          image: frame.image,
          declaredWidth: page.width,
          declaredHeight: page.height,
        );
      }

      if (textures.isEmpty) {
        return OpenBoneLoadResult(formEntry: entry, package: null);
      }

      return OpenBoneLoadResult(
        formEntry: entry,
        package: LoadedOpenBonePackage(
          formEntry: entry,
          packageManifest: pkgManifest,
          document: doc,
          textures: textures,
        ),
      );
    } catch (_) {
      return OpenBoneLoadResult(formEntry: entry, package: null);
    }
  }

  static void _evictUnusedIfNeeded() {
    if (_lruCache.length <= maxCachedPackages) return;
    final keysToEvict = <String>[];
    for (final e in _lruCache.entries) {
      if (_lruCache.length - keysToEvict.length <= maxCachedPackages) break;
      if (e.value.refCount <= 0) {
        keysToEvict.add(e.key);
      }
    }
    for (final k in keysToEvict) {
      final removed = _lruCache.remove(k);
      removed?.disposeTextures();
    }
  }

  /// Releases unused cached GPU textures (e.g. on memory pressure or in tests).
  static void clearCache({bool includeManifest = false}) {
    final keys = _lruCache.keys.toList();
    for (final k in keys) {
      final pkg = _lruCache[k];
      if (pkg != null && pkg.refCount <= 0) {
        _lruCache.remove(k);
        pkg.disposeTextures();
      }
    }
    _inFlight.clear();
    if (includeManifest) {
      _collectionManifest = null;
      _manifestFuture = null;
    }
  }
}
