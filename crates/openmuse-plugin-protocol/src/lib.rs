//! Transport-neutral contracts shared by the host and plugin SDKs.
//!
//! The types in this crate intentionally avoid Rust trait objects, pointers,
//! native view handles, and renderer-specific values. They are suitable for
//! JSON today and a binary IPC encoding later without changing semantics.

use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeSet;
use std::fmt::{Display, Formatter};

pub const PROTOCOL_VERSION: ProtocolVersion = ProtocolVersion { major: 1, minor: 0 };

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProtocolVersion {
    pub major: u16,
    pub minor: u16,
}

impl ProtocolVersion {
    pub fn accepts(self, peer: Self) -> bool {
        self.major == peer.major && peer.minor <= self.minor
    }
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct PluginId(pub String);

impl PluginId {
    pub fn new(value: impl Into<String>) -> Self {
        Self(value.into())
    }
}

impl Display for PluginId {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        self.0.fmt(f)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct Permission(pub String);

impl Permission {
    pub fn new(value: impl Into<String>) -> Self {
        Self(value.into())
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum RuntimeKind {
    BuiltIn,
    NativeProcess,
    WebView,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PluginManifest {
    pub id: PluginId,
    pub name: String,
    pub version: String,
    pub protocol: ProtocolVersion,
    pub runtime: RuntimeKind,
    #[serde(default)]
    pub activation_events: Vec<String>,
    #[serde(default)]
    pub permissions: BTreeSet<Permission>,
    #[serde(default)]
    pub contributes: Contributions,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Contributions {
    #[serde(default)]
    pub commands: Vec<CommandContribution>,
    #[serde(default)]
    pub services: Vec<ServiceContribution>,
    #[serde(default)]
    pub editors: Vec<EditorContribution>,
    #[serde(default)]
    pub panels: Vec<PanelContribution>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CommandContribution {
    pub id: String,
    pub title: String,
    #[serde(default)]
    pub required_permissions: BTreeSet<Permission>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ServiceContribution {
    pub id: String,
    pub version: u16,
    #[serde(default)]
    pub priority: i32,
    #[serde(default)]
    pub required_permissions: BTreeSet<Permission>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EditorContribution {
    pub id: String,
    pub extensions: Vec<String>,
    #[serde(default)]
    pub priority: i32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PanelContribution {
    pub id: String,
    pub region: String,
    #[serde(default)]
    pub priority: i32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RequestEnvelope {
    pub protocol: ProtocolVersion,
    pub request_id: u64,
    pub caller: PluginId,
    /// Absolute monotonic deadline supplied by the transport. A missing value
    /// means the host policy supplies the deadline; it never means infinity.
    pub deadline_ms: Option<u64>,
    pub operation: Operation,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Operation {
    ExecuteCommand {
        command: String,
        #[serde(default)]
        arguments: Value,
    },
    CallService {
        service: String,
        version: u16,
        method: String,
        #[serde(default)]
        arguments: Value,
    },
    SetContext {
        key: String,
        value: Value,
    },
    Cancel {
        request_id: u64,
    },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ResponseEnvelope {
    pub protocol: ProtocolVersion,
    pub request_id: u64,
    #[serde(flatten)]
    pub outcome: ResponseOutcome,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "status", rename_all = "snake_case")]
pub enum ResponseOutcome {
    Ok { value: Value },
    Error { error: ProtocolError },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, thiserror::Error)]
#[serde(tag = "code", content = "details", rename_all = "snake_case")]
pub enum ProtocolError {
    #[error("incompatible protocol version {actual_major}.{actual_minor}")]
    IncompatibleVersion {
        actual_major: u16,
        actual_minor: u16,
    },
    #[error("permission denied: {permission}")]
    PermissionDenied { permission: String },
    #[error("not found: {resource}")]
    NotFound { resource: String },
    #[error("conflict: {resource}")]
    Conflict { resource: String },
    #[error("invalid lifecycle transition: {from} -> {to}")]
    InvalidLifecycle { from: String, to: String },
    #[error("request deadline exceeded")]
    DeadlineExceeded,
    #[error("request was cancelled")]
    Cancelled,
    #[error("invalid request: {message}")]
    InvalidRequest { message: String },
    #[error("provider failed: {message}")]
    ProviderFailed { message: String },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LifecycleState {
    Installed,
    Registered,
    Activated,
    Active,
    Background,
    Suspended,
    Deactivated,
    Unloaded,
}

impl LifecycleState {
    pub fn can_transition_to(self, next: Self) -> bool {
        use LifecycleState::*;
        matches!(
            (self, next),
            (Installed, Registered)
                | (Registered, Activated)
                | (Activated, Active)
                | (Active, Background)
                | (Background, Active)
                | (Background, Suspended)
                | (Suspended, Active)
                | (Suspended, Deactivated)
                | (Background, Deactivated)
                | (Active, Deactivated)
                | (Activated, Deactivated)
                | (Deactivated, Activated)
                | (Deactivated, Unloaded)
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn request_is_json_round_trip_safe() {
        let request = RequestEnvelope {
            protocol: PROTOCOL_VERSION,
            request_id: 7,
            caller: PluginId::new("com.openmuse.viewer"),
            deadline_ms: Some(1_000),
            operation: Operation::CallService {
                service: "filesystem.workspace".into(),
                version: 1,
                method: "read".into(),
                arguments: json!({"uri": "workspace:///image.png"}),
            },
        };

        let encoded = serde_json::to_vec(&request).unwrap();
        let decoded: RequestEnvelope = serde_json::from_slice(&encoded).unwrap();
        assert_eq!(decoded, request);
    }

    #[test]
    fn version_negotiation_allows_older_minor_only() {
        let host = ProtocolVersion { major: 1, minor: 3 };
        assert!(host.accepts(ProtocolVersion { major: 1, minor: 2 }));
        assert!(!host.accepts(ProtocolVersion { major: 1, minor: 4 }));
        assert!(!host.accepts(ProtocolVersion { major: 2, minor: 0 }));
    }
}
