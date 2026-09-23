//! Minimal, deterministic Host/Plugin broker used to validate architecture.

use openmuse_plugin_protocol::{
    LifecycleState, Operation, PROTOCOL_VERSION, Permission, PluginId, PluginManifest,
    ProtocolError, RequestEnvelope, ResponseEnvelope, ResponseOutcome, ServiceContribution,
};
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};
use std::sync::Arc;

pub type Handler =
    Arc<dyn Fn(&PluginId, &str, Value) -> Result<Value, ProtocolError> + Send + Sync>;

#[derive(Clone)]
struct RegisteredCommand {
    owner: PluginId,
    permissions: BTreeSet<Permission>,
    handler: Handler,
}

#[derive(Clone)]
struct RegisteredService {
    owner: PluginId,
    contribution: ServiceContribution,
    handler: Handler,
}

struct Participant {
    manifest: PluginManifest,
    state: LifecycleState,
    grants: BTreeSet<Permission>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct PublishedEvent {
    pub sequence: u64,
    pub owner: PluginId,
    pub topic: String,
    pub payload: Value,
}

#[derive(Default)]
pub struct PlatformBroker {
    participants: BTreeMap<PluginId, Participant>,
    commands: BTreeMap<String, RegisteredCommand>,
    services: BTreeMap<String, Vec<RegisteredService>>,
    contexts: BTreeMap<(PluginId, String), Value>,
    subscriptions: BTreeMap<PluginId, BTreeSet<String>>,
    events: Vec<PublishedEvent>,
    next_event_sequence: u64,
}

impl PlatformBroker {
    pub fn register_plugin(
        &mut self,
        manifest: PluginManifest,
        grants: BTreeSet<Permission>,
    ) -> Result<(), ProtocolError> {
        if !PROTOCOL_VERSION.accepts(manifest.protocol) {
            return Err(ProtocolError::IncompatibleVersion {
                actual_major: manifest.protocol.major,
                actual_minor: manifest.protocol.minor,
            });
        }
        if self.participants.contains_key(&manifest.id) {
            return Err(ProtocolError::Conflict {
                resource: format!("plugin:{}", manifest.id),
            });
        }
        for permission in &manifest.permissions {
            if !grants.contains(permission) {
                return Err(ProtocolError::PermissionDenied {
                    permission: permission.0.clone(),
                });
            }
        }
        let id = manifest.id.clone();
        self.participants.insert(
            id,
            Participant {
                manifest,
                state: LifecycleState::Registered,
                grants,
            },
        );
        Ok(())
    }

    pub fn transition(
        &mut self,
        plugin: &PluginId,
        next: LifecycleState,
    ) -> Result<(), ProtocolError> {
        let participant =
            self.participants
                .get_mut(plugin)
                .ok_or_else(|| ProtocolError::NotFound {
                    resource: format!("plugin:{plugin}"),
                })?;
        let previous = participant.state;
        if !previous.can_transition_to(next) {
            return Err(ProtocolError::InvalidLifecycle {
                from: format!("{previous:?}"),
                to: format!("{next:?}"),
            });
        }
        participant.state = next;
        if matches!(next, LifecycleState::Deactivated | LifecycleState::Unloaded) {
            self.unregister_owned_resources(plugin);
        }
        Ok(())
    }

    pub fn register_command(
        &mut self,
        owner: &PluginId,
        command_id: impl Into<String>,
        permissions: BTreeSet<Permission>,
        handler: Handler,
    ) -> Result<(), ProtocolError> {
        self.require_active(owner)?;
        let command_id = command_id.into();
        if self.commands.contains_key(&command_id) {
            return Err(ProtocolError::Conflict {
                resource: format!("command:{command_id}"),
            });
        }
        self.commands.insert(
            command_id,
            RegisteredCommand {
                owner: owner.clone(),
                permissions,
                handler,
            },
        );
        Ok(())
    }

    pub fn register_service(
        &mut self,
        owner: &PluginId,
        contribution: ServiceContribution,
        handler: Handler,
    ) -> Result<(), ProtocolError> {
        self.require_active(owner)?;
        let providers = self.services.entry(contribution.id.clone()).or_default();
        if providers.iter().any(|entry| {
            entry.owner == *owner && entry.contribution.version == contribution.version
        }) {
            return Err(ProtocolError::Conflict {
                resource: format!(
                    "service:{}@{}:{owner}",
                    contribution.id, contribution.version
                ),
            });
        }
        providers.push(RegisteredService {
            owner: owner.clone(),
            contribution,
            handler,
        });
        providers.sort_by(|a, b| {
            b.contribution
                .priority
                .cmp(&a.contribution.priority)
                .then_with(|| a.owner.cmp(&b.owner))
        });
        Ok(())
    }

    pub fn subscribe(
        &mut self,
        owner: &PluginId,
        topic: impl Into<String>,
    ) -> Result<(), ProtocolError> {
        self.require_active(owner)?;
        self.subscriptions
            .entry(owner.clone())
            .or_default()
            .insert(topic.into());
        Ok(())
    }

    pub fn publish(
        &mut self,
        owner: &PluginId,
        topic: impl Into<String>,
        payload: Value,
    ) -> Result<u64, ProtocolError> {
        self.require_active(owner)?;
        let sequence = self.next_event_sequence;
        self.next_event_sequence += 1;
        self.events.push(PublishedEvent {
            sequence,
            owner: owner.clone(),
            topic: topic.into(),
            payload,
        });
        Ok(sequence)
    }

    pub fn events_for(&self, subscriber: &PluginId) -> Vec<&PublishedEvent> {
        let Some(topics) = self.subscriptions.get(subscriber) else {
            return Vec::new();
        };
        self.events
            .iter()
            .filter(|event| topics.contains(&event.topic))
            .collect()
    }

    pub fn handle(&mut self, now_ms: u64, request: RequestEnvelope) -> ResponseEnvelope {
        let outcome = self.handle_inner(now_ms, &request);
        ResponseEnvelope {
            protocol: PROTOCOL_VERSION,
            request_id: request.request_id,
            outcome: match outcome {
                Ok(value) => ResponseOutcome::Ok { value },
                Err(error) => ResponseOutcome::Error { error },
            },
        }
    }

    pub fn context(&self, owner: &PluginId, key: &str) -> Option<&Value> {
        self.contexts.get(&(owner.clone(), key.to_owned()))
    }

    pub fn command_count(&self) -> usize {
        self.commands.len()
    }

    pub fn service_provider_count(&self, service: &str) -> usize {
        self.services.get(service).map_or(0, Vec::len)
    }

    pub fn subscription_count(&self, owner: &PluginId) -> usize {
        self.subscriptions.get(owner).map_or(0, BTreeSet::len)
    }

    pub fn manifest(&self, plugin: &PluginId) -> Option<&PluginManifest> {
        self.participants.get(plugin).map(|p| &p.manifest)
    }

    fn handle_inner(
        &mut self,
        now_ms: u64,
        request: &RequestEnvelope,
    ) -> Result<Value, ProtocolError> {
        if !PROTOCOL_VERSION.accepts(request.protocol) {
            return Err(ProtocolError::IncompatibleVersion {
                actual_major: request.protocol.major,
                actual_minor: request.protocol.minor,
            });
        }
        if request
            .deadline_ms
            .is_some_and(|deadline| now_ms > deadline)
        {
            return Err(ProtocolError::DeadlineExceeded);
        }
        self.require_active(&request.caller)?;
        match &request.operation {
            Operation::ExecuteCommand { command, arguments } => {
                let registered =
                    self.commands
                        .get(command)
                        .cloned()
                        .ok_or_else(|| ProtocolError::NotFound {
                            resource: format!("command:{command}"),
                        })?;
                self.require_permissions(&request.caller, &registered.permissions)?;
                (registered.handler)(&request.caller, command, arguments.clone())
            }
            Operation::CallService {
                service,
                version,
                method,
                arguments,
            } => {
                let provider = self
                    .services
                    .get(service)
                    .and_then(|providers| {
                        providers
                            .iter()
                            .find(|provider| provider.contribution.version == *version)
                    })
                    .cloned()
                    .ok_or_else(|| ProtocolError::NotFound {
                        resource: format!("service:{service}@{version}"),
                    })?;
                self.require_permissions(
                    &request.caller,
                    &provider.contribution.required_permissions,
                )?;
                (provider.handler)(&request.caller, method, arguments.clone())
            }
            Operation::SetContext { key, value } => {
                if !is_owned_context_key(&request.caller, key) {
                    return Err(ProtocolError::InvalidRequest {
                        message: format!(
                            "plugin {} cannot write unowned context key {key}",
                            request.caller
                        ),
                    });
                }
                self.contexts
                    .insert((request.caller.clone(), key.clone()), value.clone());
                Ok(Value::Null)
            }
            Operation::Cancel { .. } => Err(ProtocolError::Cancelled),
        }
    }

    fn require_active(&self, plugin: &PluginId) -> Result<(), ProtocolError> {
        let participant = self
            .participants
            .get(plugin)
            .ok_or_else(|| ProtocolError::NotFound {
                resource: format!("plugin:{plugin}"),
            })?;
        if !matches!(
            participant.state,
            LifecycleState::Activated | LifecycleState::Active | LifecycleState::Background
        ) {
            return Err(ProtocolError::InvalidLifecycle {
                from: format!("{:?}", participant.state),
                to: "operation".into(),
            });
        }
        Ok(())
    }

    fn require_permissions(
        &self,
        caller: &PluginId,
        required: &BTreeSet<Permission>,
    ) -> Result<(), ProtocolError> {
        let participant = self
            .participants
            .get(caller)
            .ok_or_else(|| ProtocolError::NotFound {
                resource: format!("plugin:{caller}"),
            })?;
        for permission in required {
            if !participant.grants.contains(permission) {
                return Err(ProtocolError::PermissionDenied {
                    permission: permission.0.clone(),
                });
            }
        }
        Ok(())
    }

    fn unregister_owned_resources(&mut self, owner: &PluginId) {
        self.commands.retain(|_, value| &value.owner != owner);
        self.services.retain(|_, providers| {
            providers.retain(|value| &value.owner != owner);
            !providers.is_empty()
        });
        self.contexts.retain(|(plugin, _), _| plugin != owner);
        self.subscriptions.remove(owner);
    }
}

fn is_owned_context_key(owner: &PluginId, key: &str) -> bool {
    key.strip_prefix("plugin.")
        .and_then(|rest| rest.split_once('.'))
        .is_some_and(|(namespace, _)| namespace == owner.0)
}
