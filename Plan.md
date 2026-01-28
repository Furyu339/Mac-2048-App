# Plan

## Goal
- Keep existing app unchanged; build a new stack with Engine + UI (Strategy B).
- CPU + GPU are both busy on real 2048 evaluation, not idle load.
- Replicate current animation timing/feel.

## Milestones
1) IPC protocol + engine scaffold
2) CPU search baseline (multi-thread)
3) GPU batch evaluation integration (Metal)
4) UI animation replication
5) End-to-end integration and performance validation
