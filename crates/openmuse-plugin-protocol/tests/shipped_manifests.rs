use openmuse_plugin_protocol::{PROTOCOL_VERSION, PluginManifest};

const HELIX: &str = include_str!("../../../plugins/helix/openmuse.plugin.json");
const VIEWER: &str = include_str!("../../../plugins/open-file-viewer/openmuse.plugin.json");
const DSH: &str = include_str!("../../../plugins/dsh-agent/openmuse.plugin.json");

#[test]
fn shipped_manifests_parse_and_target_the_current_protocol() {
    for raw in [HELIX, VIEWER, DSH] {
        let manifest: PluginManifest = serde_json::from_str(raw).unwrap();
        assert_eq!(manifest.protocol, PROTOCOL_VERSION);
        assert!(!manifest.id.0.is_empty());
        assert!(
            !manifest.contributes.editors.is_empty()
                || !manifest.contributes.panels.is_empty()
        );
    }
}

#[test]
fn dsh_is_a_right_sidebar_plugin_without_editor_ownership() {
    let manifest: PluginManifest = serde_json::from_str(DSH).unwrap();
    assert!(manifest.contributes.editors.is_empty());
    assert_eq!(manifest.contributes.panels[0].region, "right-sidebar");
}

#[test]
fn viewer_has_no_network_permission() {
    let manifest: PluginManifest = serde_json::from_str(VIEWER).unwrap();
    assert!(
        manifest
            .permissions
            .iter()
            .all(|permission| permission.0 != "network")
    );
}
