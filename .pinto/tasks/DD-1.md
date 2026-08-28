+++
id = "DD-1"
title = "DAG core + Elm editor with a first-run cycle walkthrough"
status = "review"
rank = "i"
labels = ["milestone"]
start_at = "2026-08-28T17:57:55.138036189Z"
commits = ["05b55c78e74aea863e2980da1ad57bcb3264f56d"]
created = "2026-08-28T17:57:55.129831176Z"
updated = "2026-08-28T17:57:55.142114349Z"
+++

Open pull request: https://github.com/scull7/dolphin-dag/pull/1

First milestone for dolphin-dag: a Rust workflow DAG and an Elm SVG editor. Live at https://dolphin-dag.netlify.app.

This is a DolphinScheduler-style DAG, not a port of the Java scheduler.

Confirmed scope from PR #1:
- Rust `Workflow::add_edge` returns `Result<(), Error>`. A loop is `Error::WouldCycle { from, to }`.
- Elm editor shares the same JSON document.
- Beat 0 of the first-run guide is a centered Elm popover. Later beats still use the old strip until DD-2 / DD-3.

Do not implement this card on the Pinto board branch. Implementation lives on PR #1 (`cursor/dag-core-editor-de78`).
