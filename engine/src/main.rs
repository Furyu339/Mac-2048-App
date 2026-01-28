use dashmap::DashMap;
use rand::seq::SliceRandom;
use rand::Rng;
use rayon::prelude::*;
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::io::{self, BufRead, Write};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

const SIZE: usize = 4;
const BOARD_COUNT: usize = SIZE * SIZE;
const BASE_MOVE_DURATION_MS: u64 = 220;
const BASE_MERGE_DURATION_MS: u64 = 140;

#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
enum Direction {
    Up,
    Down,
    Left,
    Right,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct Movement {
    from: usize,
    to: usize,
    value: i32,
    is_merge: bool,
}

#[derive(Clone, Debug)]
struct MoveOutcome {
    board: [i32; BOARD_COUNT],
    score: i32,
    merged_indices: HashSet<usize>,
    movements: Vec<Movement>,
    changed: bool,
}

#[derive(Deserialize)]
#[serde(tag = "type")]
enum Request {
    #[serde(rename = "reset")]
    Reset { id: u64 },
    #[serde(rename = "hint")]
    Hint { id: u64, board: Vec<i32>, score: i32, time_limit_ms: u64, max_depth: i32 },
    #[serde(rename = "move")]
    Move { id: u64, direction: Direction },
    #[serde(rename = "auto")]
    Auto { id: u64, time_limit_ms: u64, max_depth: i32 },
}

#[derive(Serialize)]
#[serde(tag = "type")]
enum Response {
    #[serde(rename = "state")]
    State {
        id: u64,
        board: Vec<i32>,
        score: i32,
        best_score: i32,
        is_game_over: bool,
    },
    #[serde(rename = "hint")]
    Hint {
        id: u64,
        direction: Option<Direction>,
        value: f64,
        metrics: Metrics,
    },
    #[serde(rename = "move_result")]
    MoveResult {
        id: u64,
        previous_board: Vec<i32>,
        final_board: Vec<i32>,
        movements: Vec<Movement>,
        merged_indices: Vec<usize>,
        spawned_index: Option<usize>,
        score: i32,
        best_score: i32,
        is_game_over: bool,
        move_duration_ms: u64,
        merge_duration_ms: u64,
    },
}

#[derive(Serialize, Default, Clone)]
struct Metrics {
    nodes: u64,
    cache_hits: u64,
    deadline_hits: u64,
    elapsed_ms: u64,
}

struct Engine {
    board: [i32; BOARD_COUNT],
    score: i32,
    best_score: i32,
}

impl Engine {
    fn new() -> Self {
        let mut engine = Self {
            board: [0; BOARD_COUNT],
            score: 0,
            best_score: 0,
        };
        engine.reset();
        engine
    }

    fn reset(&mut self) {
        self.board = [0; BOARD_COUNT];
        self.score = 0;
        add_random_tile(&mut self.board);
        add_random_tile(&mut self.board);
    }

    fn is_game_over(&self) -> bool {
        !can_move(&self.board)
    }

    fn state_response(&self, id: u64) -> Response {
        Response::State {
            id,
            board: self.board.to_vec(),
            score: self.score,
            best_score: self.best_score,
            is_game_over: self.is_game_over(),
        }
    }

    fn apply_move(&mut self, direction: Direction) -> Option<Response> {
        let outcome = move_board(&self.board, direction);
        if !outcome.changed {
            return None;
        }
        let previous = self.board;
        let mut new_board = outcome.board;
        self.score += outcome.score;
        let spawned_index = add_random_tile(&mut new_board);
        self.board = new_board;
        if self.score > self.best_score {
            self.best_score = self.score;
        }
        let merged_indices: Vec<usize> = outcome.merged_indices.iter().copied().collect();
        Some(Response::MoveResult {
            id: 0,
            previous_board: previous.to_vec(),
            final_board: self.board.to_vec(),
            movements: outcome.movements,
            merged_indices,
            spawned_index,
            score: self.score,
            best_score: self.best_score,
            is_game_over: self.is_game_over(),
            move_duration_ms: BASE_MOVE_DURATION_MS,
            merge_duration_ms: BASE_MERGE_DURATION_MS,
        })
    }
}

fn main() {
    let stdin = io::stdin();
    let mut stdout = io::stdout();
    let mut engine = Engine::new();

    for line in stdin.lock().lines() {
        let line = match line { Ok(v) => v, Err(_) => continue };
        if line.trim().is_empty() { continue; }
        let req: Request = match serde_json::from_str(&line) {
            Ok(v) => v,
            Err(_) => continue,
        };

        let resp = match req {
            Request::Reset { id } => {
                engine.reset();
                engine.state_response(id)
            }
            Request::Hint { id, board, score, time_limit_ms, max_depth } => {
                let (dir, value, metrics) = best_move_with_metrics(&board, score, time_limit_ms, max_depth);
                Response::Hint { id, direction: dir, value, metrics }
            }
            Request::Move { id, direction } => {
                if let Some(mut resp) = engine.apply_move(direction) {
                    if let Response::MoveResult { id: ref mut rid, .. } = resp {
                        *rid = id;
                    }
                    resp
                } else {
                    engine.state_response(id)
                }
            }
            Request::Auto { id, time_limit_ms, max_depth } => {
                let (dir, _, _) = best_move_with_metrics(&engine.board.to_vec(), engine.score, time_limit_ms, max_depth);
                if let Some(dir) = dir {
                    if let Some(mut resp) = engine.apply_move(dir) {
                        if let Response::MoveResult { id: ref mut rid, .. } = resp {
                            *rid = id;
                        }
                        resp
                    } else {
                        engine.state_response(id)
                    }
                } else {
                    engine.state_response(id)
                }
            }
        };

        let json = serde_json::to_string(&resp).unwrap();
        let _ = writeln!(stdout, "{json}");
        let _ = stdout.flush();
    }
}

fn best_move_with_metrics(board: &Vec<i32>, score: i32, time_limit_ms: u64, max_depth: i32) -> (Option<Direction>, f64, Metrics) {
    let start = Instant::now();
    let deadline = start + Duration::from_millis(time_limit_ms);
    let cache = Arc::new(DashMap::<u64, f64>::with_capacity(200_000));
    let nodes = Arc::new(AtomicU64::new(0));
    let cache_hits = Arc::new(AtomicU64::new(0));
    let deadline_hits = Arc::new(AtomicU64::new(0));

    let candidates: Vec<(Direction, MoveOutcome)> = [Direction::Up, Direction::Down, Direction::Left, Direction::Right]
        .iter()
        .filter_map(|&dir| {
            let outcome = move_board(&to_array(board), dir);
            if outcome.changed { Some((dir, outcome)) } else { None }
        })
        .collect();

    if candidates.is_empty() {
        let metrics = Metrics {
            nodes: nodes.load(Ordering::Relaxed),
            cache_hits: cache_hits.load(Ordering::Relaxed),
            deadline_hits: deadline_hits.load(Ordering::Relaxed),
            elapsed_ms: start.elapsed().as_millis() as u64,
        };
        return (None, 0.0, metrics);
    }

    let results: Vec<(Direction, f64)> = candidates
        .par_iter()
        .map(|(dir, outcome)| {
            let v = expectimax(
                &outcome.board,
                score + outcome.score,
                max_depth - 1,
                false,
                deadline,
                &cache,
                &nodes,
                &cache_hits,
                &deadline_hits,
            );
            (*dir, v)
        })
        .collect();

    let mut best = results[0];
    for r in results.into_iter().skip(1) {
        if r.1 > best.1 { best = r; }
    }

    let metrics = Metrics {
        nodes: nodes.load(Ordering::Relaxed),
        cache_hits: cache_hits.load(Ordering::Relaxed),
        deadline_hits: deadline_hits.load(Ordering::Relaxed),
        elapsed_ms: start.elapsed().as_millis() as u64,
    };

    (Some(best.0), best.1, metrics)
}

fn expectimax(
    board: &[i32; BOARD_COUNT],
    score: i32,
    depth: i32,
    is_player: bool,
    deadline: Instant,
    cache: &DashMap<u64, f64>,
    nodes: &AtomicU64,
    cache_hits: &AtomicU64,
    deadline_hits: &AtomicU64,
) -> f64 {
    nodes.fetch_add(1, Ordering::Relaxed);
    if Instant::now() > deadline {
        deadline_hits.fetch_add(1, Ordering::Relaxed);
        return evaluate(board, score);
    }
    if depth == 0 || !can_move(board) {
        return evaluate(board, score);
    }

    let key = board_hash(board, depth, is_player);
    if let Some(v) = cache.get(&key) {
        cache_hits.fetch_add(1, Ordering::Relaxed);
        return *v;
    }

    let value = if is_player {
        let mut best = f64::NEG_INFINITY;
        for dir in [Direction::Up, Direction::Down, Direction::Left, Direction::Right] {
            let outcome = move_board(board, dir);
            if !outcome.changed { continue; }
            let v = expectimax(&outcome.board, score + outcome.score, depth - 1, false, deadline, cache, nodes, cache_hits, deadline_hits);
            if v > best { best = v; }
        }
        if best == f64::NEG_INFINITY { evaluate(board, score) } else { best }
    } else {
        let empties = empty_indices(board);
        if empties.is_empty() {
            evaluate(board, score)
        } else {
            let prob2 = 0.9 / empties.len() as f64;
            let prob4 = 0.1 / empties.len() as f64;
            if depth > 1 && empties.len() >= 6 {
                let total: f64 = empties.par_iter().map(|&idx| {
                    let mut b2 = *board;
                    b2[idx] = 2;
                    let mut b4 = *board;
                    b4[idx] = 4;
                    let v2 = expectimax(&b2, score, depth - 1, true, deadline, cache, nodes, cache_hits, deadline_hits);
                    let v4 = expectimax(&b4, score, depth - 1, true, deadline, cache, nodes, cache_hits, deadline_hits);
                    prob2 * v2 + prob4 * v4
                }).sum();
                total
            } else {
                let mut total = 0.0;
                for idx in empties {
                    let mut b2 = *board;
                    b2[idx] = 2;
                    let mut b4 = *board;
                    b4[idx] = 4;
                    let v2 = expectimax(&b2, score, depth - 1, true, deadline, cache, nodes, cache_hits, deadline_hits);
                    let v4 = expectimax(&b4, score, depth - 1, true, deadline, cache, nodes, cache_hits, deadline_hits);
                    total += prob2 * v2 + prob4 * v4;
                }
                total
            }
        }
    };

    if cache.len() > 200_000 { cache.clear(); }
    cache.insert(key, value);
    value
}

fn evaluate(board: &[i32; BOARD_COUNT], score: i32) -> f64 {
    let empty = empty_indices(board).len() as f64;
    let smooth = smoothness(board);
    let mono = monotonicity(board);
    let max_tile = *board.iter().max().unwrap_or(&0) as f64;
    let corner = corner_max_score(board);
    let stability = stability_penalty(board);
    empty * 130.0 + smooth * 2.5 + mono * 18.0 + (max_tile + 1.0).log2() * 22.0 + corner * 45.0 - stability * 8.0 + score as f64 * 0.08
}

fn smoothness(board: &[i32; BOARD_COUNT]) -> f64 {
    let mut penalty = 0.0;
    for r in 0..SIZE {
        for c in 0..SIZE {
            let idx = r * SIZE + c;
            let v = board[idx];
            if v == 0 { continue; }
            let logv = (v as f64).log2();
            if c + 1 < SIZE {
                let nv = board[idx + 1];
                if nv > 0 { penalty -= (logv - (nv as f64).log2()).abs(); }
            }
            if r + 1 < SIZE {
                let nv = board[idx + SIZE];
                if nv > 0 { penalty -= (logv - (nv as f64).log2()).abs(); }
            }
        }
    }
    penalty
}

fn monotonicity(board: &[i32; BOARD_COUNT]) -> f64 {
    let mut totals = [0.0, 0.0, 0.0, 0.0];
    for r in 0..SIZE {
        let mut current = 0;
        let mut next = 1;
        while next < SIZE {
            let cur_val = board[r * SIZE + current];
            let next_val = board[r * SIZE + next];
            if cur_val > next_val {
                totals[0] += ((cur_val + 1) as f64).log2() - ((next_val + 1) as f64).log2();
            } else if next_val > cur_val {
                totals[1] += ((next_val + 1) as f64).log2() - ((cur_val + 1) as f64).log2();
            }
            current = next;
            next += 1;
        }
    }
    for c in 0..SIZE {
        let mut current = 0;
        let mut next = 1;
        while next < SIZE {
            let cur_val = board[current * SIZE + c];
            let next_val = board[next * SIZE + c];
            if cur_val > next_val {
                totals[2] += ((cur_val + 1) as f64).log2() - ((next_val + 1) as f64).log2();
            } else if next_val > cur_val {
                totals[3] += ((next_val + 1) as f64).log2() - ((cur_val + 1) as f64).log2();
            }
            current = next;
            next += 1;
        }
    }
    totals[0].max(totals[1]) + totals[2].max(totals[3])
}

fn corner_max_score(board: &[i32; BOARD_COUNT]) -> f64 {
    let max_val = *board.iter().max().unwrap_or(&0);
    if max_val <= 0 { return 0.0; }
    let corners = [0, SIZE - 1, BOARD_COUNT - SIZE, BOARD_COUNT - 1];
    if corners.iter().any(|&i| board[i] == max_val) { 1.0 } else { -1.0 }
}

fn stability_penalty(board: &[i32; BOARD_COUNT]) -> f64 {
    let mut penalty = 0.0;
    for r in 0..SIZE {
        for c in 0..SIZE {
            let idx = r * SIZE + c;
            let v = board[idx];
            if v == 0 { continue; }
            if c + 1 < SIZE {
                let nv = board[idx + 1];
                if nv > 0 { penalty += ((v as f64).log2() - (nv as f64).log2()).abs(); }
            }
            if r + 1 < SIZE {
                let nv = board[idx + SIZE];
                if nv > 0 { penalty += ((v as f64).log2() - (nv as f64).log2()).abs(); }
            }
        }
    }
    penalty
}

fn empty_indices(board: &[i32; BOARD_COUNT]) -> Vec<usize> {
    board.iter().enumerate().filter_map(|(i, &v)| if v == 0 { Some(i) } else { None }).collect()
}

fn can_move(board: &[i32; BOARD_COUNT]) -> bool {
    if board.iter().any(|&v| v == 0) { return true; }
    for r in 0..SIZE {
        for c in 0..SIZE {
            let idx = r * SIZE + c;
            let v = board[idx];
            if c + 1 < SIZE && board[idx + 1] == v { return true; }
            if r + 1 < SIZE && board[idx + SIZE] == v { return true; }
        }
    }
    false
}

fn add_random_tile(board: &mut [i32; BOARD_COUNT]) -> Option<usize> {
    let empties = empty_indices(board);
    if empties.is_empty() { return None; }
    let mut rng = rand::thread_rng();
    let &idx = empties.choose(&mut rng).unwrap();
    let value = if rng.gen::<f64>() < 0.9 { 2 } else { 4 };
    board[idx] = value;
    Some(idx)
}

fn move_board(board: &[i32; BOARD_COUNT], direction: Direction) -> MoveOutcome {
    let mut new_board = *board;
    let mut total_score = 0;
    let mut merged = HashSet::new();
    let mut changed = false;
    let mut movements = Vec::new();

    for line in 0..SIZE {
        let indices = line_indices(direction, line);
        let values: Vec<i32> = indices.iter().map(|&i| board[i]).collect();
        let (new_line, score, merged_positions, line_moves) = slide_and_merge(&values, &indices);
        total_score += score;
        for (offset, &idx) in indices.iter().enumerate() {
            if new_board[idx] != new_line[offset] { changed = true; }
            new_board[idx] = new_line[offset];
        }
        for pos in merged_positions {
            merged.insert(indices[pos]);
        }
        movements.extend(line_moves);
    }

    MoveOutcome { board: new_board, score: total_score, merged_indices: merged, movements, changed }
}

fn line_indices(direction: Direction, line: usize) -> Vec<usize> {
    match direction {
        Direction::Left => (0..SIZE).map(|i| line * SIZE + i).collect(),
        Direction::Right => (0..SIZE).map(|i| line * SIZE + (SIZE - 1 - i)).collect(),
        Direction::Up => (0..SIZE).map(|i| i * SIZE + line).collect(),
        Direction::Down => (0..SIZE).map(|i| (SIZE - 1 - i) * SIZE + line).collect(),
    }
}

fn slide_and_merge(values: &[i32], indices: &[usize]) -> (Vec<i32>, i32, Vec<usize>, Vec<Movement>) {
    let tiles: Vec<(usize, i32)> = values
        .iter()
        .enumerate()
        .filter_map(|(offset, &v)| if v == 0 { None } else { Some((indices[offset], v)) })
        .collect();

    let mut result: Vec<i32> = Vec::new();
    let mut score = 0;
    let mut merged_positions: Vec<usize> = Vec::new();
    let mut line_moves: Vec<Movement> = Vec::new();
    let mut i = 0;
    while i < tiles.len() {
        if i + 1 < tiles.len() && tiles[i].1 == tiles[i + 1].1 {
            let merged_value = tiles[i].1 * 2;
            result.push(merged_value);
            score += merged_value;
            let dest_pos = result.len() - 1;
            merged_positions.push(dest_pos);
            let dest_index = indices[dest_pos];
            line_moves.push(Movement { from: tiles[i].0, to: dest_index, value: tiles[i].1, is_merge: true });
            line_moves.push(Movement { from: tiles[i + 1].0, to: dest_index, value: tiles[i + 1].1, is_merge: true });
            i += 2;
        } else {
            result.push(tiles[i].1);
            let dest_pos = result.len() - 1;
            let dest_index = indices[dest_pos];
            line_moves.push(Movement { from: tiles[i].0, to: dest_index, value: tiles[i].1, is_merge: false });
            i += 1;
        }
    }
    while result.len() < SIZE { result.push(0); }
    (result, score, merged_positions, line_moves)
}

fn board_hash(board: &[i32; BOARD_COUNT], depth: i32, is_player: bool) -> u64 {
    let mut h: u64 = if is_player { 0x9E3779B185EBCA87 } else { 0xC2B2AE3D27D4EB4F };
    for &v in board.iter() {
        h = h.wrapping_mul(1099511628211) ^ ((v as u64).wrapping_mul(31) + 7);
    }
    h ^ ((depth as u64).wrapping_mul(131))
}

fn to_array(board: &Vec<i32>) -> [i32; BOARD_COUNT] {
    let mut arr = [0; BOARD_COUNT];
    for i in 0..BOARD_COUNT {
        arr[i] = *board.get(i).unwrap_or(&0);
    }
    arr
}
