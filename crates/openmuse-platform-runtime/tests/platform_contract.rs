use openmuse_platform_runtime::{Handler, PlatformBroker};
use openmuse_plugin_protocol::{
    Contributions, LifecycleState, Operation, PROTOCOL_VERSION, Permission, PluginId,
    PluginManifest, ProtocolError, ProtocolVersion, RequestEnvelope, ResponseOutcome, RuntimeKind,
    ServiceContribution,
};
use serde_json::json;
use std::collections::BTreeSet;
use std::sync::Arc;

fn permissions(values: &[&str]) -> BTreeSet<Permission> {
    values.iter().map(|value| Permission::new(*value)).collect()
}

fn manifest(id: &str, requested_permissions: &[&str]) -> PluginManifest {
    PluginManifest {
        id: PluginId::new(id),
        name: id.into(),
        version: "0.1.0".into(),
        protocol: PROTOCOL_VERSION,
        runtime: RuntimeKind::BuiltIn,
        activation_events: vec!["onStartupFinished".into()],
        permissions: permissions(requested_permissions),
        contributes: Contributions::default(),
    }
}

fn activate(broker: &mut PlatformBroker, id: &PluginId) {
    broker.transition(id, LifecycleState::Activated).unwrap();
    broker.transition(id, LifecycleState::Active).unwrap();
}

fn echo_handler() -> Handler {
    Arc::new(|caller, method, args| Ok(json!({"caller": caller.0, "method": method, "args": args})))
}

#[test]
fn registration_rejects_ungranted_manifest_permission() {
    let mut broker = PlatformBroker::default();
    let result = broker.register_plugin(
        manifest("viewer", &["filesystem.workspace"]),
        BTreeSet::new(),
    );
    assert_eq!(
        result,
        Err(ProtocolError::PermissionDenied {
            permission: "filesystem.workspace".into()
        })
    );
}

#[test]
fn request_permissions_are_checked_at_call_time() {
    let mut broker = PlatformBroker::default();
    let host = PluginId::new("host");
    let viewer = PluginId::new("viewer");
    broker
        .register_plugin(manifest("host", &[]), BTreeSet::new())
        .unwrap();
    broker
        .register_plugin(manifest("viewer", &[]), BTreeSet::new())
        .unwrap();
    activate(&mut broker, &host);
    activate(&mut broker, &viewer);
    broker
        .register_service(
            &host,
            ServiceContribution {
                id: "filesystem.workspace".into(),
                version: 1,
                priority: 0,
                required_permissions: permissions(&["filesystem.workspace"]),
            },
            echo_handler(),
        )
        .unwrap();

    let response = broker.handle(
        10,
        RequestEnvelope {
            protocol: PROTOCOL_VERSION,
            request_id: 1,
            caller: viewer,
            deadline_ms: Some(20),
            operation: Operation::CallService {
                service: "filesystem.workspace".into(),
                version: 1,
                method: "read".into(),
                arguments: json!({"uri": "workspace:///cat.png"}),
            },
        },
    );
    assert!(matches!(
        response.outcome,
        ResponseOutcome::Error {
            error: ProtocolError::PermissionDenied { .. }
        }
    ));
}

#[test]
fn service_provider_selection_is_priority_then_stable_id() {
    let mut broker = PlatformBroker::default();
    for id in ["provider.z", "provider.a", "caller"] {
        broker
            .register_plugin(manifest(id, &[]), BTreeSet::new())
            .unwrap();
        activate(&mut broker, &PluginId::new(id));
    }
    for (id, priority) in [("provider.z", 5), ("provider.a", 5)] {
        let provider_id = id.to_string();
        broker
            .register_service(
                &PluginId::new(id),
                ServiceContribution {
                    id: "document.preview".into(),
                    version: 1,
                    priority,
                    required_permissions: BTreeSet::new(),
                },
                Arc::new(move |_, _, _| Ok(json!({"provider": provider_id}))),
            )
            .unwrap();
    }

    let response = broker.handle(
        10,
        RequestEnvelope {
            protocol: PROTOCOL_VERSION,
            request_id: 2,
            caller: PluginId::new("caller"),
            deadline_ms: Some(20),
            operation: Operation::CallService {
                service: "document.preview".into(),
                version: 1,
                method: "open".into(),
                arguments: Value::Null,
            },
        },
    );
    assert_eq!(
        response.outcome,
        ResponseOutcome::Ok {
            value: json!({"provider": "provider.a"})
        }
    );
}

#[test]
fn duplicate_command_ids_fail_instead_of_becoming_order_dependent() {
    let mut broker = PlatformBroker::default();
    for id in ["a", "b"] {
        broker
            .register_plugin(manifest(id, &[]), BTreeSet::new())
            .unwrap();
        activate(&mut broker, &PluginId::new(id));
    }
    broker
        .register_command(
            &PluginId::new("a"),
            "document.save",
            BTreeSet::new(),
            echo_handler(),
        )
        .unwrap();
    let result = broker.register_command(
        &PluginId::new("b"),
        "document.save",
        BTreeSet::new(),
        echo_handler(),
    );
    assert_eq!(
        result,
        Err(ProtocolError::Conflict {
            resource: "command:document.save".into()
        })
    );
}

#[test]
fn deactivation_releases_commands_services_context_and_subscriptions() {
    let mut broker = PlatformBroker::default();
    let plugin = PluginId::new("viewer");
    broker
        .register_plugin(manifest("viewer", &[]), BTreeSet::new())
        .unwrap();
    activate(&mut broker, &plugin);
    broker
        .register_command(&plugin, "viewer.open", BTreeSet::new(), echo_handler())
        .unwrap();
    broker
        .register_service(
            &plugin,
            ServiceContribution {
                id: "document.preview".into(),
                version: 1,
                priority: 0,
                required_permissions: BTreeSet::new(),
            },
            echo_handler(),
        )
        .unwrap();
    broker.subscribe(&plugin, "theme.changed").unwrap();
    let response = broker.handle(
        0,
        RequestEnvelope {
            protocol: PROTOCOL_VERSION,
            request_id: 3,
            caller: plugin.clone(),
            deadline_ms: Some(10),
            operation: Operation::SetContext {
                key: "plugin.viewer.ready".into(),
                value: json!(true),
            },
        },
    );
    assert!(matches!(response.outcome, ResponseOutcome::Ok { .. }));

    broker
        .transition(&plugin, LifecycleState::Deactivated)
        .unwrap();
    assert_eq!(broker.command_count(), 0);
    assert_eq!(broker.service_provider_count("document.preview"), 0);
    assert_eq!(broker.subscription_count(&plugin), 0);
    assert!(broker.context(&plugin, "plugin.viewer.ready").is_none());
}

#[test]
fn plugin_cannot_spoof_another_plugins_context_namespace() {
    let mut broker = PlatformBroker::default();
    let plugin = PluginId::new("viewer");
    broker
        .register_plugin(manifest("viewer", &[]), BTreeSet::new())
        .unwrap();
    activate(&mut broker, &plugin);
    let response = broker.handle(
        0,
        RequestEnvelope {
            protocol: PROTOCOL_VERSION,
            request_id: 4,
            caller: plugin,
            deadline_ms: Some(10),
            operation: Operation::SetContext {
                key: "plugin.helix.ready".into(),
                value: json!(true),
            },
        },
    );
    assert!(matches!(
        response.outcome,
        ResponseOutcome::Error {
            error: ProtocolError::InvalidRequest { .. }
        }
    ));
}

#[test]
fn incompatible_protocol_and_expired_deadline_fail_closed() {
    let mut broker = PlatformBroker::default();
    let plugin = PluginId::new("viewer");
    broker
        .register_plugin(manifest("viewer", &[]), BTreeSet::new())
        .unwrap();
    activate(&mut broker, &plugin);

    let incompatible = broker.handle(
        5,
        RequestEnvelope {
            protocol: ProtocolVersion { major: 2, minor: 0 },
            request_id: 5,
            caller: plugin.clone(),
            deadline_ms: Some(10),
            operation: Operation::Cancel { request_id: 1 },
        },
    );
    assert!(matches!(
        incompatible.outcome,
        ResponseOutcome::Error {
            error: ProtocolError::IncompatibleVersion { .. }
        }
    ));

    let expired = broker.handle(
        11,
        RequestEnvelope {
            protocol: PROTOCOL_VERSION,
            request_id: 6,
            caller: plugin,
            deadline_ms: Some(10),
            operation: Operation::Cancel { request_id: 1 },
        },
    );
    assert_eq!(
        expired.outcome,
        ResponseOutcome::Error {
            error: ProtocolError::DeadlineExceeded
        }
    );
}

#[test]
fn event_sequence_is_monotonic_and_subscription_is_owner_bound() {
    let mut broker = PlatformBroker::default();
    for id in ["host", "viewer"] {
        broker
            .register_plugin(manifest(id, &[]), BTreeSet::new())
            .unwrap();
        activate(&mut broker, &PluginId::new(id));
    }
    let host = PluginId::new("host");
    let viewer = PluginId::new("viewer");
    broker.subscribe(&viewer, "theme.changed").unwrap();
    assert_eq!(
        broker
            .publish(&host, "theme.changed", json!({"dark": true}))
            .unwrap(),
        0
    );
    assert_eq!(
        broker
            .publish(&host, "theme.changed", json!({"dark": false}))
            .unwrap(),
        1
    );
    let events = broker.events_for(&viewer);
    assert_eq!(events.len(), 2);
    assert_eq!(events[0].sequence, 0);
    assert_eq!(events[1].sequence, 1);
}

use serde_json::Value;
