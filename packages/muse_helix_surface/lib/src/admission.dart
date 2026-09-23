import 'package:muse_resource_contract/muse_resource_contract.dart';

final class MuseHelixAdmission {
  const MuseHelixAdmission({
    required this.buildReproducible,
    required this.runtimePackaged,
    required this.ptyCertified,
    required this.inputCertified,
    required this.processCleanupCertified,
    required this.signedArtifact,
    required this.readOnlyCertified,
    required this.watcherCertified,
    required this.commitCertified,
    required this.platforms,
    required this.reasonCode,
  });
  final bool buildReproducible,
      runtimePackaged,
      ptyCertified,
      inputCertified,
      processCleanupCertified,
      signedArtifact,
      readOnlyCertified,
      watcherCertified,
      commitCertified;
  final List<MusePlatformV1> platforms;
  final String reasonCode;
  bool get h0Passed =>
      buildReproducible &&
      runtimePackaged &&
      ptyCertified &&
      inputCertified &&
      processCleanupCertified &&
      signedArtifact;
  bool get viewAdmitted => h0Passed && readOnlyCertified;
  bool get editAdmitted => viewAdmitted && watcherCertified && commitCertified;
  static const current = MuseHelixAdmission(
    buildReproducible: false,
    runtimePackaged: false,
    ptyCertified: false,
    inputCertified: false,
    processCleanupCertified: false,
    signedArtifact: false,
    readOnlyCertified: false,
    watcherCertified: false,
    commitCertified: false,
    platforms: [MusePlatformV1(os: 'macos', arch: 'arm64')],
    reasonCode: 'H0_GATE_NOT_PASSED',
  );
}

final class MuseHelixRuntimeHealth {
  const MuseHelixRuntimeHealth({
    required this.binaryPresent,
    required this.digestMatches,
    required this.runtimePresent,
    required this.grammarReady,
    required this.ptyReady,
    required this.processTreeControl,
    required this.os,
    required this.arch,
    required this.runtimeDigest,
  });
  final bool binaryPresent,
      digestMatches,
      runtimePresent,
      grammarReady,
      ptyReady,
      processTreeControl;
  final String os, arch, runtimeDigest;
  bool get ready =>
      binaryPresent &&
      digestMatches &&
      runtimePresent &&
      grammarReady &&
      ptyReady &&
      processTreeControl;
}
