import 'dart:convert';
import 'dart:io';

import 'package:openmuse_plugin_sdk/openmuse_plugin_sdk.dart';
import 'package:path/path.dart' as p;

/// Registers Host-granted local Mounts with the current DSH RPC catalog.
/// It never removes user-created DSH workspaces or imports old app state.
final class DshWorkspaceSynchronizer {
  DshWorkspaceSynchronizer({required this.context, required this.endpoint});

  final OpenMusePluginContext context;
  final Uri? Function() endpoint;
  Future<void> _pending = Future<void>.value();
  String? _fingerprint;
  int _rpcCounter = 0;

  Future<void> sync() {
    _pending = _pending.catchError((Object _) {}).then((_) => _syncNow());
    return _pending;
  }

  Future<void> _syncNow() async {
    final base = endpoint();
    if (base == null) return;
    if (base.scheme != 'http' || base.host != '127.0.0.1') {
      throw const FormatException('DSH endpoint 必须是本机 loopback');
    }
    final raw = await context.executeHostCommand('workspace.snapshot', null);
    if (raw is! Map || raw['mounts'] is! List) {
      throw const FormatException('无效 Host Workspace 快照');
    }
    final mounts = <String>[];
    for (final value in raw['mounts'] as List) {
      if (value is! Map || value['path'] is! String) continue;
      final path = value['path'] as String;
      if (p.isAbsolute(path) && !mounts.contains(path)) mounts.add(path);
    }
    final active = raw['activeMountPath'];
    if (active is String && mounts.remove(active)) mounts.insert(0, active);
    final fingerprint = jsonEncode([base.toString(), mounts]);
    if (_fingerprint == fingerprint) return;
    final ids = <String>[];
    for (final path in mounts) {
      final value = await _rpc(base, 'workspace.create', {'path': path});
      final workspace = value['workspace'];
      if (workspace is! Map || workspace['workspaceId'] is! String) {
        throw const FormatException('DSH 返回无效 workspace.create 结果');
      }
      ids.add(workspace['workspaceId'] as String);
    }
    // Newly adopted workspaces are prepended by DSH; restore Host's order
    // without deleting or renaming any workspace the DSH user owns.
    for (var index = ids.length - 2; index >= 0; index--) {
      await _rpc(base, 'workspace.insertBefore', {
        'workspaceId': ids[index],
        'beforeWorkspaceId': ids[index + 1],
      });
    }
    _fingerprint = fingerprint;
  }

  Future<Map<String, Object?>> _rpc(
    Uri base,
    String method,
    Map<String, Object?> payload,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final uri = base.resolve('/api/$method');
      final request = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 5));
      request.headers.contentType = ContentType.json;
      final rpcId =
          'openmuse-${DateTime.now().microsecondsSinceEpoch}-${_rpcCounter++}';
      request.write(
        jsonEncode({
          'type': 'client-request',
          'rpcId': rpcId,
          'method': method,
          'payload': payload,
        }),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'DSH $method HTTP ${response.statusCode}',
          uri: uri,
        );
      }
      final body = jsonDecode(await utf8.decoder.bind(response).join());
      if (body is! Map || body['rpcId'] != rpcId || body['result'] is! Map) {
        throw const FormatException('无效 DSH RPC 响应');
      }
      final result = body['result'] as Map;
      if (result['ok'] != true || result['value'] is! Map) {
        throw StateError('DSH $method 失败：${result['error']}');
      }
      return Map<String, Object?>.from(result['value'] as Map);
    } finally {
      client.close(force: true);
    }
  }
}
