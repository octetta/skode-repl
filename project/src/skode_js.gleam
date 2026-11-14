//// Bridge for the browser stand-in engine: turns Skode text into plain lines
//// a JS audio shim can act on. The parsing is the real Gleam lexer; only the
//// meaning given to a few commands below is the shim's own assumption.

import gleam/float
import gleam/int
import gleam/list
import gleam/string
import skode.{type Op}

/// One line per op: `<delay seconds> <kind> <value>`, or `<delay> - unsupported <text>`.
/// Delays follow skode_defer: positive defers within a chunk accumulate, zero
/// or negative ones restart from 0. Beats assume 120 BPM and one tick is a
/// quarter beat (a tempo step); both are the shim's assumptions.
pub fn plan(src: String) -> String {
  skode.parse_program(src)
  |> list.flat_map(fn(chunk) { chunk_lines(chunk.ops) })
  |> string.join("\n")
}

fn num(f: Float) -> String {
  float.to_string(f)
}

fn chunk_lines(ops: List(Op)) -> List(String) {
  let #(_, acc) =
    list.fold(ops, #(0.0, []), fn(state, op) {
      let #(cursor, acc) = state
      case op {
        skode.Defer(mode, skode.Lit(skode.Value(n)), body) -> {
          let at = case n <=. 0.0 {
            True -> { 0.0 -. n } *. 0.125
            False ->
              cursor
              +. case mode {
                skode.Beats -> n *. 0.5
                skode.Seconds -> n
              }
          }
          #(at, list.append(acc, now(body, at)))
        }
        _ -> #(cursor, list.append(acc, now([op], 0.0)))
      }
    })
  acc
}

fn now(ops: List(Op), at: Float) -> List(String) {
  list.map(ops, fn(op) {
    let when = num(at)
    case op {
      skode.Voice(n) -> when <> " voice " <> int.to_string(n)
      skode.Freq(f) -> when <> " freq " <> num(f)
      skode.Note(m, _) -> when <> " note " <> int.to_string(m)
      skode.Amp(db) -> when <> " amp_db " <> num(db)
      skode.Level(l) -> when <> " level " <> num(l)
      _ -> when <> " - unsupported " <> skode.op_to_string(op)
    }
  })
}
