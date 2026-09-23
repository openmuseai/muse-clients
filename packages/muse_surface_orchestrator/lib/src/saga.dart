import 'dart:async';

final class MuseOpenSaga {
  final _disposers = <FutureOr<void> Function()>[];
  var _closed = false;
  int get effectCount => _disposers.length;
  bool get isClosed => _closed;
  void own(FutureOr<void> Function() disposer) {
    if (_closed) throw StateError('SAGA_CLOSED');
    _disposers.add(disposer);
  }

  void release(FutureOr<void> Function() disposer) =>
      _disposers.remove(disposer);
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final disposer in _disposers.reversed) {
      try {
        await disposer();
      } catch (_) {}
    }
    _disposers.clear();
  }
}
