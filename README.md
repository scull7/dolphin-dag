# dolphin-dag

A DolphinScheduler-style **workflow DAG** in Rust and Elm. First milestone only: a real DAG document plus a visual editor.

This is **not** a port of Apache DolphinScheduler. There is no master/worker cluster, no Hadoop tenants, no task plugins, and no job runner. The product inspiration is the [DolphinScheduler](https://dolphinscheduler.apache.org) drag-and-drop workflow designer: tasks as nodes, dependencies as directed edges, cycles forbidden.

**Stack:** Rust domain crate · Elm editor · vanilla CSS. Melange is reserved for later shared browser-side domain; it is not used in this milestone.

## Layout

```
crates/dolphin-dag/   Rust workflow document, add_edge cycle check, topo order
ui/                   Elm canvas/list editor + styles.css
```

## Rust tests

Requires a current stable Rust toolchain.

```bash
cargo test
```

Named tests in `crates/dolphin-dag/tests/dag.rs`:

| Test | What it checks |
|---|---|
| `empty_graph` | Empty workflow is a DAG with an empty topo order |
| `three_node_linear_dag_topo_order` | `extract → transform → load` orders as those three ids |
| `cycle_rejected` | `add_edge` refuses an edge that would close a loop |
| `serialize_deserialize_roundtrip` | serde JSON roundtrip keeps the document equal |

## Elm editor

Requires [Elm 0.19.1](https://guide.elm-lang.org/install/elm.html). No JavaScript UI, no Tailwind.

```bash
cd ui
elm make src/Main.elm --output=/dev/null
elm reactor
```

Open `http://localhost:8000/src/Main.elm`. The editor loads `styles.css` from the `ui/` root (`/styles.css`).

Build a three-node DAG:

1. Add nodes `extract`, `transform`, `load` (task type is a free string, e.g. `shell`).
2. Click `extract`, then `transform`, then click `transform`, then `load`.
3. The canvas shows the chain and the topological order under the canvas.
4. Closing `load → extract` is rejected and the red cycle banner appears.
5. The right pane is the live JSON document. Edit it and click **Load JSON** to rehydrate the graph.

## JSON shape

Elm and Rust share one document. Field names are snake_case. `status` is one of `pending`, `running`, `success`, `failure`.

```json
{
  "nodes": [
    {
      "id": "extract",
      "name": "Extract logs",
      "task_type": "shell",
      "status": "pending"
    },
    {
      "id": "transform",
      "name": "Transform",
      "task_type": "python",
      "status": "pending"
    },
    {
      "id": "load",
      "name": "Load warehouse",
      "task_type": "sql",
      "status": "pending"
    }
  ],
  "edges": [
    { "from": "extract", "to": "transform" },
    { "from": "transform", "to": "load" }
  ]
}
```

`Workflow::add_edge` (Rust) and `Dag.addEdge` (Elm) both reject an edge that would create a cycle. Loading a hand-edited cyclic document still displays the nodes and shows the cycle error; topo order stays unavailable until an edge is removed.

## License

MIT. See `LICENSE`.
