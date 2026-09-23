import 'package:muse_resource_contract/muse_resource_contract.dart';

import 'probe_coordinator.dart';
import 'registry.dart';

final class MuseRoutePolicy {
  const MuseRoutePolicy({
    required this.revision,
    this.deniedAdapterRefs = const {},
    this.preferredAdapterRefs = const [],
    this.allowModeDowngrade = true,
  });
  final String revision;
  final Set<String> deniedAdapterRefs;
  final List<String> preferredAdapterRefs;
  final bool allowModeDowngrade;
}

final class MuseRouteSelection {
  const MuseRouteSelection({
    required this.registration,
    required this.probe,
    required this.effectiveMode,
    required this.score,
    required this.reasonCodes,
    required this.candidates,
  });
  final MuseAdapterRegistration registration;
  final MuseProbeResultV1 probe;
  final MuseEngineMode effectiveMode;
  final int score;
  final List<String> reasonCodes;
  final List<MuseRouteCandidateV2> candidates;
}

final class MuseEngineRouter {
  const MuseEngineRouter();
  MuseRouteSelection? select({
    required List<MuseProbeOutcome> outcomes,
    required MuseRequestedMode requestedMode,
    required MuseRoutePolicy policy,
  }) {
    final ranked = <_Ranked>[];
    for (final outcome in outcomes) {
      final probe = outcome.result;
      if (probe == null ||
          !probe.available ||
          policy.deniedAdapterRefs.contains(outcome.registration.adapterRef)) {
        ranked.add(
          _Ranked(
            outcome: outcome,
            mode: null,
            score: 0,
            reasons: [
              if (policy.deniedAdapterRefs.contains(
                outcome.registration.adapterRef,
              ))
                'POLICY_DENIED'
              else
                outcome.errorCode ?? 'ADAPTER_UNAVAILABLE',
            ],
          ),
        );
        continue;
      }
      final mode = _mode(
        probe.effectiveModes,
        requestedMode,
        policy.allowModeDowngrade,
      );
      if (mode == null) {
        ranked.add(
          _Ranked(
            outcome: outcome,
            mode: null,
            score: 0,
            reasons: const ['MODE_UNAVAILABLE'],
          ),
        );
        continue;
      }
      var score =
          500 +
          _fidelity(probe.quality.fidelity) +
          _startup(probe.quality.startupClass);
      final preference = policy.preferredAdapterRefs.indexOf(
        outcome.registration.adapterRef,
      );
      if (preference >= 0) score += 200 - preference;
      final reasons = <String>[
        if (_isDowngrade(requestedMode, mode)) 'MODE_DOWNGRADED',
      ];
      ranked.add(
        _Ranked(outcome: outcome, mode: mode, score: score, reasons: reasons),
      );
    }
    ranked.sort((a, b) {
      final score = b.score.compareTo(a.score);
      return score != 0
          ? score
          : a.outcome.registration.adapterRef.compareTo(
              b.outcome.registration.adapterRef,
            );
    });
    final candidates = ranked
        .map(
          (item) => MuseRouteCandidateV2(
            adapterRef: item.outcome.registration.adapterRef,
            available: item.mode != null,
            effectiveModes:
                item.outcome.result?.effectiveModes
                    .map((mode) => MuseEffectiveMode.values.byName(mode.name))
                    .toList() ??
                const [],
            score: item.score,
            reasonCodes: item.reasons,
          ),
        )
        .toList(growable: false);
    final selected = ranked.where((item) => item.mode != null).firstOrNull;
    if (selected == null) return null;
    return MuseRouteSelection(
      registration: selected.outcome.registration,
      probe: selected.outcome.result!,
      effectiveMode: selected.mode!,
      score: selected.score,
      reasonCodes: selected.reasons,
      candidates: candidates,
    );
  }

  MuseEngineMode? _mode(
    List<MuseEngineMode> modes,
    MuseRequestedMode requested,
    bool downgrade,
  ) {
    if (requested == MuseRequestedMode.view)
      return modes.contains(MuseEngineMode.view) ? MuseEngineMode.view : null;
    if (requested == MuseRequestedMode.edit) {
      if (modes.contains(MuseEngineMode.edit)) return MuseEngineMode.edit;
      return null;
    }
    if (modes.contains(MuseEngineMode.edit)) return MuseEngineMode.edit;
    if (downgrade && modes.contains(MuseEngineMode.ephemeralEdit))
      return MuseEngineMode.ephemeralEdit;
    if (downgrade && modes.contains(MuseEngineMode.view))
      return MuseEngineMode.view;
    return null;
  }

  bool _isDowngrade(MuseRequestedMode request, MuseEngineMode mode) =>
      request == MuseRequestedMode.preferEdit && mode != MuseEngineMode.edit;
  int _fidelity(MuseFidelity value) => switch (value) {
    MuseFidelity.nativeEngine => 300,
    MuseFidelity.nativePartial => 220,
    MuseFidelity.converted => 120,
    MuseFidelity.generic => 50,
  };
  int _startup(MuseStartupClass value) => switch (value) {
    MuseStartupClass.hotFast => 100,
    MuseStartupClass.warmMedium => 50,
    MuseStartupClass.coldSlow => 0,
  };
}

final class _Ranked {
  const _Ranked({
    required this.outcome,
    required this.mode,
    required this.score,
    required this.reasons,
  });
  final MuseProbeOutcome outcome;
  final MuseEngineMode? mode;
  final int score;
  final List<String> reasons;
}
