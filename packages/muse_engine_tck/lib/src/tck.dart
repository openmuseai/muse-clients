import 'package:muse_engine_adapter/muse_engine_adapter.dart';
import 'package:muse_resource_contract/muse_resource_contract.dart';

final class MuseAdapterTckScenario {
  const MuseAdapterTckScenario({
    required this.adapter,
    required this.probeRequest,
    required this.openRequest,
  });
  final MuseEngineAdapter adapter;
  final MuseProbeRequestV1 probeRequest;
  final MuseOpenEngineSessionRequestV1 Function(MuseProbeResultV1 result)
  openRequest;
}

final class MuseAdapterTckReport {
  const MuseAdapterTckReport(this.failures);
  final List<String> failures;
  bool get passed => failures.isEmpty;
}

final class MuseAdapterTck {
  const MuseAdapterTck();
  Future<MuseAdapterTckReport> run(MuseAdapterTckScenario scenario) async {
    final failures = <String>[];
    final manifest = scenario.adapter.manifest;
    try {
      final parsed = MuseEngineAdapterManifestV1.fromJson(manifest.toJson());
      if (parsed.adapterRef != manifest.adapterRef)
        failures.add('MANIFEST_ROUNDTRIP');
    } catch (_) {
      failures.add('MANIFEST_INVALID');
    }
    if (manifest.formats.map((value) => value.formatId).toSet().length !=
        manifest.formats.length)
      failures.add('FORMAT_DUPLICATE');
    if (manifest.modes.contains(MuseEngineMode.edit) &&
        !manifest.capabilities.contains(MuseAdapterCapability.commit))
      failures.add('EDIT_WITHOUT_COMMIT');
    final cancellation = MuseCancellationToken();
    MuseProbeResultV1 result;
    try {
      result = await scenario.adapter.probe(
        scenario.probeRequest,
        cancellation,
      );
    } catch (_) {
      failures.add('PROBE_THREW');
      return MuseAdapterTckReport(failures);
    }
    if (result.probeRef != scenario.probeRequest.probeRef)
      failures.add('PROBE_REF_MISMATCH');
    if (!manifest.modes.toSet().containsAll(result.effectiveModes))
      failures.add('PROBE_MODE_ESCALATION');
    if (!manifest.materializations.toSet().containsAll(
      result.materializationKinds,
    ))
      failures.add('PROBE_MATERIALIZATION_ESCALATION');
    if (!result.available &&
        (result.effectiveModes.isNotEmpty ||
            result.materializationKinds.isNotEmpty))
      failures.add('UNAVAILABLE_WITH_CAPABILITIES');
    if (!result.available) return MuseAdapterTckReport(failures);
    MuseEngineSessionHandleV1? handle;
    try {
      final open = scenario.openRequest(result);
      handle = await scenario.adapter.open(open, MuseCancellationToken());
      if (handle.adapterRef != manifest.adapterRef)
        failures.add('SESSION_ADAPTER_MISMATCH');
      if (handle.resourceRef != open.resourceRef ||
          handle.baseRevision != open.baseRevision)
        failures.add('SESSION_RESOURCE_MISMATCH');
      if (handle.generation != open.generation)
        failures.add('SESSION_GENERATION_MISMATCH');
      await scenario.adapter.focus(handle);
    } catch (_) {
      failures.add('OPEN_OR_FOCUS_FAILED');
    }
    if (handle != null) {
      try {
        await scenario.adapter.close(handle, reason: 'tck');
        await scenario.adapter.close(handle, reason: 'tck-idempotency');
      } catch (_) {
        failures.add('CLOSE_NOT_IDEMPOTENT');
      }
    }
    return MuseAdapterTckReport(failures);
  }
}
