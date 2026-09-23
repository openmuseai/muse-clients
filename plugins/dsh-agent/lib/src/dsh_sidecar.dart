import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

enum DshSidecarState { stopped, configurationRequired, starting, ready, failed }

final class DshSidecarSupervisor extends ChangeNotifier {
  DshSidecarSupervisor({Map<String, String>? environment})
    : environment = environment ?? Platform.environment;

  final Map<String, String> environment;
  DshSidecarState state = DshSidecarState.stopped;
  Process? _process;
  Future<void>? _starting;
  Object? lastError;
  Uri? endpoint;
  int launchCount = 0;
  final List<String> logTail = [];

  String? get cliPath {
    final explicit = environment['OPENMUSE_DSH_CLI'];
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final executableDir = File(Platform.resolvedExecutable).parent;
    final bundled = File(
      '${executableDir.parent.path}/Resources/openmuse/dsh/'
      'node_modules/@deepseek-ai/dsh/lib/bin.js',
    );
    return bundled.existsSync() ? bundled.path : null;
  }

  String get nodeExecutable {
    final executableDir = File(Platform.resolvedExecutable).parent;
    final bundled = File(
      '${executableDir.parent.path}/Resources/openmuse/dsh/node/bin/node',
    );
    return bundled.existsSync() ? bundled.path : 'node';
  }

  bool get hasModelKey => (environment['DEEPSEEK_API_KEY'] ?? '').isNotEmpty;

  Future<String> probeVersion() async {
    final cli = cliPath;
    if (cli == null || cli.isEmpty) {
      throw StateError('OPENMUSE_DSH_CLI is not configured');
    }
    final command = dshCommand(cli, [
      '--version',
    ], nodeExecutable: nodeExecutable);
    final result = await Process.run(command.executable, command.arguments);
    if (result.exitCode != 0) throw StateError('${result.stderr}');
    return '${result.stdout}'.trim();
  }

  Future<void> ensureStarted() async {
    if (state == DshSidecarState.ready) return;
    final inFlight = _starting;
    if (inFlight != null) return inFlight;
    final operation = _start();
    _starting = operation;
    try {
      await operation;
    } finally {
      _starting = null;
    }
  }

  Future<void> _start() async {
    final cli = cliPath;
    if (cli == null || cli.isEmpty) {
      state = DshSidecarState.configurationRequired;
      lastError = StateError('DSH runtime 尚未安装。');
      notifyListeners();
      return;
    }
    state = DshSidecarState.starting;
    lastError = null;
    endpoint = null;
    logTail.clear();
    notifyListeners();
    try {
      final command = dshWebCommand(cli, nodeExecutable: nodeExecutable);
      final reportedEndpoint = Completer<Uri>();
      final process = await Process.start(
        command.executable,
        command.arguments,
        environment: environment,
      );
      _process = process;
      launchCount++;
      _capture(process.stdout, reportedEndpoint: reportedEndpoint);
      _capture(process.stderr, reportedEndpoint: reportedEndpoint);
      unawaited(
        process.exitCode.then((code) {
          if (!reportedEndpoint.isCompleted) {
            reportedEndpoint.completeError(
              StateError('DSH exited with code $code before reporting ready'),
            );
          }
          if (_process != process) return;
          _process = null;
          endpoint = null;
          if (state != DshSidecarState.stopped) {
            state = DshSidecarState.failed;
            lastError = StateError('DSH exited with code $code');
            notifyListeners();
          }
        }),
      );
      final candidate = await reportedEndpoint.future.timeout(
        const Duration(seconds: 45),
        onTimeout: () => throw TimeoutException(
          'DSH did not report its ephemeral loopback endpoint',
        ),
      );
      await waitForHttp(candidate, const Duration(seconds: 45));
      endpoint = candidate;
      state = DshSidecarState.ready;
      notifyListeners();
    } catch (error) {
      state = DshSidecarState.failed;
      lastError = error;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> stop() async {
    _process?.kill();
    _process = null;
    endpoint = null;
    state = DshSidecarState.stopped;
    notifyListeners();
  }

  void _capture(
    Stream<List<int>> stream, {
    required Completer<Uri> reportedEndpoint,
  }) {
    stream.transform(utf8.decoder).transform(const LineSplitter()).listen((
      line,
    ) {
      logTail.add(_redact(line));
      if (logTail.length > 100) logTail.removeAt(0);
      if (!reportedEndpoint.isCompleted) {
        final match = RegExp(
          r'https?://127\.0\.0\.1:[0-9]+(?:/\?[^\s]*)?',
        ).firstMatch(line);
        final value = match?.group(0);
        if (value != null) reportedEndpoint.complete(Uri.parse(value));
      }
      notifyListeners();
    });
  }

  String _redact(String value) {
    final key = environment['DEEPSEEK_API_KEY'];
    return key == null || key.isEmpty
        ? value
        : value.replaceAll(key, '<redacted>');
  }

  @override
  void dispose() {
    _process?.kill();
    super.dispose();
  }
}

({String executable, List<String> arguments}) dshCommand(
  String cli,
  List<String> args, {
  String nodeExecutable = 'node',
}) {
  if (cli.endsWith('.js'))
    return (executable: nodeExecutable, arguments: [cli, ...args]);
  return (executable: cli, arguments: args);
}

({String executable, List<String> arguments}) dshWebCommand(
  String cli, {
  String nodeExecutable = 'node',
}) => dshCommand(cli, [
  'web',
  '--host',
  '127.0.0.1',
  '--port',
  '0',
], nodeExecutable: nodeExecutable);

Future<void> waitForHttp(Uri uri, Duration timeout) async {
  final deadline = DateTime.now().add(timeout);
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode < 500) return;
    } catch (error) {
      lastError = error;
    } finally {
      client.close(force: true);
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException(
    'DSH did not become ready at $uri; last error: $lastError',
  );
}
