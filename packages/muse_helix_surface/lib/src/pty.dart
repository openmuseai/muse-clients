final class MuseHelixPtySize {
  const MuseHelixPtySize({required this.columns, required this.rows});
  final int columns, rows;
}

final class MuseHelixUserInputGrant {
  const MuseHelixUserInputGrant._(this.sessionRef, this.generation);
  final String sessionRef;
  final int generation;
  static MuseHelixUserInputGrant issueForUser(
    String sessionRef,
    int generation,
  ) => MuseHelixUserInputGrant._(sessionRef, generation);
}

abstract interface class MuseHelixRuntimeSession {
  String get sessionRef;
  String get surfaceInstanceRef;
  Future<void> focus();
  Future<void> resize(MuseHelixPtySize size);
  Future<void> sendUserInput(List<int> bytes, MuseHelixUserInputGrant grant);
  Future<void> terminate();
}
