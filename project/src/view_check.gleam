import gleam/io
import lustre/element
import skred_repl.{Model}

pub fn main() {
  let m =
    Model(
      running: True,
      input: "v0 n57,12 a-4.5 vt +-2 [lead] puts",
      lines: [],
      history: [],
      pos: -1,
      draft: "",
      comp: skred_repl.NoCompletion,
    )
  io.println(element.to_string(skred_repl.view(m)))
}
