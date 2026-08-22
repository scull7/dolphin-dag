//! Named cargo tests for the workflow DAG document.

use dolphin_dag::{Error, Node, Status, Workflow};

fn task(id: &str, name: &str, task_type: &str) -> Node {
    Node {
        id: id.to_string(),
        name: name.to_string(),
        task_type: task_type.to_string(),
        status: Status::Pending,
    }
}

#[test]
fn empty_graph() {
    let workflow = Workflow::new();
    assert_eq!(workflow.nodes.len(), 0);
    assert_eq!(workflow.edges.len(), 0);
    let order = workflow.topological_order().expect("empty graph is a dag");
    assert!(order.is_empty());
}

#[test]
fn three_node_linear_dag_topo_order() {
    let mut workflow = Workflow::new();
    workflow
        .add_node(task("extract", "Extract", "shell"))
        .unwrap();
    workflow
        .add_node(task("transform", "Transform", "python"))
        .unwrap();
    workflow.add_node(task("load", "Load", "sql")).unwrap();
    workflow.add_edge("extract", "transform").unwrap();
    workflow.add_edge("transform", "load").unwrap();

    let ids: Vec<String> = workflow
        .topological_order()
        .expect("linear")
        .into_iter()
        .map(|node| node.id.clone())
        .collect();

    assert_eq!(
        ids,
        vec![
            String::from("extract"),
            String::from("transform"),
            String::from("load")
        ]
    );
}

#[test]
fn cycle_rejected() {
    let mut workflow = Workflow::new();
    workflow.add_node(task("left", "Left", "shell")).unwrap();
    workflow.add_node(task("right", "Right", "shell")).unwrap();
    workflow.add_edge("left", "right").unwrap();

    match workflow.add_edge("right", "left") {
        Err(Error::Cycle { from, to }) => {
            assert_eq!(from, "right");
            assert_eq!(to, "left");
        }
        other => panic!("expected cycle, got {other:?}"),
    }
}

#[test]
fn serialize_deserialize_roundtrip() {
    let mut workflow = Workflow::new();
    workflow
        .add_node(Node {
            id: String::from("n1"),
            name: String::from("One"),
            task_type: String::from("shell"),
            status: Status::Success,
        })
        .unwrap();
    workflow
        .add_node(Node {
            id: String::from("n2"),
            name: String::from("Two"),
            task_type: String::from("sql"),
            status: Status::Failure,
        })
        .unwrap();
    workflow.add_edge("n1", "n2").unwrap();

    let encoded = serde_json::to_string(&workflow).expect("encode");
    let decoded: Workflow = serde_json::from_str(&encoded).expect("decode");
    assert_eq!(workflow, decoded);
}
