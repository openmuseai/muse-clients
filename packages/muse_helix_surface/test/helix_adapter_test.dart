import 'package:flutter_test/flutter_test.dart';
import 'package:muse_engine_adapter/muse_engine_adapter.dart';
import 'package:muse_helix_surface/muse_helix_surface.dart';
import 'package:muse_resource_contract/muse_resource_contract.dart';

void main() {
  test('current admission remains closed until all H0 gates pass', () async {
    expect(MuseHelixAdmission.current.h0Passed, isFalse);
    expect(MuseHelixAdmission.current.viewAdmitted, isFalse);
    expect(MuseHelixAdmission.current.editAdmitted, isFalse);
    expect(
      _adapter(MuseHelixAdmission.current).manifest.modes,
      [MuseEngineMode.view],
      reason: 'manifest is a candidate; runtime probe remains unavailable',
    );
    expect(
      (await _adapter(
        MuseHelixAdmission.current,
      ).probe(_probe(), MuseCancellationToken())).available,
      isFalse,
    );
  });
  test('read-only certification never advertises edit or commit', () async {
    final admission = _admission(view: true);
    final adapter = _adapter(admission);
    expect(adapter.manifest.modes, [MuseEngineMode.view]);
    expect(
      adapter.manifest.capabilities,
      isNot(contains(MuseAdapterCapability.commit)),
    );
    expect(
      (await adapter.probe(_probe(), MuseCancellationToken())).available,
      isTrue,
    );
    expect(
      (await adapter.probe(
        _probe(mode: MuseRequestedMode.edit),
        MuseCancellationToken(),
      )).available,
      isFalse,
    );
  });
  test(
    'probe rejects binary content, bad digest and uncertified platform',
    () async {
      final admission = _admission(view: true);
      expect(
        (await _adapter(admission).probe(
          _probe(active: MuseActiveContent.unknown),
          MuseCancellationToken(),
        )).available,
        isFalse,
      );
      expect(
        (await _adapter(
          admission,
          health: _health(digest: false),
        ).probe(_probe(), MuseCancellationToken())).available,
        isFalse,
      );
      expect(
        (await _adapter(
          admission,
        ).probe(_probe(os: 'windows'), MuseCancellationToken())).available,
        isFalse,
      );
    },
  );
  test(
    'PTY input requires a user grant scoped to session generation',
    () async {
      final runtime = _Runtime(_health());
      final adapter = _adapter(_admission(view: true), runtime: runtime);
      final handle = await adapter.open(_open(), MuseCancellationToken());
      final grant = adapter.grantUserInput(handle);
      await adapter.sendUserInput(handle, [0x69], grant);
      await adapter.resize(
        handle,
        const MuseHelixPtySize(columns: 160, rows: 50),
      );
      expect(runtime.session.inputCalls, 1);
      expect(runtime.session.resizeCalls, 1);
      final other = MuseEngineSessionHandleV1(
        sessionRef: handle.sessionRef,
        surfaceInstanceRef: handle.surfaceInstanceRef,
        adapterRef: handle.adapterRef,
        resourceRef: handle.resourceRef,
        baseRevision: handle.baseRevision,
        mode: handle.mode,
        generation: 2,
        state: handle.state,
      );
      expect(
        () => adapter.sendUserInput(other, [1], grant),
        throwsA(isA<MuseAdapterException>()),
      );
      await adapter.close(handle, reason: 'test');
      await adapter.close(handle, reason: 'again');
      expect(runtime.session.terminateCalls, 1);
    },
  );
  test(
    'working-copy state prevents dirty close and models conflict recovery',
    () {
      final state = MuseWorkingCopyCommitController(baseRevision: 'r1');
      state.stableWrite('sha256:a');
      expect(state.mayClose, isFalse);
      expect(() => state.closeClean(), throwsStateError);
      final intent = state.begin(commitRef: 'c1', idempotencyKey: 'i1');
      expect(intent.expectedRevision, 'r1');
      state.complete(intent, MuseWorkingCopyCommitResult.conflict);
      expect(state.state, MuseWorkingCopyState.conflict);
      state.retainDraftAfterFailure();
      final retry = state.begin(commitRef: 'c2', idempotencyKey: 'i2');
      state.complete(
        retry,
        MuseWorkingCopyCommitResult.committed,
        newRevision: 'r2',
      );
      expect(state.baseRevision, 'r2');
      expect(state.mayClose, isTrue);
      state.closeClean();
      expect(state.state, MuseWorkingCopyState.closed);
    },
  );
}

MuseHelixAdmission _admission({bool view = false, bool edit = false}) =>
    MuseHelixAdmission(
      buildReproducible: true,
      runtimePackaged: true,
      ptyCertified: true,
      inputCertified: true,
      processCleanupCertified: true,
      signedArtifact: true,
      readOnlyCertified: view,
      watcherCertified: edit,
      commitCertified: edit,
      platforms: const [MusePlatformV1(os: 'macos', arch: 'arm64')],
      reasonCode: view ? 'CERTIFIED' : 'NOT_CERTIFIED',
    );
MuseHelixRuntimeHealth _health({bool digest = true}) => MuseHelixRuntimeHealth(
  binaryPresent: true,
  digestMatches: digest,
  runtimePresent: true,
  grammarReady: true,
  ptyReady: true,
  processTreeControl: true,
  os: 'macos',
  arch: 'arm64',
  runtimeDigest: 'sha256:hx',
);
MuseHelixAdapter _adapter(
  MuseHelixAdmission admission, {
  MuseHelixRuntimeHealth? health,
  _Runtime? runtime,
}) => MuseHelixAdapter(
  runtime: runtime ?? _Runtime(health ?? _health()),
  admission: admission,
);
MuseProbeRequestV1 _probe({
  String os = 'macos',
  MuseRequestedMode mode = MuseRequestedMode.view,
  MuseActiveContent active = MuseActiveContent.none,
}) => MuseProbeRequestV1(
  probeRef: 'probe',
  descriptor: MuseProbeDescriptorV1(
    resourceRef: 'r',
    revision: 'rev',
    format: const MuseResourceFormat(
      formatId: 'code.source',
      confidence: MuseFormatConfidence.verified,
    ),
    sizeBytes: 100,
    security: MuseResourceSecurity(
      classification: MuseSecurityClassification.internal,
      activeContent: active,
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
MuseOpenEngineSessionRequestV1 _open() => const MuseOpenEngineSessionRequestV1(
  requestRef: 'p',
  attemptRef: 'a',
  resourceRef: 'r',
  baseRevision: 'rev',
  mode: MuseEngineMode.view,
  materialization: MuseOpenMaterializationV1(
    kind: MuseMaterializationKind.workingCopy,
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

final class _Runtime implements MuseHelixRuntime {
  _Runtime(this.value);
  final MuseHelixRuntimeHealth value;
  final session = _Session();
  @override
  Future<MuseHelixRuntimeHealth> health() async => value;
  @override
  Future<MuseHelixRuntimeSession> spawn(
    MuseOpenEngineSessionRequestV1 request,
    MuseCancellationToken cancellation,
  ) async => session;
}

final class _Session implements MuseHelixRuntimeSession {
  @override
  String get sessionRef => 'hx.session';
  @override
  String get surfaceInstanceRef => 'hx.surface';
  int focusCalls = 0, resizeCalls = 0, inputCalls = 0, terminateCalls = 0;
  @override
  Future<void> focus() async {
    focusCalls++;
  }

  @override
  Future<void> resize(MuseHelixPtySize size) async {
    resizeCalls++;
  }

  @override
  Future<void> sendUserInput(
    List<int> bytes,
    MuseHelixUserInputGrant grant,
  ) async {
    inputCalls++;
  }

  @override
  Future<void> terminate() async {
    terminateCalls++;
  }
}
