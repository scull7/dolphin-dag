# dolphin-dag

DolphinScheduler-style DAG, written in Rust and Elm. First milestone: the DAG *class* plus a visual editor.

This is **not** a port of Apache [DolphinScheduler](https://dolphinscheduler.apache.org) and does not start from that Java codebase. There is no master/worker cluster, no Hadoop tenants, no task plugins, and no job runner. The inspiration is the workflow designer: tasks as nodes, dependencies as directed edges, cycles forbidden.

**Stack:** Rust domain crate · Elm editor · vanilla CSS. Melange is reserved for later shared browser-side domain; it is not used here. No TypeScript, no JavaScript UI, no Tailwind.

## Layout

```
crates/dolphin-dag/   Workflow DAG class: add_edge, WouldCycle, topo order
ui/                   Elm list + SVG editor (no canvas library)
```

## Rust tests

```bash
cargo test
```

Named tests in `crates/dolphin-dag/tests/dag.rs`:

| Test | What it checks |
|---|---|
| `empty_graph` | Empty workflow is a DAG with an empty topo order |
| `three_node_linear_dag_topo_order` | `extract → transform → load` |
| `diamond_dag_topo_order` | `A→B, A→C, B→D, C→D` is valid; order is `A, B, C, D` |
| `a_b_a_rejected` / `cycle_rejected` | `A→B` then `B→A` returns typed `Error::WouldCycle` |
| `serialize_deserialize_roundtrip` | serde JSON roundtrip keeps the document equal |

`Workflow::add_edge` returns `Result<(), Error>`. A loop is `Error::WouldCycle { from, to }`, not a panic or an untyped string. There is no worker / ready-set execution in this milestone.

## Elm editor

Requires [Elm 0.19.1](https://guide.elm-lang.org/install/elm.html).

```bash
cd ui
elm make src/Main.elm --output=/dev/null
elm reactor
```

Open `http://localhost:8000/src/Main.elm`. The editor loads `styles.css` from the `ui/` root.

The screen shows nodes, edges, and `topological_order : Result` (for example `Ok [ extract, transform, load ]`). A rejected edge is `Err (WouldCycle load -> extract)` on the banner — a typed `Result`, not `window.alert`.

Build a three-node DAG:

1. Add nodes `extract`, `transform`, `load`.
2. Click `extract` then `transform`, then `transform` then `load`.
3. Closing `load → extract` stays `WouldCycle`; the JSON still has two edges.

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

## License

MIT. See `LICENSE`.
