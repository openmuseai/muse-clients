import 'package:flutter_test/flutter_test.dart';
import 'package:muse_engine_adapter/muse_engine_adapter.dart';
import 'package:muse_ioffice_adapter/muse_ioffice_adapter.dart';
import 'package:muse_resource_contract/muse_resource_contract.dart';

void main() {
  test(
    'current admission is honest: Word view only, placeholders unavailable',
    () {
      final catalog = MuseOfficeAdmissionCatalog.current();
      expect(catalog[MuseOfficeKind.word].effectiveModes, {
        MuseEngineMode.view,
      });
      expect(catalog[MuseOfficeKind.word].exportCertified, isFalse);
      for (final kind in [
        MuseOfficeKind.excel,
        MuseOfficeKind.slides,
        MuseOfficeKind.pdf,
      ]) {
        expect(catalog[kind].engineBound, isFalse);
        expect(catalog[kind].effectiveCreatable, isFalse);
        expect(catalog[kind].effectiveModes, isEmpty);
      }
    },
  );
  test(
    'manifest does not advertise edit/commit before toDocx certification',
    () {
      final adapter = _adapter();
      expect(adapter.manifest.modes, [MuseEngineMode.view]);
      expect(
        adapter.manifest.capabilities,
        isNot(contains(MuseAdapterCapability.commit)),
      );
    },
  );
  test('probe validates artifact, ABI, layout, format and platform', () async {
    expect(
      (await _adapter().probe(_probe(), MuseCancellationToken())).available,
      isTrue,
    );
    expect(
      (await _adapter(
        health: _health(digestMatches: false),
      ).probe(_probe(), MuseCancellationToken())).available,
      isFalse,
    );
    expect(
      (await _adapter().probe(
        _probe(format: 'ooxml.spreadsheet'),
        MuseCancellationToken(),
      )).available,
      isFalse,
    );
    expect(
      (await _adapter().probe(
        _probe(os: 'windows'),
        MuseCancellationToken(),
      )).available,
      isFalse,
    );
  });
  test(
    'heap edit remains internal ephemeral and never becomes save edit',
    () async {
      final adapter = _adapter(ephemeral: true);
      final result = await adapter.probe(
        _probe(mode: MuseRequestedMode.preferEdit),
        MuseCancellationToken(),
      );
      expect(result.effectiveModes, contains(MuseEngineMode.ephemeralEdit));
      expect(result.effectiveModes, isNot(contains(MuseEngineMode.edit)));
      expect(
        adapter.manifest.capabilities,
        isNot(contains(MuseAdapterCapability.commit)),
      );
    },
  );
  test('open requires opaque bytes handle and disposes exactly once', () async {
    final runtime = _Runtime(_health());
    final adapter = _adapter(runtime: runtime);
    final request = MuseOpenEngineSessionRequestV1(
      requestRef: 'p',
      attemptRef: 'a',
      resourceRef: 'r',
      baseRevision: 'rev',
      mode: MuseEngineMode.view,
      materialization: const MuseOpenMaterializationV1(
        kind: MuseMaterializationKind.bytesHandle,
        handleRef: 'h',
        expiresAt: 9999999999999,
      ),
      surface: const MuseOpenSurfaceV1(
        windowRef: 'w',
        placement: 'main',
        reuse: 'compatible',
      ),
      generation: 1,
    );
    final handle = await adapter.open(request, MuseCancellationToken());
    await adapter.focus(handle);
    await adapter.close(handle, reason: 'test');
    await adapter.close(handle, reason: 'again');
    expect(runtime.session.focusCalls, 1);
    expect(runtime.session.disposeCalls, 1);
    expect(adapter.liveSessionCount, 0);
  });
}

MuseIofficeWordHealth _health({bool digestMatches = true}) =>
    MuseIofficeWordHealth(
      artifactPresent: true,
      digestMatches: digestMatches,
      abiMatches: true,
      ffiInitialized: true,
      smokeLayoutPassed: true,
      canEditHeap: true,
      canExportDocx: false,
      runtimeDigest: 'sha256:word',
      os: 'macos',
      arch: 'arm64',
    );
MuseIofficeWordAdapter _adapter({
  MuseIofficeWordHealth? health,
  _Runtime? runtime,
  bool ephemeral = false,
}) => MuseIofficeWordAdapter(
  runtime: runtime ?? _Runtime(health ?? _health()),
  admission: MuseOfficeAdmissionCatalog.current()[MuseOfficeKind.word],
  allowInternalEphemeralEdit: ephemeral,
);
MuseProbeRequestV1 _probe({
  String format = 'ooxml.word',
  String os = 'macos',
  MuseRequestedMode mode = MuseRequestedMode.view,
}) => MuseProbeRequestV1(
  probeRef: 'probe',
  descriptor: MuseProbeDescriptorV1(
    resourceRef: 'r',
    revision: 'rev',
    format: MuseResourceFormat(
      formatId: format,
      confidence: MuseFormatConfidence.verified,
    ),
    sizeBytes: 42,
    security: const MuseResourceSecurity(
      classification: MuseSecurityClassification.internal,
      activeContent: MuseActiveContent.none,
    ),
  ),
  placement: MuseProbePlacementV1(
    kind: MusePlacementKind.desktopLocal,
    os: os,
    arch: 'arm64',
    memoryBudgetBytes: 1000000,
    gpu: false,
  ),
  requestedMode: mode,
  policyRevision: 'p',
  deadlineAt: 9999999999999,
  cancellationRef: 'c',
);

final class _Runtime implements MuseIofficeWordRuntime {
  _Runtime(this.value);
  final MuseIofficeWordHealth value;
  final session = _Session();
  @override
  Future<MuseIofficeWordHealth> health() async => value;
  @override
  Future<MuseIofficeWordRuntimeSession> open(
    MuseOpenEngineSessionRequestV1 request,
    MuseCancellationToken cancellation,
  ) async => session;
}

final class _Session implements MuseIofficeWordRuntimeSession {
  @override
  String get sessionRef => 'word.session';
  @override
  String get surfaceInstanceRef => 'word.surface';
  int focusCalls = 0, disposeCalls = 0;
  @override
  Future<void> focus() async {
    focusCalls++;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}
