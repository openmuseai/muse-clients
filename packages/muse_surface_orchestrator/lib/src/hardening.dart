import 'dart:collection';

enum MuseRolloutMode { disabled, shadow, cohort, enabled }

final class MuseRolloutDecision {
  const MuseRolloutDecision({
    required this.mode,
    required this.mayProbe,
    required this.mayOpen,
    required this.reasonCode,
  });
  final MuseRolloutMode mode;
  final bool mayProbe, mayOpen;
  final String reasonCode;
}

final class MuseEngineRolloutGate {
  MuseEngineRolloutGate({
    required Map<String, MuseRolloutMode> adapterModes,
    Set<String> cohortActors = const {},
  }) : _adapterModes = Map.unmodifiable(adapterModes),
       _cohortActors = Set.unmodifiable(cohortActors);
  final Map<String, MuseRolloutMode> _adapterModes;
  final Set<String> _cohortActors;
  MuseRolloutDecision decide(String adapterRef, {required String actorRef}) {
    final mode = _adapterModes[adapterRef] ?? MuseRolloutMode.disabled;
    return switch (mode) {
      MuseRolloutMode.disabled => const MuseRolloutDecision(
        mode: MuseRolloutMode.disabled,
        mayProbe: false,
        mayOpen: false,
        reasonCode: 'FEATURE_DISABLED',
      ),
      MuseRolloutMode.shadow => const MuseRolloutDecision(
        mode: MuseRolloutMode.shadow,
        mayProbe: true,
        mayOpen: false,
        reasonCode: 'SHADOW_ONLY',
      ),
      MuseRolloutMode.cohort => MuseRolloutDecision(
        mode: mode,
        mayProbe: true,
        mayOpen: _cohortActors.contains(actorRef),
        reasonCode: _cohortActors.contains(actorRef)
            ? 'COHORT_ENABLED'
            : 'COHORT_EXCLUDED',
      ),
      MuseRolloutMode.enabled => const MuseRolloutDecision(
        mode: MuseRolloutMode.enabled,
        mayProbe: true,
        mayOpen: true,
        reasonCode: 'FEATURE_ENABLED',
      ),
    };
  }
}

final class MuseAdapterCircuitBreaker {
  MuseAdapterCircuitBreaker({
    this.failureThreshold = 3,
    this.cooldown = const Duration(seconds: 30),
    int Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch) {
    if (failureThreshold < 1)
      throw ArgumentError.value(failureThreshold, 'failureThreshold');
  }
  final int failureThreshold;
  final Duration cooldown;
  final int Function() _clock;
  final _states = <String, _BreakerState>{};
  void success(String adapterRef) => _states.remove(adapterRef);
  void failure(String adapterRef) {
    final state = _states.putIfAbsent(adapterRef, () => _BreakerState());
    state.failures++;
    if (state.failures >= failureThreshold) state.openedAt = _clock();
  }

  bool allows(String adapterRef) {
    final state = _states[adapterRef];
    if (state?.openedAt == null) return true;
    if (_clock() - state!.openedAt! >= cooldown.inMilliseconds) {
      _states.remove(adapterRef);
      return true;
    }
    return false;
  }

  Set<String> get deniedAdapterRefs =>
      _states.keys.where((ref) => !allows(ref)).toSet();
}

final class _BreakerState {
  int failures = 0;
  int? openedAt;
}

final class MuseLatencyHistogram {
  MuseLatencyHistogram({this.maxSamples = 2048});
  final int maxSamples;
  final ListQueue<int> _samples = ListQueue<int>();
  int get count => _samples.length;
  void record(Duration value) {
    _samples.add(value.inMicroseconds);
    while (_samples.length > maxSamples) {
      _samples.removeFirst();
    }
  }

  Duration percentile(double percentile) {
    if (_samples.isEmpty) return Duration.zero;
    if (percentile < 0 || percentile > 1)
      throw ArgumentError.value(percentile, 'percentile');
    final sorted = _samples.toList()..sort();
    final index = ((sorted.length - 1) * percentile).ceil();
    return Duration(microseconds: sorted[index]);
  }
}

final class MuseLeakSnapshot {
  const MuseLeakSnapshot({
    required this.pendingRequests,
    required this.sessions,
    required this.materializations,
    required this.surfaces,
  });
  final int pendingRequests, sessions, materializations, surfaces;
  bool get isZero =>
      pendingRequests == 0 &&
      sessions == 0 &&
      materializations == 0 &&
      surfaces == 0;
  void verifyZero() {
    if (!isZero)
      throw StateError(
        'RESOURCE_LEAK:pending=$pendingRequests,sessions=$sessions,materializations=$materializations,surfaces=$surfaces',
      );
  }
}
