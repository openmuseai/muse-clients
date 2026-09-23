enum MuseWorkingCopyState { clean, dirty, committing, conflict, failed, closed }

enum MuseWorkingCopyCommitResult {
  committed,
  noChange,
  conflict,
  denied,
  failed,
}

final class MuseWorkingCopyCommitIntent {
  const MuseWorkingCopyCommitIntent({
    required this.commitRef,
    required this.expectedRevision,
    required this.digest,
    required this.idempotencyKey,
  });
  final String commitRef, expectedRevision, digest, idempotencyKey;
}

final class MuseWorkingCopyCommitController {
  MuseWorkingCopyCommitController({required String baseRevision})
    : _baseRevision = baseRevision;
  String _baseRevision;
  String? _workingDigest;
  MuseWorkingCopyState _state = MuseWorkingCopyState.clean;
  final _receipts = <String, MuseWorkingCopyCommitResult>{};
  MuseWorkingCopyState get state => _state;
  String get baseRevision => _baseRevision;
  bool get mayClose =>
      _state == MuseWorkingCopyState.clean ||
      _state == MuseWorkingCopyState.closed;
  void stableWrite(String digest) {
    if (_state == MuseWorkingCopyState.closed)
      throw StateError('WORKING_COPY_CLOSED');
    if (_state == MuseWorkingCopyState.committing)
      throw StateError('COMMIT_IN_FLIGHT');
    _workingDigest = digest;
    _state = MuseWorkingCopyState.dirty;
  }

  MuseWorkingCopyCommitIntent begin({
    required String commitRef,
    required String idempotencyKey,
  }) {
    if (_state == MuseWorkingCopyState.closed)
      throw StateError('WORKING_COPY_CLOSED');
    final prior = _receipts[idempotencyKey];
    if (prior != null)
      throw StateError('COMMIT_ALREADY_TERMINAL:${prior.name}');
    if (_state != MuseWorkingCopyState.dirty || _workingDigest == null)
      throw StateError('NOT_DIRTY');
    _state = MuseWorkingCopyState.committing;
    return MuseWorkingCopyCommitIntent(
      commitRef: commitRef,
      expectedRevision: _baseRevision,
      digest: _workingDigest!,
      idempotencyKey: idempotencyKey,
    );
  }

  void complete(
    MuseWorkingCopyCommitIntent intent,
    MuseWorkingCopyCommitResult result, {
    String? newRevision,
  }) {
    if (_state != MuseWorkingCopyState.committing)
      throw StateError('COMMIT_NOT_IN_FLIGHT');
    _receipts[intent.idempotencyKey] = result;
    switch (result) {
      case MuseWorkingCopyCommitResult.committed:
        if (newRevision == null || newRevision.isEmpty)
          throw ArgumentError('newRevision required');
        _baseRevision = newRevision;
        _workingDigest = null;
        _state = MuseWorkingCopyState.clean;
      case MuseWorkingCopyCommitResult.noChange:
        _workingDigest = null;
        _state = MuseWorkingCopyState.clean;
      case MuseWorkingCopyCommitResult.conflict:
        _state = MuseWorkingCopyState.conflict;
      case MuseWorkingCopyCommitResult.denied ||
          MuseWorkingCopyCommitResult.failed:
        _state = MuseWorkingCopyState.failed;
    }
  }

  void retainDraftAfterFailure() {
    if (_state != MuseWorkingCopyState.conflict &&
        _state != MuseWorkingCopyState.failed)
      throw StateError('NO_FAILED_DRAFT');
    _state = MuseWorkingCopyState.dirty;
  }

  void discardAndClose() {
    _workingDigest = null;
    _state = MuseWorkingCopyState.closed;
  }

  void closeClean() {
    if (!mayClose) throw StateError('DIRTY_CLOSE_REQUIRES_DECISION');
    _state = MuseWorkingCopyState.closed;
  }
}
