import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:openmuse_plugin_sdk/openmuse_plugin_sdk.dart';
import 'package:path/path.dart' as p;

enum WorkspaceTabKind { resource, diff }

final class WorkspaceMount {
  WorkspaceMount({required this.path})
    : name = p.basename(path),
      root = WorkspaceEntry.directory(path: path, depth: 0);

  final String path;
  final String name;
  final WorkspaceEntry root;
}

final class WorkspaceEntry {
  WorkspaceEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.depth,
  });

  factory WorkspaceEntry.directory({
    required String path,
    required int depth,
  }) => WorkspaceEntry(
    path: path,
    name: p.basename(path),
    isDirectory: true,
    depth: depth,
  );

  final String path;
  String name;
  final bool isDirectory;
  final int depth;
  bool expanded = false;
  bool loading = false;
  List<WorkspaceEntry> children = [];

  OpenMuseResource get resource => OpenMuseResource(
    uri: Uri.file(path),
    displayName: name,
    mediaType: _mediaTypeFor(name),
  );
}

final class WorkspaceDiff {
  const WorkspaceDiff({
    required this.resource,
    required this.snapshot,
    required this.comparisonId,
    required this.afterLabel,
    required this.before,
    required this.after,
  });

  final OpenMuseResource resource;
  final LocalVersionSnapshot snapshot;
  final String comparisonId;
  final String afterLabel;
  final String before;
  final String after;
}

final class WorkspaceTab {
  WorkspaceTab.resource(this.resource, {this.preferredEditorId})
    : id = resource.uri.toString(),
      title = resource.displayName,
      kind = WorkspaceTabKind.resource,
      diff = null;

  WorkspaceTab.diff(WorkspaceDiff value)
    : id = 'diff:${value.resource.uri}:${value.comparisonId}',
      title =
          '${value.resource.displayName}-${value.snapshot.shortId}↔${value.afterLabel}',
      kind = WorkspaceTabKind.diff,
      resource = value.resource,
      diff = value;

  final String id;
  final String title;
  final WorkspaceTabKind kind;
  final OpenMuseResource resource;
  final WorkspaceDiff? diff;
  String? preferredEditorId;
  bool pinned = false;
}

final class LocalVersionSnapshot {
  const LocalVersionSnapshot({
    required this.id,
    required this.resourcePath,
    required this.createdAt,
    required this.byteLength,
  });

  factory LocalVersionSnapshot.fromJson(Map<String, Object?> value) =>
      LocalVersionSnapshot(
        id: value['id']! as String,
        resourcePath: value['resourcePath']! as String,
        createdAt: DateTime.parse(value['createdAt']! as String),
        byteLength: value['byteLength']! as int,
      );

  final String id;
  final String resourcePath;
  final DateTime createdAt;
  final int byteLength;
  String get shortId => id.substring(0, 8);

  Map<String, Object?> toJson() => {
    'id': id,
    'resourcePath': resourcePath,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'byteLength': byteLength,
  };
}

/// Content-addressed, append-only local version storage. Blobs are outside the
/// user's workspace so versioning never mutates a project tree.
final class LocalVersionStore {
  LocalVersionStore(this.root);

  final Directory root;
  final Map<String, List<LocalVersionSnapshot>> _index = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final file = File(p.join(root.path, 'index.json'));
    if (!await file.exists()) return;
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) return;
    for (final entry in decoded.entries) {
      final values = entry.value;
      if (values is! List) continue;
      _index[entry.key] = values
          .whereType<Map>()
          .map((value) => LocalVersionSnapshot.fromJson(value.cast()))
          .toList();
    }
  }

  Future<LocalVersionSnapshot> capture(OpenMuseResource resource) async {
    await load();
    final path = resource.uri.toFilePath();
    final bytes = await File(path).readAsBytes();
    final id = sha256.convert(bytes).toString();
    final snapshots = _index.putIfAbsent(path, () => []);
    for (final snapshot in snapshots) {
      if (snapshot.id == id) return snapshot;
    }
    await Directory(p.join(root.path, 'blobs')).create(recursive: true);
    final blob = File(p.join(root.path, 'blobs', id));
    if (!await blob.exists()) await blob.writeAsBytes(bytes, flush: true);
    final snapshot = LocalVersionSnapshot(
      id: id,
      resourcePath: path,
      createdAt: DateTime.now(),
      byteLength: bytes.length,
    );
    snapshots.insert(0, snapshot);
    await _save();
    return snapshot;
  }

  Future<List<LocalVersionSnapshot>> list(OpenMuseResource resource) async {
    await load();
    return List.unmodifiable(_index[resource.uri.toFilePath()] ?? const []);
  }

  Future<String> read(LocalVersionSnapshot snapshot) =>
      File(p.join(root.path, 'blobs', snapshot.id)).readAsString();

  Future<void> _save() async {
    await root.create(recursive: true);
    final value = {
      for (final entry in _index.entries)
        entry.key: entry.value.map((snapshot) => snapshot.toJson()).toList(),
    };
    final target = File(p.join(root.path, 'index.json'));
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
  }
}

final class WorkspaceMountStore {
  const WorkspaceMountStore(this.file);

  final File file;

  Future<List<String>> load() async {
    if (!await file.exists()) return const [];
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! List) return const [];
    return decoded.whereType<String>().toList(growable: false);
  }

  Future<void> save(Iterable<String> paths) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(paths.toList()), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }
}

/// Host-owned Resource Authority. It owns mounts, tabs and filesystem safety;
/// concrete editors/viewers/agents remain plugin responsibilities.
final class LocalWorkspaceController extends ChangeNotifier {
  LocalWorkspaceController({
    required String rootPath,
    required Iterable<OpenMuseResource> initialResources,
    LocalVersionStore? versionStore,
    WorkspaceMountStore? mountStore,
    Iterable<String> additionalMountPaths = const [],
  }) : _versionStore =
           versionStore ??
           LocalVersionStore(
             Directory(p.join(Directory.systemTemp.path, 'openmuse-versions')),
           ),
       _mountStore = _mountStoreValue(mountStore) {
    final mount = WorkspaceMount(path: _canonicalMountPath(rootPath));
    mount.root
      ..expanded = true
      ..children = initialResources
          .map(
            (resource) => WorkspaceEntry(
              path: resource.uri.toFilePath(),
              name: resource.displayName,
              isDirectory: false,
              depth: 1,
            ),
          )
          .toList();
    _mounts.add(mount);
    for (final path in additionalMountPaths) {
      final normalized = _canonicalMountPath(path);
      if (normalized == mount.path) {
        continue;
      }
      _mounts.add(WorkspaceMount(path: normalized)..root.expanded = true);
    }
  }

  final LocalVersionStore _versionStore;
  final WorkspaceMountStore? _mountStore;
  final List<WorkspaceMount> _mounts = [];
  final List<WorkspaceTab> _tabs = [];
  final Set<Uri> _favorites = <Uri>{};
  final Map<String, StreamSubscription<FileSystemEvent>> _watchers = {};
  Timer? _watchDebounce;
  bool _disposed = false;
  WorkspaceTab? _activeTab;
  bool _sidebarVisible = true;
  bool _projectSectionExpanded = true;
  String? _activeMountPath;

  String get rootPath => _mounts.first.path;
  List<WorkspaceMount> get mounts => List.unmodifiable(_mounts);
  List<WorkspaceTab> get tabs => List.unmodifiable(_tabs);
  WorkspaceTab? get activeTab => _activeTab;
  OpenMuseResource? get selected => _activeTab?.resource;
  bool get sidebarVisible => _sidebarVisible;
  bool get projectSectionExpanded => _projectSectionExpanded;
  String get activeMountPath => _activeMountPath ?? rootPath;

  List<OpenMuseResource> get resources => [
    for (final mount in _mounts)
      for (final entry in _walk(mount.root))
        if (!entry.isDirectory) entry.resource,
  ];

  Future<void> initialize() async {
    await Future.wait([
      for (final mount in _mounts) refreshDirectory(mount.root),
      _versionStore.load(),
    ]);
    for (final mount in _mounts) {
      _watchMount(mount);
    }
  }

  bool isFavorite(OpenMuseResource resource) =>
      _favorites.contains(resource.uri);

  void select(OpenMuseResource resource) => openResource(resource);

  void openResource(OpenMuseResource resource, {String? editorId}) {
    final path = resource.uri.toFilePath();
    for (final mount in _mounts) {
      if (mount.path == path || p.isWithin(mount.path, path)) {
        _activeMountPath = mount.path;
        break;
      }
    }
    WorkspaceTab? existing;
    for (final tab in _tabs) {
      if (tab.kind == WorkspaceTabKind.resource &&
          tab.resource.uri == resource.uri) {
        existing = tab;
        break;
      }
    }
    final tab =
        existing ??
        WorkspaceTab.resource(resource, preferredEditorId: editorId);
    if (editorId != null) tab.preferredEditorId = editorId;
    if (existing == null) _tabs.add(tab);
    _activeTab = tab;
    notifyListeners();
  }

  void activateTab(WorkspaceTab tab) {
    _activeTab = tab;
    notifyListeners();
  }

  void closeTab(WorkspaceTab tab) {
    if (tab.pinned) return;
    final index = _tabs.indexOf(tab);
    if (index < 0) return;
    _tabs.removeAt(index);
    if (identical(_activeTab, tab)) {
      _activeTab = _tabs.isEmpty
          ? null
          : _tabs[index.clamp(0, _tabs.length - 1)];
    }
    notifyListeners();
  }

  void closeOtherTabs(WorkspaceTab tab) {
    _tabs.removeWhere(
      (candidate) => !identical(candidate, tab) && !candidate.pinned,
    );
    _activeTab = tab;
    notifyListeners();
  }

  void togglePinned(WorkspaceTab tab) {
    tab.pinned = !tab.pinned;
    notifyListeners();
  }

  Future<void> addWorkspace(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) throw FileSystemException('目录不存在', path);
    final canonical = await directory.resolveSymbolicLinks();
    if (_mounts.any((mount) => mount.path == canonical)) return;
    final mount = WorkspaceMount(path: canonical)..root.expanded = true;
    _mounts.add(mount);
    _activeMountPath = mount.path;
    _projectSectionExpanded = true;
    await refreshDirectory(mount.root);
    _watchMount(mount);
    await _persistMounts();
    notifyListeners();
  }

  Future<void> removeWorkspace(WorkspaceMount mount) async {
    if (_mounts.length == 1) return;
    _mounts.remove(mount);
    await _watchers.remove(mount.path)?.cancel();
    _removeTabsWithin(mount.path);
    if (_activeMountPath == mount.path) _activeMountPath = rootPath;
    await _persistMounts();
    notifyListeners();
  }

  Future<void> toggleDirectory(WorkspaceEntry entry) async {
    if (!entry.isDirectory) return;
    if (_mounts.any((mount) => identical(mount.root, entry))) {
      _activeMountPath = entry.path;
    }
    entry.expanded = !entry.expanded;
    notifyListeners();
    if (entry.expanded) await refreshDirectory(entry);
  }

  Future<void> refreshDirectory(WorkspaceEntry entry) async {
    if (!entry.isDirectory || entry.loading) return;
    entry.loading = true;
    notifyListeners();
    try {
      final children = <WorkspaceEntry>[];
      final previous = {for (final child in entry.children) child.path: child};
      await for (final entity in Directory(
        entry.path,
      ).list(followLinks: false)) {
        final type = await FileSystemEntity.type(
          entity.path,
          followLinks: false,
        );
        if (type != FileSystemEntityType.file &&
            type != FileSystemEntityType.directory) {
          continue;
        }
        final path = p.normalize(p.absolute(entity.path));
        final existing = previous[path];
        children.add(
          existing != null &&
                  existing.isDirectory ==
                      (type == FileSystemEntityType.directory)
              ? (existing..name = p.basename(entity.path))
              : WorkspaceEntry(
                  path: path,
                  name: p.basename(entity.path),
                  isDirectory: type == FileSystemEntityType.directory,
                  depth: entry.depth + 1,
                ),
        );
      }
      children.sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      entry.children = children;
    } finally {
      entry.loading = false;
      notifyListeners();
    }
  }

  void _watchMount(WorkspaceMount mount) {
    if (_disposed || _watchers.containsKey(mount.path)) return;
    try {
      _watchers[mount.path] = Directory(mount.path)
          .watch(recursive: true)
          .listen(
            (_) => _scheduleWatchRefresh(),
            onError: (Object _) => _scheduleWatchRefresh(),
          );
    } on FileSystemException {
      // Some network filesystems do not support recursive notifications.
      // Manual refresh remains available in the Workspace context menu.
    } on UnsupportedError {
      // Keep the mounted directory usable even when watching is unavailable.
    }
  }

  void _scheduleWatchRefresh() {
    if (_disposed) return;
    _watchDebounce?.cancel();
    _watchDebounce = Timer(const Duration(milliseconds: 250), () async {
      if (_disposed) return;
      for (final mount in _mounts.toList()) {
        final directories = <WorkspaceEntry>[
          mount.root,
          for (final entry in _walk(mount.root))
            if (entry.isDirectory && entry.expanded) entry,
        ];
        for (final directory in directories) {
          if (_disposed || !_mounts.contains(mount)) return;
          try {
            await refreshDirectory(directory);
          } on FileSystemException {
            // The directory may have been removed between the watch event and
            // this refresh; its parent still reconciles on the next event.
          }
        }
      }
    });
  }

  List<WorkspaceEntry> visibleEntries(WorkspaceMount mount) {
    final result = <WorkspaceEntry>[];
    if (!mount.root.expanded) return result;
    void append(WorkspaceEntry parent) {
      for (final child in parent.children) {
        result.add(child);
        if (child.isDirectory && child.expanded) append(child);
      }
    }

    append(mount.root);
    return result;
  }

  Future<OpenMuseResource> createMarkdown(String requestedName) async {
    final baseName = _safeBaseName(requestedName);
    final directory = Directory(activeMountPath);
    await directory.create(recursive: true);
    var suffix = 1;
    var file = File(p.join(directory.path, '$baseName.md'));
    while (await file.exists()) {
      suffix += 1;
      file = File(p.join(directory.path, '$baseName $suffix.md'));
    }
    await file.writeAsString('# $baseName\n\n', flush: true);
    final mount = _mounts.firstWhere((value) => value.path == directory.path);
    await refreshDirectory(mount.root);
    final resource = OpenMuseResource(
      uri: file.uri,
      displayName: p.basename(file.path),
      mediaType: 'text/markdown',
    );
    openResource(resource);
    return resource;
  }

  Future<WorkspaceEntry> createEntry(
    WorkspaceEntry parent,
    String requestedName, {
    required bool directory,
  }) async {
    if (!parent.isDirectory || !_containsEntry(parent)) {
      throw const FormatException('目标文件夹不在工作区内');
    }
    final name = _validatedName(requestedName);
    final target = p.join(parent.path, name);
    if (await FileSystemEntity.type(target, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException('目标已存在', target);
    }
    if (directory) {
      await Directory(target).create();
    } else {
      await File(target).create();
    }
    parent.expanded = true;
    await refreshDirectory(parent);
    return parent.children.firstWhere((entry) => entry.path == target);
  }

  Future<void> renameEntry(WorkspaceEntry entry, String requestedName) async {
    if (!_containsEntry(entry) ||
        _mounts.any((m) => identical(m.root, entry))) {
      throw const FormatException('不能重命名工作区根目录');
    }
    final name = _validatedName(requestedName);
    final target = p.join(p.dirname(entry.path), name);
    if (await FileSystemEntity.type(target, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException('目标已存在', target);
    }
    if (entry.isDirectory) {
      await Directory(entry.path).rename(target);
    } else {
      await File(entry.path).rename(target);
    }
    _retargetTabs(entry.path, target);
    await _refreshParent(entry.path);
  }

  Future<void> deleteEntry(WorkspaceEntry entry) async {
    if (!_containsEntry(entry) ||
        _mounts.any((m) => identical(m.root, entry))) {
      throw const FormatException('不能删除工作区根目录');
    }
    if (entry.isDirectory) {
      await Directory(entry.path).delete(recursive: true);
    } else {
      await File(entry.path).delete();
    }
    _removeTabsWithin(entry.path);
    await _refreshParent(entry.path);
  }

  Future<LocalVersionSnapshot> captureVersion(OpenMuseResource resource) async {
    final snapshot = await _versionStore.capture(resource);
    notifyListeners();
    return snapshot;
  }

  Future<List<LocalVersionSnapshot>> versions(OpenMuseResource resource) =>
      _versionStore.list(resource);

  Future<void> openDiff(
    OpenMuseResource resource,
    LocalVersionSnapshot snapshot,
  ) => openVersionComparison(resource, snapshot);

  Future<void> openVersionComparison(
    OpenMuseResource resource,
    LocalVersionSnapshot beforeVersion, {
    LocalVersionSnapshot? afterVersion,
  }) async {
    if (afterVersion != null && beforeVersion.id == afterVersion.id) {
      throw ArgumentError('不能把同一个版本与自己比较');
    }
    final after = afterVersion == null
        ? await File.fromUri(resource.uri).readAsString()
        : await _versionStore.read(afterVersion);
    final afterIdentity =
        afterVersion?.id ?? sha256.convert(utf8.encode(after)).toString();
    final diff = WorkspaceDiff(
      resource: resource,
      snapshot: beforeVersion,
      comparisonId: '${beforeVersion.id}:$afterIdentity',
      afterLabel: afterVersion?.shortId ?? '当前',
      before: await _versionStore.read(beforeVersion),
      after: after,
    );
    WorkspaceTab? existing;
    final id = 'diff:${resource.uri}:${diff.comparisonId}';
    for (final candidate in _tabs) {
      if (candidate.id == id) {
        existing = candidate;
        break;
      }
    }
    final tab = existing ?? WorkspaceTab.diff(diff);
    if (existing == null) _tabs.add(tab);
    _activeTab = tab;
    notifyListeners();
  }

  void toggleFavorite(OpenMuseResource resource) {
    if (!_favorites.add(resource.uri)) _favorites.remove(resource.uri);
    notifyListeners();
  }

  void toggleSidebar() {
    _sidebarVisible = !_sidebarVisible;
    notifyListeners();
  }

  void toggleProjectSection() {
    _projectSectionExpanded = !_projectSectionExpanded;
    notifyListeners();
  }

  void activateMount(WorkspaceMount mount) {
    if (!_mounts.contains(mount)) return;
    _activeMountPath = mount.path;
    notifyListeners();
  }

  /// Resolve a sidecar request only inside a mounted, canonical local tree.
  Future<OpenMuseResource> openHostResource({
    required String requestedPath,
    String? cwd,
  }) async {
    if (requestedPath.isEmpty || requestedPath.length > 4096) {
      throw const FormatException('无效资源路径');
    }
    final base = cwd == null || cwd.isEmpty ? activeMountPath : cwd;
    final candidate = p.isAbsolute(requestedPath)
        ? requestedPath
        : p.join(base, requestedPath);
    final canonical = await File(candidate).resolveSymbolicLinks();
    if (!_mounts.any((mount) => p.isWithin(mount.path, canonical))) {
      throw FileSystemException('资源不在已授权的工作区内', requestedPath);
    }
    if (await FileSystemEntity.type(canonical) != FileSystemEntityType.file) {
      throw FileSystemException('资源不是文件', requestedPath);
    }
    final resource = OpenMuseResource(
      uri: Uri.file(canonical),
      displayName: p.basename(canonical),
      mediaType: _mediaTypeFor(canonical),
    );
    openResource(resource);
    return resource;
  }

  List<OpenMuseResource> search(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return resources;
    return resources
        .where(
          (resource) => resource.displayName.toLowerCase().contains(normalized),
        )
        .toList(growable: false);
  }

  String relativePath(OpenMuseResource resource) {
    final path = resource.uri.toFilePath();
    for (final mount in _mounts) {
      if (mount.path == path || p.isWithin(mount.path, path)) {
        return p.relative(path, from: mount.path);
      }
    }
    return path;
  }

  Future<void> _refreshParent(String childPath) async {
    final parent = p.dirname(childPath);
    for (final mount in _mounts) {
      for (final entry in [mount.root, ..._walk(mount.root)]) {
        if (entry.path == parent) {
          await refreshDirectory(entry);
          return;
        }
      }
    }
  }

  Future<void> _persistMounts() =>
      _mountStore?.save(_mounts.map((mount) => mount.path)) ??
      Future<void>.value();

  void _retargetTabs(String oldPath, String newPath) {
    for (var index = 0; index < _tabs.length; index++) {
      final tab = _tabs[index];
      final path = tab.resource.uri.toFilePath();
      if (path != oldPath && !p.isWithin(oldPath, path)) continue;
      if (tab.kind == WorkspaceTabKind.diff) {
        _tabs.removeAt(index--);
        if (identical(_activeTab, tab)) _activeTab = null;
        continue;
      }
      final target = path == oldPath
          ? newPath
          : p.join(newPath, p.relative(path, from: oldPath));
      final replacement = WorkspaceTab.resource(
        OpenMuseResource(
          uri: Uri.file(target),
          displayName: p.basename(target),
          mediaType: _mediaTypeFor(target),
        ),
        preferredEditorId: tab.preferredEditorId,
      )..pinned = tab.pinned;
      _tabs[index] = replacement;
      if (identical(_activeTab, tab)) _activeTab = replacement;
    }
    _activeTab ??= _tabs.lastOrNull;
    notifyListeners();
  }

  void _removeTabsWithin(String path) {
    _tabs.removeWhere((tab) {
      final resourcePath = tab.resource.uri.toFilePath();
      return resourcePath == path || p.isWithin(path, resourcePath);
    });
    if (_activeTab != null && !_tabs.contains(_activeTab)) {
      _activeTab = _tabs.lastOrNull;
    }
    notifyListeners();
  }

  bool _containsEntry(WorkspaceEntry entry) => _mounts.any(
    (mount) =>
        identical(mount.root, entry) ||
        _walk(mount.root).any((candidate) => identical(candidate, entry)),
  );

  static String _validatedName(String value) {
    final name = value.trim();
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        p.basename(name) != name ||
        name.contains('\\')) {
      throw const FormatException('无效名称');
    }
    return name;
  }

  static Iterable<WorkspaceEntry> _walk(WorkspaceEntry entry) sync* {
    for (final child in entry.children) {
      yield child;
      if (child.isDirectory) yield* _walk(child);
    }
  }

  static String _safeBaseName(String value) {
    var result = value.trim().replaceAll(
      RegExp(r'\.md$', caseSensitive: false),
      '',
    );
    result = result.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
    return result.isEmpty ? '未命名文档' : result;
  }

  @override
  void dispose() {
    _disposed = true;
    _watchDebounce?.cancel();
    for (final watcher in _watchers.values) {
      unawaited(watcher.cancel());
    }
    _watchers.clear();
    super.dispose();
  }
}

String? _mediaTypeFor(String name) => switch (p.extension(name).toLowerCase()) {
  '.md' => 'text/markdown',
  '.png' => 'image/png',
  '.jpg' || '.jpeg' => 'image/jpeg',
  '.pdf' => 'application/pdf',
  _ => null,
};

WorkspaceMountStore? _mountStoreValue(WorkspaceMountStore? value) => value;

String _canonicalMountPath(String path) {
  final absolute = p.normalize(p.absolute(path));
  try {
    return Directory(absolute).resolveSymbolicLinksSync();
  } on FileSystemException {
    return absolute;
  }
}
