import 'dart:convert';

final class MuseViewerBridgeEvent {
  const MuseViewerBridgeEvent({
    required this.type,
    required this.generation,
    this.page,
    this.errorCode,
  });
  final String type;
  final int generation;
  final int? page;
  final String? errorCode;
}

final class MuseViewerBridgeSession {
  MuseViewerBridgeSession({
    required this.origin,
    required this.nonce,
    required this.generation,
    this.maxMessageBytes = 64 * 1024,
  });
  final String origin, nonce;
  final int generation, maxMessageBytes;
  var _closed = false;
  bool get isClosed => _closed;
  MuseViewerBridgeEvent? receive({
    required String sourceOrigin,
    required Map<String, Object?> message,
  }) {
    if (_closed || sourceOrigin != origin) return null;
    if (utf8.encode(jsonEncode(message)).length > maxMessageBytes) return null;
    if (message['protocol'] != 'muse.viewer-bridge/v1' ||
        message['nonce'] != nonce ||
        message['generation'] != generation)
      return null;
    final type = message['type'];
    if (type is! String ||
        !{'viewer.ready', 'viewer.error', 'viewer.view-state'}.contains(type))
      return null;
    final page = message['page'];
    final errorCode = message['errorCode'];
    if (page != null && page is! int ||
        errorCode != null && errorCode is! String)
      return null;
    return MuseViewerBridgeEvent(
      type: type,
      generation: generation,
      page: page as int?,
      errorCode: errorCode as String?,
    );
  }

  void close() => _closed = true;
}
