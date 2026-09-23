enum MuseCertificationStatus { blocked, passed, revoked }

final class MuseEnginePlatformCertification {
  const MuseEnginePlatformCertification({
    required this.adapterRef,
    required this.os,
    required this.arch,
    required this.status,
    required this.runtimeDigest,
    required this.certifiedCapabilities,
  });
  final String adapterRef, os, arch, runtimeDigest;
  final MuseCertificationStatus status;
  final Set<String> certifiedCapabilities;
  String get key => '$adapterRef/$os/$arch';
}

final class MuseEngineEcosystemCatalog {
  final _certifications = <String, MuseEnginePlatformCertification>{};
  void register(MuseEnginePlatformCertification value) {
    final current = _certifications[value.key];
    if (current != null && current.runtimeDigest != value.runtimeDigest)
      throw StateError('CERTIFICATION_DIGEST_CONFLICT:${value.key}');
    _certifications[value.key] = value;
  }

  bool isAdmitted(
    String adapterRef, {
    required String os,
    required String arch,
    required String runtimeDigest,
    required Set<String> requiredCapabilities,
  }) {
    final value = _certifications['$adapterRef/$os/$arch'];
    return value != null &&
        value.status == MuseCertificationStatus.passed &&
        value.runtimeDigest == runtimeDigest &&
        value.certifiedCapabilities.containsAll(requiredCapabilities);
  }

  void revoke(String adapterRef, {required String os, required String arch}) {
    final key = '$adapterRef/$os/$arch';
    final current = _certifications[key];
    if (current == null) return;
    _certifications[key] = MuseEnginePlatformCertification(
      adapterRef: current.adapterRef,
      os: current.os,
      arch: current.arch,
      status: MuseCertificationStatus.revoked,
      runtimeDigest: current.runtimeDigest,
      certifiedCapabilities: current.certifiedCapabilities,
    );
  }
}
