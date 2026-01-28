# 2048 B Project (Engine + UI)

This project is a fresh implementation of the 2048 stack using Strategy B:
- Engine owns rules, search, and GPU batch evaluation
- UI only renders animations and forwards input
- IPC bridges UI <-> Engine

Directories:
- engine/   Rust engine (search + GPU eval stubs)
- ui/       SwiftUI frontend (display + input, minimal logic)
- protocol/ IPC message definitions
- docs/     animation replication notes
