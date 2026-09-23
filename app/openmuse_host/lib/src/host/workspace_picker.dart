import 'package:flutter/services.dart';

final class WorkspacePicker {
  const WorkspacePicker();

  static const _channel = MethodChannel('com.openmuse.host/workspace');

  Future<String?> chooseDirectory() =>
      _channel.invokeMethod<String>('chooseDirectory');

  Future<void> reveal(String path) =>
      _channel.invokeMethod<void>('reveal', {'path': path});
}
