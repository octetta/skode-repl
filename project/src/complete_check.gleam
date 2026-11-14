import gleam/io
import gleam/list
import gleam/string
import skred_repl.{Key, Model, NoCompletion, Typed}

fn run(start: String, keys: List(String)) -> String {
  let m0 =
    Model(running: True, input: start, lines: [], history: [], pos: -1, draft: "", comp: NoCompletion)
  let m =
    list.fold(keys, m0, fn(m, k) {
      let #(m, _) = skred_repl.update(m, Key(k))
      m
    })
  string.inspect(m.input)
}

pub fn main() {
  io.println("z        -> " <> run("z", []))
  io.println("z Tab    -> " <> run("z", ["Tab"]))
  io.println("z Tab x2 -> " <> run("z", ["Tab", "Tab"]))
  io.println("z Tab x3 -> " <> run("z", ["Tab", "Tab", "Tab"]))
  io.println("z Tab x7 -> " <> run("z", ["Tab", "Tab", "Tab", "Tab", "Tab", "Tab", "Tab"]))
  io.println("v0 pu Tab -> " <> run("v0 pu", ["Tab"]))
  io.println("v0 fb Tab -> " <> run("v0 fb", ["Tab"]))
  io.println("v0 fb Tab x3 -> " <> run("v0 fb", ["Tab", "Tab", "Tab"]))
  io.println("empty Tab -> " <> run("", ["Tab"]))
  io.println("v0 (trailing space) Tab -> " <> run("v0 ", ["Tab"]))
  io.println("qq Tab -> " <> run("qq", ["Tab"]))
  let #(m, _) =
    skred_repl.update(
      Model(running: True, input: "z", lines: [], history: [], pos: -1, draft: "", comp: NoCompletion)
      |> fn(m) { skred_repl.update(m, Key("Tab")).0 },
      Typed("zq"),
    )
  io.println("typing resets cycle, then Tab -> " <> string.inspect(skred_repl.update(m, Key("Tab")).0.input))
}
