import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:openmuse_plugin_sdk/openmuse_plugin_sdk.dart';
import 'package:path/path.dart' as p;

/// DSH plugin-owned projection of the Host's local Mount catalog.
/// The v1 document contains no device paths; each path has a separate locator.
final class DshWorkspaceBinding {
  DshWorkspaceBinding(this.context);

  final OpenMusePluginContext context;
  String? _fingerprint;
  Future<void> _pending = Future<void>.value();
  String? dshHome;

  Future<void> publish() {
    _pending = _pending.catchError((Object _) {}).then((_) => _publishNow());
    return _pending;
  }

  Future<void> _publishNow() async {
    final raw = await context.executeHostCommand('workspace.snapshot', null);
    if (raw is! Map) return;
    final snapshot = Map<String, Object?>.from(raw);
    final home = snapshot['dshHome'];
    final workspaceRef = snapshot['workspaceRef'];
    final title = snapshot['title'];
    final activePath = snapshot['activeMountPath'];
    final rawMounts = snapshot['mounts'];
    if (home is! String ||
        !p.isAbsolute(home) ||
        workspaceRef is! String ||
        title is! String ||
        rawMounts is! List) {
      throw const FormatException('无效的 Host 工作区快照');
    }
    dshHome = home;
    final mounts = <({String path, String name, String ref})>[];
    for (final value in rawMounts) {
      if (value is! Map || value['path'] is! String || value['name'] is! String)
        continue;
      final path = value['path'] as String;
      if (!p.isAbsolute(path)) continue;
      mounts.add((
        path: path,
        name: value['name'] as String,
        ref:
            'local.${sha256.convert(utf8.encode(path)).toString().substring(0, 32)}',
      ));
    }
    final fingerprint = jsonEncode({
      'workspaceRef': workspaceRef,
      'title': title,
      'activePath': activePath,
      'mounts': [
        for (final mount in mounts) [mount.path, mount.name],
      ],
    });
    if (_fingerprint == fingerprint) return;
    final bindingDir = Directory(p.join(home, 'bindings'));
    final materializedDir = Directory(p.join(bindingDir.path, 'materialized'));
    await materializedDir.create(recursive: true);
    await _restrict(materializedDir.path, directory: true);
    final expected = <String>{};
    for (final mount in mounts) {
      final name = '${mount.ref}.path';
      expected.add(name);
      await _writeAtomic(
        File(p.join(materializedDir.path, name)),
        '${mount.path}\n',
      );
    }
    await for (final entity in materializedDir.list(followLinks: false)) {
      if (entity is File &&
          p.basename(entity.path).endsWith('.path') &&
          !expected.contains(p.basename(entity.path))) {
        await entity.delete();
      }
    }
    var revision = 1;
    final bindingFile = File(p.join(bindingDir.path, 'workspace-binding.json'));
    if (await bindingFile.exists()) {
      try {
        final previous = jsonDecode(await bindingFile.readAsString());
        if (previous is Map && previous['bindingRevision'] is int) {
          revision = (previous['bindingRevision'] as int) + 1;
        }
      } catch (_) {}
    }
    final document = {
      'protocol': 'muse.workspace/binding/v1',
      'bindingRevision': revision,
      'workspaceRef': workspaceRef,
      'title': title,
      if (activePath is String &&
          mounts.any((mount) => mount.path == activePath))
        'activeMountRef': mounts
            .firstWhere((mount) => mount.path == activePath)
            .ref,
      'issuedAt': DateTime.now().millisecondsSinceEpoch,
      'mounts': [
        for (var index = 0; index < mounts.length; index++)
          {
            'mountRef': mounts[index].ref,
            'displayName': mounts[index].name,
            'providerId': 'openmuse.workspace.local.v1',
            'providerKind': 'local',
            'order': index,
            'requestedMode': 'read-write',
            'materialization': {'mode': 'host-path'},
          },
      ],
    };
    await _writeAtomic(bindingFile, jsonEncode(document));
    _fingerprint = fingerprint;
  }

  Future<void> _writeAtomic(File target, String contents) async {
    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(contents, flush: true);
    await _restrict(temporary.path);
    await temporary.rename(target.path);
  }

  Future<void> _restrict(String path, {bool directory = false}) async {
    if (Platform.isWindows) return;
    final result = await Process.run('chmod', [
      directory ? '700' : '600',
      path,
    ]);
    if (result.exitCode != 0) {
      throw FileSystemException('无法限制 DSH 绑定文件权限', path);
    }
  }
}
