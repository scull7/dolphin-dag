//! Workflow DAG document shared with the Elm editor.
//!
//! This crate models nodes, directed edges, cycle-safe mutation, and
//! topological order. It is not a scheduler.

use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet, VecDeque};
use std::fmt;

/// Runtime status of a task node. Serialized as snake_case strings.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Status {
    Pending,
    Running,
    Success,
    Failure,
}

/// A workflow task vertex.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Node {
    pub id: String,
    pub name: String,
    pub task_type: String,
    pub status: Status,
}

/// A directed dependency: `from` must finish before `to` runs.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Edge {
    pub from: String,
    pub to: String,
}

/// A workflow document: nodes plus directed edges.
///
/// JSON shape (Elm and Rust share this):
///
/// ```json
/// {
///   "nodes": [
///     {"id": "extract", "name": "Extract", "task_type": "shell", "status": "pending"}
///   ],
///   "edges": [
///     {"from": "extract", "to": "transform"}
///   ]
/// }
/// ```
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct Workflow {
    pub nodes: Vec<Node>,
    pub edges: Vec<Edge>,
}

/// Why a mutation or topo sort failed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Error {
    EmptyNodeId,
    DuplicateNode { id: String },
    UnknownNode { id: String },
    DuplicateEdge { from: String, to: String },
    Cycle { from: String, to: String },
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::EmptyNodeId => write!(f, "node id must not be empty"),
            Error::DuplicateNode { id } => write!(f, "duplicate node id: {id}"),
            Error::UnknownNode { id } => write!(f, "unknown node id: {id}"),
            Error::DuplicateEdge { from, to } => {
                write!(f, "duplicate edge: {from} -> {to}")
            }
            Error::Cycle { from, to } => {
                write!(f, "edge {from} -> {to} would create a cycle")
            }
        }
    }
}

impl std::error::Error for Error {}

impl Workflow {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn add_node(&mut self, node: Node) -> Result<(), Error> {
        if node.id.is_empty() {
            return Err(Error::EmptyNodeId);
        }
        if self.nodes.iter().any(|existing| existing.id == node.id) {
            return Err(Error::DuplicateNode { id: node.id });
        }
        self.nodes.push(node);
        Ok(())
    }

    /// Adds a directed edge. Rejects unknown endpoints, duplicates, and cycles.
    pub fn add_edge(
        &mut self,
        from: impl Into<String>,
        to: impl Into<String>,
    ) -> Result<(), Error> {
        let from = from.into();
        let to = to.into();

        if !self.contains_node(&from) {
            return Err(Error::UnknownNode { id: from });
        }
        if !self.contains_node(&to) {
            return Err(Error::UnknownNode { id: to });
        }
        if self
            .edges
            .iter()
            .any(|edge| edge.from == from && edge.to == to)
        {
            return Err(Error::DuplicateEdge { from, to });
        }
        if from == to || self.reaches(&to, &from) {
            return Err(Error::Cycle { from, to });
        }

        self.edges.push(Edge { from, to });
        Ok(())
    }

    pub fn contains_node(&self, id: &str) -> bool {
        self.nodes.iter().any(|node| node.id == id)
    }

    /// True when a directed path exists from `start` to `goal`.
    pub fn reaches(&self, start: &str, goal: &str) -> bool {
        if start == goal {
            return true;
        }

        let mut seen = HashSet::new();
        let mut queue = VecDeque::from([start.to_string()]);

        while let Some(current) = queue.pop_front() {
            if !seen.insert(current.clone()) {
                continue;
            }
            for successor in self.successors(&current) {
                if successor == goal {
                    return true;
                }
                queue.push_back(successor.to_string());
            }
        }

        false
    }

    pub fn has_cycle(&self) -> bool {
        self.topological_order().is_err()
    }

    /// Kahn topological order. Ready nodes are dequeued in id order so the
    /// result is deterministic when several nodes have indegree zero.
    pub fn topological_order(&self) -> Result<Vec<&Node>, Error> {
        let index = self.node_index()?;
        let mut indegree: HashMap<&str, usize> = self
            .nodes
            .iter()
            .map(|node| (node.id.as_str(), 0))
            .collect();

        for edge in &self.edges {
            *indegree
                .get_mut(edge.to.as_str())
                .expect("validated endpoints") += 1;
        }

        let mut ready: Vec<&str> = indegree
            .iter()
            .filter_map(|(id, degree)| (*degree == 0).then_some(*id))
            .collect();
        ready.sort_unstable();

        let mut order = Vec::new();

        while !ready.is_empty() {
            let id = ready.remove(0);
            order.push(*index.get(id).expect("indexed node"));
            let mut unlocked = Vec::new();
            for successor in self.successors(id) {
                let degree = indegree.get_mut(successor).expect("validated endpoints");
                *degree -= 1;
                if *degree == 0 {
                    unlocked.push(successor);
                }
            }
            ready.extend(unlocked);
            ready.sort_unstable();
        }

        if order.len() != self.nodes.len() {
            return Err(Error::Cycle {
                from: String::from("?"),
                to: String::from("?"),
            });
        }

        Ok(order)
    }

    pub fn to_json(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string_pretty(self)
    }

    pub fn from_json(json: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(json)
    }

    fn successors(&self, id: &str) -> Vec<&str> {
        self.edges
            .iter()
            .filter(|edge| edge.from == id)
            .map(|edge| edge.to.as_str())
            .collect()
    }

    fn node_index(&self) -> Result<HashMap<&str, &Node>, Error> {
        let mut index = HashMap::new();
        for node in &self.nodes {
            if node.id.is_empty() {
                return Err(Error::EmptyNodeId);
            }
            if index.insert(node.id.as_str(), node).is_some() {
                return Err(Error::DuplicateNode {
                    id: node.id.clone(),
                });
            }
        }
        for edge in &self.edges {
            if !index.contains_key(edge.from.as_str()) {
                return Err(Error::UnknownNode {
                    id: edge.from.clone(),
                });
            }
            if !index.contains_key(edge.to.as_str()) {
                return Err(Error::UnknownNode {
                    id: edge.to.clone(),
                });
            }
        }
        Ok(index)
    }
}
