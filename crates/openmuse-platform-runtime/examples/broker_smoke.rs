use openmuse_platform_runtime::PlatformBroker;
use openmuse_plugin_protocol::{
    Contributions, LifecycleState, Operation, PROTOCOL_VERSION, PluginId, PluginManifest,
    RequestEnvelope, ResponseOutcome, RuntimeKind,
};
use serde_json::Value;
use std::collections::BTreeSet;
use std::sync::Arc;
use std::time::Instant;

fn main() {
    let mut broker = PlatformBroker::default();
    let plugin = PluginId::new("com.openmuse.broker-smoke");
    broker
        .register_plugin(
            PluginManifest {
                id: plugin.clone(),
                name: "Broker smoke".into(),
                version: "0.1.0".into(),
                protocol: PROTOCOL_VERSION,
                runtime: RuntimeKind::BuiltIn,
                activation_events: vec![],
                permissions: BTreeSet::new(),
                contributes: Contributions::default(),
            },
            BTreeSet::new(),
        )
        .unwrap();
    broker
        .transition(&plugin, LifecycleState::Activated)
        .unwrap();
    broker
        .register_command(
            &plugin,
            "smoke.noop",
            BTreeSet::new(),
            Arc::new(|_, _, _| Ok(Value::Null)),
        )
        .unwrap();

    const ITERATIONS: u64 = 100_000;
    let started = Instant::now();
    for request_id in 0..ITERATIONS {
        let response = broker.handle(
            0,
            RequestEnvelope {
                protocol: PROTOCOL_VERSION,
                request_id,
                caller: plugin.clone(),
                deadline_ms: Some(1),
                operation: Operation::ExecuteCommand {
                    command: "smoke.noop".into(),
                    arguments: Value::Null,
                },
            },
        );
        assert!(matches!(response.outcome, ResponseOutcome::Ok { .. }));
    }
    let elapsed = started.elapsed();
    let average_ns = elapsed.as_nanos() / u128::from(ITERATIONS);
    println!("{ITERATIONS} in-process dispatches in {elapsed:?}; average {average_ns} ns/dispatch");

    // This is intentionally a broad regression guard, not a product benchmark.
    assert!(average_ns < 1_000_000, "average dispatch exceeded 1 ms");
}
