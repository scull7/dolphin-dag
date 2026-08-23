//! Named cargo tests for the workflow DAG class.

use dolphin_dag::{Error, Node, Status, Workflow};

fn task(id: &str, name: &str, task_type: &str) -> Node {
    Node {
        id: id.to_string(),
        name: name.to_string(),
        task_type: task_type.to_string(),
        status: Status::Pending,
    }
}

fn ids(workflow: &Workflow) -> Vec<String> {
    workflow
        .topological_order()
        .expect("valid dag")
        .into_iter()
        .map(|node| node.id.clone())
        .collect()
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

    assert_eq!(
        ids(&workflow),
        vec![
            String::from("extract"),
            String::from("transform"),
            String::from("load")
        ]
    );
}

#[test]
fn diamond_dag_topo_order() {
    let mut workflow = Workflow::new();
    for id in ["A", "B", "C", "D"] {
        workflow.add_node(task(id, id, "shell")).unwrap();
    }
    workflow.add_edge("A", "B").unwrap();
    workflow.add_edge("A", "C").unwrap();
    workflow.add_edge("B", "D").unwrap();
    workflow.add_edge("C", "D").unwrap();

    let order = ids(&workflow);
    let pos = |id: &str| order.iter().position(|item| item == id).expect(id);

    assert_eq!(order.len(), 4);
    assert!(pos("A") < pos("B"));
    assert!(pos("A") < pos("C"));
    assert!(pos("B") < pos("D"));
    assert!(pos("C") < pos("D"));
    assert_eq!(order, vec!["A", "B", "C", "D"]);
}

#[test]
fn cycle_rejected() {
    a_b_a_is_would_cycle();
}

#[test]
fn a_b_a_rejected() {
    a_b_a_is_would_cycle();
}

fn a_b_a_is_would_cycle() {
    let mut workflow = Workflow::new();
    workflow.add_node(task("A", "A", "shell")).unwrap();
    workflow.add_node(task("B", "B", "shell")).unwrap();
    workflow.add_edge("A", "B").unwrap();

    match workflow.add_edge("B", "A") {
        Err(Error::WouldCycle { from, to }) => {
            assert_eq!(from, "B");
            assert_eq!(to, "A");
        }
        other => panic!("expected typed WouldCycle, got {other:?}"),
    }
    assert_eq!(workflow.edges.len(), 1);
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
