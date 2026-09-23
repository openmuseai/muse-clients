import 'package:muse_resource_contract/muse_resource_contract.dart';

enum MuseOfficeKind { word, excel, slides, pdf }

final class MuseOfficeAdmission {
  const MuseOfficeAdmission({
    required this.kind,
    required this.engineBound,
    required this.viewCertified,
    required this.editCertified,
    required this.exportCertified,
    required this.creatable,
    required this.reasonCode,
    required this.formats,
  });
  final MuseOfficeKind kind;
  final bool engineBound,
      viewCertified,
      editCertified,
      exportCertified,
      creatable;
  final String reasonCode;
  final Set<String> formats;
  bool get effectiveCreatable =>
      engineBound && creatable && (viewCertified || editCertified);
  Set<MuseEngineMode> get effectiveModes => {
    if (engineBound && viewCertified) MuseEngineMode.view,
    if (engineBound && editCertified && exportCertified) MuseEngineMode.edit,
  };
}

final class MuseOfficeAdmissionCatalog {
  MuseOfficeAdmissionCatalog(Iterable<MuseOfficeAdmission> values)
    : _byKind = {for (final value in values) value.kind: value};
  final Map<MuseOfficeKind, MuseOfficeAdmission> _byKind;
  MuseOfficeAdmission operator [](MuseOfficeKind kind) =>
      _byKind[kind] ?? (throw StateError('OFFICE_KIND_NOT_REGISTERED'));
  static MuseOfficeAdmissionCatalog current() =>
      MuseOfficeAdmissionCatalog(const [
        MuseOfficeAdmission(
          kind: MuseOfficeKind.word,
          engineBound: true,
          viewCertified: true,
          editCertified: false,
          exportCertified: false,
          creatable: true,
          reasonCode: 'WORD_VIEW_ONLY_NO_TODOCX',
          formats: {'ooxml.word'},
        ),
        MuseOfficeAdmission(
          kind: MuseOfficeKind.excel,
          engineBound: false,
          viewCertified: false,
          editCertified: false,
          exportCertified: false,
          creatable: false,
          reasonCode: 'ENGINE_NOT_IMPLEMENTED',
          formats: {'ooxml.spreadsheet'},
        ),
        MuseOfficeAdmission(
          kind: MuseOfficeKind.slides,
          engineBound: false,
          viewCertified: false,
          editCertified: false,
          exportCertified: false,
          creatable: false,
          reasonCode: 'ENGINE_NOT_IMPLEMENTED',
          formats: {'ooxml.presentation'},
        ),
        MuseOfficeAdmission(
          kind: MuseOfficeKind.pdf,
          engineBound: false,
          viewCertified: false,
          editCertified: false,
          exportCertified: false,
          creatable: false,
          reasonCode: 'ENGINE_NOT_IMPLEMENTED',
          formats: {'document.pdf'},
        ),
      ]);
}
