# IPC Protocol (draft)

## Request: Evaluate
{
  "type": "evaluate",
  "board": [16 ints],
  "score": 1234,
  "depth": 9,
  "time_limit_ms": 2000
}

## Response: BestMove
{
  "type": "best_move",
  "direction": "up|down|left|right",
  "value": 123.45,
  "metrics": {
    "nodes": 123456,
    "cache_hits": 45678,
    "deadline_hits": 12,
    "elapsed_ms": 1987
  }
}

## Response: MoveTrace (for UI animation)
{
  "type": "move_trace",
  "previous_board": [16 ints],
  "final_board": [16 ints],
  "movements": [
    {"from": 0, "to": 1, "value": 2, "merge": false}
  ],
  "merged_indices": [3, 7],
  "spawned_index": 5
}
