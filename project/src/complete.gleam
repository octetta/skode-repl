//// Tab completion for Skode input. Pure functions, no DOM.
//// Templates are the command shapes `skode.gleam` understands; the
//// descriptions are inferred from mod2skode.py's output, not an official spec.

import gleam/list
import gleam/string

const templates = [
  #("v0", "select voice"),
  #("n60", "note (MIDI), optionally n60,cents"),
  #("f440", "frequency in Hz"),
  #("a-6", "amplitude in dB"),
  #("l1", "level"),
  #("p0", "pan, -1 to 1"),
  #("w0", "wave id"),
  #("m0", "mode"),
  #("B1", "loop on/off"),
  #("fb0", "frequency bend"),
  #("fbp24", "bend range in semitones"),
  #("g0.01", "glide time[,curve]"),
  #("s0.01", "slew time[,curve]"),
  #("N0,0", "detune wave,cents"),
  #("VS", "sample window, optionally VS start,end"),
  #("WL", "wave loop: WL id,start,end"),
  #("+0.01", "defer by seconds"),
  #("+-1", "defer by ticks"),
  #("y0", "select pattern"),
  #("yp127", "master pattern"),
  #("%6", "pattern speed"),
  #("x0", "step index"),
  #("z1", "run on/off"),
  #("zq1", "queue next pattern"),
  #("z%3", "clock speed"),
  #("z*2", "step ratchet"),
  #("zg0", "goto step"),
  #("M125,96", "clock: bpm,subdivision"),
  #("ce 0", "emit control event"),
  #("e>0", "event handler: [ops] e>id"),
  #("puts", "print text: [text] puts"),
  #("wt", "name a wave: [name] wt id"),
  #("/ws", "load a wave: [path] /ws id"),
  #("/cex", "control event map"),
  #("/cer", "control event"),
]

/// Split input into everything before the last word (keeping its trailing
/// space) and the last word.
pub fn split_last_word(input: String) -> #(String, String) {
  let rev = string.to_graphemes(input) |> list.reverse
  let #(word_rev, base_rev) = list.split_while(rev, fn(c) { c != " " })
  #(string.concat(list.reverse(base_rev)), string.concat(list.reverse(word_rev)))
}

/// Templates that start with `word`. Empty word completes nothing.
pub fn candidates(word: String) -> List(String) {
  case word {
    "" -> []
    _ ->
      list.filter_map(templates, fn(t) {
        case string.starts_with(t.0, word) {
          True -> Ok(t.0)
          False -> Error(Nil)
        }
      })
  }
}

pub fn describe(template: String) -> String {
  case list.find(templates, fn(t) { t.0 == template }) {
    Ok(#(_, d)) -> d
    Error(_) -> ""
  }
}

fn pair_prefix(a: String, b: String) -> String {
  do_pair(string.to_graphemes(a), string.to_graphemes(b), [])
}

fn do_pair(a: List(String), b: List(String), acc: List(String)) -> String {
  case a, b {
    [x, ..xs], [y, ..ys] if x == y -> do_pair(xs, ys, [x, ..acc])
    _, _ -> string.concat(list.reverse(acc))
  }
}

pub fn common_prefix(words: List(String)) -> String {
  case words {
    [] -> ""
    [first, ..rest] -> list.fold(rest, first, pair_prefix)
  }
}
