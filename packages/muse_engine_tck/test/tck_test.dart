import 'package:flutter_test/flutter_test.dart';
import 'package:muse_engine_adapter/muse_engine_adapter.dart';
import 'package:muse_engine_tck/muse_engine_tck.dart';
import 'package:muse_resource_contract/muse_resource_contract.dart';

void main() {
  test('conforming adapter passes lifecycle and authority TCK', () async {
    final adapter = _Adapter();
    final report = await const MuseAdapterTck().run(
      MuseAdapterTckScenario(
        adapter: adapter,
        probeRequest: _probe(),
        openRequest: (result) => _open(),
      ),
    );
    expect(report.failures, isEmpty);
    expect(
      adapter.closeCalls,
      1,
      reason: 'adapter idempotently owns runtime close',
    );
  });
  test('TCK detects probe capability escalation', () async {
    final adapter = _Adapter(escalate: true);
    final report = await const MuseAdapterTck().run(
      MuseAdapterTckScenario(
        adapter: adapter,
        probeRequest: _probe(),
        openRequest: (result) => _open(),
      ),
    );
    expect(report.failures, contains('PROBE_MODE_ESCALATION'));
  });
  test('platform certification is exact, digest-bound and revocable', () {
    final catalog = MuseEngineEcosystemCatalog();
    const certification = MuseEnginePlatformCertification(
      adapterRef: 'viewer~1',
      os: 'macos',
      arch: 'arm64',
      status: MuseCertificationStatus.passed,
      runtimeDigest: 'sha256:a',
      certifiedCapabilities: {'view'},
    );
    catalog.register(certification);
    expect(
      catalog.isAdmitted(
        'viewer~1',
        os: 'macos',
        arch: 'arm64',
        runtimeDigest: 'sha256:a',
        requiredCapabilities: {'view'},
      ),
      isTrue,
    );
    expect(
      catalog.isAdmitted(
        'viewer~1',
        os: 'windows',
        arch: 'x64',
        runtimeDigest: 'sha256:a',
        requiredCapabilities: {'view'},
      ),
      isFalse,
    );
    expect(
      catalog.isAdmitted(
        'viewer~1',
        os: 'macos',
        arch: 'arm64',
        runtimeDigest: 'sha256:b',
        requiredCapabilities: {'view'},
      ),
      isFalse,
    );
    catalog.revoke('viewer~1', os: 'macos', arch: 'arm64');
    expect(
      catalog.isAdmitted(
        'viewer~1',
        os: 'macos',
        arch: 'arm64',
        runtimeDigest: 'sha256:a',
        requiredCapabilities: {'view'},
      ),
      isFalse,
    );
  });
}

MuseProbeRequestV1 _probe() => const MuseProbeRequestV1(
  probeRef: 'probe',
  descriptor: MuseProbeDescriptorV1(
    resourceRef: 'r',
    revision: 'rev',
    format: MuseResourceFormat(
      formatId: 'text.plain',
      confidence: MuseFormatConfidence.verified,
    ),
    security: MuseResourceSecurity(
      classification: MuseSecurityClassification.internal,
      activeContent: MuseActiveContent.none,
    ),
  ),
  placement: MuseProbePlacementV1(
    kind: MusePlacementKind.desktopLocal,
    os: 'macos',
    arch: 'arm64',
    memoryBudgetBytes: 1000000,
    gpu: false,
  ),
  requestedMode: MuseRequestedMode.view,
  policyRevision: 'p',
  deadlineAt: 9999999999999,
  cancellationRef: 'c',
);
MuseOpenEngineSessionRequestV1 _open() => const MuseOpenEngineSessionRequestV1(
  requestRef: 'p',
  attemptRef: 'a',
  resourceRef: 'r',
  baseRevision: 'rev',
  mode: MuseEngineMode.view,
  materialization: MuseOpenMaterializationV1(
    kind: MuseMaterializationKind.bytesHandle,
    handleRef: 'h',
    expiresAt: 9999999999999,
  ),
  surface: MuseOpenSurfaceV1(
    windowRef: 'w',
    placement: 'main',
    reuse: 'compatible',
  ),
  generation: 1,
);

final class _Adapter implements MuseEngineAdapter {
  _Adapter({this.escalate = false});
  final bool escalate;
  int closeCalls = 0;
  bool closed = false;
  @override
  MuseEngineAdapterManifestV1 get manifest => const MuseEngineAdapterManifestV1(
    adapterId: 'fake.tck',
    adapterVersion: '1.0.0',
    engine: MuseEngineIdentityV1(
      vendor: 'fake',
      engineId: 'fake',
      engineVersion: '1',
    ),
    placements: [MusePlacementKind.desktopLocal],
    platforms: [MusePlatformV1(os: 'macos', arch: 'arm64')],
    formats: [
      MuseFormatSupportV1(
        formatId: 'text.plain',
        mimeTypes: ['text/plain'],
        extensionsHint: ['txt'],
      ),
    ],
    modes: [MuseEngineMode.view],
    materializations: [MuseMaterializationKind.bytesHandle],
    contextProviders: [],
    capabilities: [MuseAdapterCapability.focus],
    risk: MuseAdapterRiskV1(
      executesProcess: false,
      executesActiveContent: false,
      requiresGpu: false,
    ),
  );
  @override
  Future<MuseProbeResultV1> probe(
    MuseProbeRequestV1 request,
    MuseCancellationToken cancellation,
  ) async => MuseProbeResultV1(
    probeRef: request.probeRef,
    available: true,
    effectiveModes: [MuseEngineMode.view, if (escalate) MuseEngineMode.edit],
    materializationKinds: const [MuseMaterializationKind.bytesHandle],
    maxBytes: 100,
    quality: const MuseProbeQualityV1(
      fidelity: MuseFidelity.generic,
      startupClass: MuseStartupClass.hotFast,
    ),
    warnings: const [],
    probeDigest: 'd',
    expiresAt: 9999999999999,
  );
  @override
  Future<MuseEngineSessionHandleV1> open(
    MuseOpenEngineSessionRequestV1 request,
    MuseCancellationToken cancellation,
  ) async => MuseEngineSessionHandleV1(
    sessionRef: 's',
    surfaceInstanceRef: 'surface',
    adapterRef: manifest.adapterRef,
    resourceRef: request.resourceRef,
    baseRevision: request.baseRevision,
    mode: request.mode,
    generation: request.generation,
    state: MuseEngineSessionState.ready,
  );
  @override
  Future<void> focus(MuseEngineSessionHandleV1 session) async {}
  @override
  Future<void> close(
    MuseEngineSessionHandleV1 session, {
    required String reason,
  }) async {
    if (closed) return;
    closed = true;
    closeCalls++;
  }
}
