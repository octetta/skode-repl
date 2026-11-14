//// Skred web REPL in Gleam + Lustre.
//// Same engine calls as skred-web's help.html: start, send a Skode
//// command, read the text log, stop. Up/Down walk command history.

import complete
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/string
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import gleam/option
import skode.{type Op}

// ---- FFI ------------------------------------------------------------------

const engine_unavailable = -1000

@external(javascript, "./skred_repl_ffi.mjs", "start_engine")
fn ffi_start() -> Int

@external(javascript, "./skred_repl_ffi.mjs", "stop_engine")
fn ffi_stop() -> Nil

@external(javascript, "./skred_repl_ffi.mjs", "send_command")
fn ffi_send(cmd: String) -> String

@external(javascript, "./skred_repl_ffi.mjs", "after_render")
fn ffi_after_render() -> Nil

// ---- Model ----------------------------------------------------------------

pub type Line {
  Echo(String)
  Reply(String)
  Note(String)
}

pub type Completion {
  NoCompletion
  /// `idx` is -1 until the first Tab after the list was shown.
  Cycling(base: String, cands: List(String), idx: Int)
}

pub type Model {
  Model(
    running: Bool,
    input: String,
    // newest first
    lines: List(Line),
    // newest first
    history: List(String),
    // -1 = not browsing history
    pos: Int,
    // what was typed before browsing history
    draft: String,
    comp: Completion,
  )
}

pub type Msg {
  Typed(String)
  Key(String)
  Toggle
  Started(Int)
  Stopped
  Replied(String)
}

fn init(_flags) -> #(Model, Effect(Msg)) {
  #(
    Model(
      running: False,
      input: "",
      lines: [Note("Engine stopped. Start it, then try ?? or v0 f440 l1")],
      history: [],
      pos: -1,
      draft: "",
      comp: NoCompletion,
    ),
    effect.none(),
  )
}

// ---- Update ---------------------------------------------------------------

fn after() -> Effect(Msg) {
  effect.from(fn(_dispatch) { ffi_after_render() })
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    Typed(text) ->
      #(Model(..model, input: text, pos: -1, comp: NoCompletion), effect.none())

    Toggle ->
      case model.running {
        False -> #(
          model,
          effect.from(fn(dispatch) { dispatch(Started(ffi_start())) }),
        )
        True -> #(
          model,
          effect.from(fn(dispatch) {
            ffi_stop()
            dispatch(Stopped)
          }),
        )
      }

    Started(code) ->
      case code == engine_unavailable {
        True -> #(
          Model(..model, lines: [
            Note("skred_api.js isn’t loaded. Run ./fetch-wasm.sh first."),
            ..model.lines
          ]),
          after(),
        )
        False -> #(
          Model(..model, running: True, lines: [
            Note("Engine started. Return code: " <> int.to_string(code)),
            ..model.lines
          ]),
          after(),
        )
      }

    Stopped -> #(
      Model(..model, running: False, lines: [
        Note("Engine stopped."),
        ..model.lines
      ]),
      after(),
    )

    Replied(text) ->
      case text {
        "" -> #(model, effect.none())
        _ -> #(Model(..model, lines: [Reply(text), ..model.lines]), after())
      }

    Key("Enter") -> {
      let cmd = string.trim(model.input)
      case cmd, model.running {
        "", _ -> #(model, effect.none())
        _, False -> #(model, effect.none())
        _, True -> #(
          Model(
            ..model,
            input: "",
            lines: [Echo(cmd), ..model.lines],
            history: [cmd, ..model.history],
            pos: -1,
            draft: "",
            comp: NoCompletion,
          ),
          effect.batch([
            effect.from(fn(dispatch) { dispatch(Replied(ffi_send(cmd))) }),
            after(),
          ]),
        )
      }
    }

    Key("Tab") -> #(complete_step(model), after())

    Key("ArrowUp") -> {
      let next = model.pos + 1
      case list.first(list.drop(model.history, next)) {
        Ok(cmd) -> {
          let draft = case model.pos {
            -1 -> model.input
            _ -> model.draft
          }
          #(
            Model(..model, input: cmd, pos: next, draft: draft, comp: NoCompletion),
            effect.none(),
          )
        }
        Error(_) -> #(model, effect.none())
      }
    }

    Key("ArrowDown") ->
      case model.pos {
        -1 -> #(model, effect.none())
        0 -> #(
          Model(..model, input: model.draft, pos: -1, comp: NoCompletion),
          effect.none(),
        )
        p ->
          case list.first(list.drop(model.history, p - 1)) {
            Ok(cmd) -> #(
              Model(..model, input: cmd, pos: p - 1, comp: NoCompletion),
              effect.none(),
            )
            Error(_) -> #(model, effect.none())
          }
      }

    Key(_) -> #(model, effect.none())
  }
}

/// One Tab press: complete, extend to the common prefix and list the
/// choices, or cycle through the choices already listed.
fn complete_step(model: Model) -> Model {
  case model.comp {
    Cycling(base, cands, idx) -> {
      let next = { idx + 1 } % list.length(cands)
      case list.first(list.drop(cands, next)) {
        Ok(c) ->
          Model(..model, input: base <> c, comp: Cycling(base, cands, next))
        Error(_) -> model
      }
    }
    NoCompletion -> {
      let #(base, word) = complete.split_last_word(model.input)
      case complete.candidates(word) {
        [] -> model
        [one] -> Model(..model, input: base <> one)
        many ->
          Model(
            ..model,
            input: base <> complete.common_prefix(many),
            comp: Cycling(base, many, -1),
          )
      }
    }
  }
}

// ---- View -----------------------------------------------------------------

fn key_decoder() -> decode.Decoder(event.Handler(Msg)) {
  use key <- decode.field("key", decode.string)
  use shift <- decode.field("shiftKey", decode.bool)
  // Keep Tab (but not Shift+Tab) and the REPL keys from their browser defaults.
  let block = case key {
    "Tab" -> !shift
    "Enter" | "ArrowUp" | "ArrowDown" -> True
    _ -> False
  }
  decode.success(event.handler(Key(key), prevent_default: block, stop_propagation: False))
}

fn view_completions(comp: Completion) -> Element(Msg) {
  case comp {
    NoCompletion -> html.div([attribute.class("completions")], [])
    Cycling(_, cands, idx) -> {
      let chips =
        list.index_map(cands, fn(c, i) {
          html.span(
            [
              attribute.class(case i == idx {
                True -> "cand cur"
                False -> "cand"
              }),
              attribute.title(complete.describe(c)),
            ],
            [html.text(c)],
          )
        })
      let hint = case list.first(list.drop(cands, idx)) {
        Ok(c) if idx >= 0 -> [
          html.span([attribute.class("hint")], [
            html.text(c <> ": " <> complete.describe(c)),
          ]),
        ]
        _ -> []
      }
      html.div([attribute.class("completions")], list.append(chips, hint))
    }
  }
}

fn op_class(op: Op) -> String {
  case op {
    skode.Voice(_) -> "voice"
    skode.Note(..)
    | skode.Freq(_)
    | skode.Bend(_)
    | skode.BendRange(_)
    | skode.Glide(..)
    | skode.Detune(..) -> "pitch"
    skode.Amp(_) | skode.Level(_) | skode.Pan(_) | skode.Slew(..) -> "mix"
    skode.Wave(_)
    | skode.Mode(_)
    | skode.Loop(_)
    | skode.SampleWindow(_)
    | skode.WaveLoop(..)
    | skode.LoadWave(..)
    | skode.NameWave(..) -> "wave"
    skode.Defer(..)
    | skode.Pattern(_)
    | skode.MasterPattern(_)
    | skode.PatternSpeed(_)
    | skode.Step(..)
    | skode.OnEvent(..)
    | skode.Run(_)
    | skode.QueueStart(_)
    | skode.ClockSpeed(_)
    | skode.Ratchet(_)
    | skode.Goto(_)
    | skode.Clock(..)
    | skode.EmitEvent(_) -> "time"
    skode.Puts(_) | skode.MacroDef(..) -> "text"
    skode.Stray(_) | skode.Generic(_) -> "raw"
  }
}

/// Live, colour-coded reading of what is being typed. Atoms the typed layer
/// doesn't know are still valid and are sent to the engine as typed.
fn view_preview(input: String) -> Element(Msg) {
  let chunks = skode.parse_program(input)
  let ops = list.flat_map(chunks, fn(c) { c.ops })
  let chips =
    list.map(ops, fn(op) {
      html.span([attribute.class("chip " <> op_class(op))], [
        html.text(skode.op_to_string(op)),
      ])
    })
  let remarks =
    list.filter_map(chunks, fn(c) {
      case c.remark {
        option.Some(r) ->
          Ok(html.span([attribute.class("chip text")], [html.text("#" <> r)]))
        option.None -> Error(Nil)
      }
    })
  let hint = case skode.generic_atoms(ops) {
    [] -> []
    atoms -> [
      html.span([attribute.class("hint")], [
        html.text("untyped: " <> string.join(atoms, " ")),
      ]),
    ]
  }
  html.div(
    [attribute.id("preview"), attribute.class("preview")],
    list.append(list.append(chips, remarks), hint),
  )
}

fn view_line(line: Line) -> Element(Msg) {
  case line {
    Echo(t) -> html.div([attribute.class("echo")], [html.text("> " <> t)])
    Reply(t) -> html.div([attribute.class("reply")], [html.text(t)])
    Note(t) -> html.div([attribute.class("note")], [html.text(t)])
  }
}

pub fn view(model: Model) -> Element(Msg) {
  html.main([attribute.class("repl")], [
    html.header([], [
      html.h1([], [html.text("skred")]),
      html.button([event.on_click(Toggle)], [
        html.text(case model.running {
          True -> "Stop engine"
          False -> "Start engine"
        }),
      ]),
    ]),
    html.div(
      [attribute.id("output"), attribute.class("output")],
      list.map(list.reverse(model.lines), view_line),
    ),
    view_preview(model.input),
    view_completions(model.comp),
    html.div([attribute.class("row")], [
      html.input([
        attribute.id("cmd"),
        attribute.class("cmd"),
        attribute.value(model.input),
        attribute.disabled(!model.running),
        attribute.placeholder("Skode command, e.g. v0 f440 l1"),
        attribute.attribute("autocapitalize", "none"),
        attribute.attribute("autocorrect", "off"),
        attribute.attribute("autocomplete", "off"),
        attribute.attribute("spellcheck", "false"),
        event.on_input(Typed),
        event.advanced("keydown", key_decoder()),
      ]),
      html.button(
        [
          attribute.class("tab"),
          attribute.attribute("aria-label", "Complete"),
          attribute.disabled(!model.running),
          event.on_click(Key("Tab")),
        ],
        [html.text("⇥")],
      ),
    ]),
  ])
}

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}
