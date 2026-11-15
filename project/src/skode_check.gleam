import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import skode.{
  type Op, Beats, Chunk, Command, Defer, Generic, Lit, MacroDef,
  Note, Rest, Seconds, Tie, Value,
}

fn check(name: String, got: a, want: a) -> Bool {
  case got == want {
    True -> {
      io.println("ok    " <> name)
      True
    }
    False -> {
      io.println("FAIL  " <> name)
      io.println("  got  " <> string.inspect(got))
      io.println("  want " <> string.inspect(want))
      False
    }
  }
}

fn ops(src: String) -> List(Op) {
  skode.parse_ops(src)
}

fn roundtrip(name: String, src: String) -> Bool {
  let a = skode.parse_program(src)
  let b = skode.parse_program(skode.program_to_string(a))
  check("roundtrip " <> name, b, a)
}

fn num(f: Float) -> skode.Arg {
  Lit(Value(f))
}

pub fn main() {
  let results = [
    // tokenizing
    check("tight packing", ops("v0w1f440"), [skode.Voice(0), skode.Wave(1), skode.Freq(440.0)]),
    check("comma is whitespace", ops("n57,12"), [Note(57, Some(12.0))]),
    check("args may precede the atom", ops("440 f"), [skode.Freq(440.0)]),
    check("decimals and signs", ops("p-.6 a-100.00 l.5"), [skode.Pan(-0.6), skode.Amp(-100.0), skode.Level(0.5)]),
    check("atoms with symbols", ops("z%3 z*2 zg0 zq1 yp127 %6"), [
      skode.ClockSpeed(3), skode.Ratchet(2), skode.Goto(0), skode.QueueStart(True),
      skode.MasterPattern(127), skode.PatternSpeed(6),
    ]),
    check("M both forms", ops("M125,96") == ops("M 125 96"), True),
    check("bare g clears glide", ops("g"), [skode.Glide(0.0, None)]),
    check("one step behind: 8 args max", ops("DL 1 2 3 4 5 6 7 8 9"), [
      Generic(Command("DL", [num(1.0), num(2.0), num(3.0), num(4.0), num(5.0), num(6.0), num(7.0), num(8.0)], None, None)),
    ]),
    // sentinels
    check("sentinels as args", ops("- - 0.75 DL"), [
      Generic(Command("DL", [Lit(Rest), Lit(Rest), num(0.75)], None, None)),
    ]),
    // arrays
    check("array with sentinels", ops("/SS 0 ( 1 - . 3 )"), [
      Generic(Command("/SS", [num(0.0)], Some([num(1.0), Lit(Rest), Lit(Tie), num(3.0)]), None)),
    ]),
    check("array commas, hex, exponent", ops("/SS (1,2 0x10 1e2 -- ...)"), [
      Generic(Command("/SS", [], Some([num(1.0), num(2.0), num(16.0), num(100.0), Lit(Rest), Lit(Tie)]), None)),
    ]),
    check("array with variable", ops("/SS ( $3 2 )"), [
      Generic(Command("/SS", [], Some([skode.VarRef(3), num(2.0)]), None)),
    ]),
    check("array buffer gotcha", ops("( 10 20 ) /SS 3 ( 30 40 ) /SS 4"), [
      Generic(Command("/SS", [num(3.0)], Some([num(30.0), num(40.0)]), None)),
      Generic(Command("/SS", [num(4.0)], None, None)),
    ]),
    // comments and chunk ends
    check("inline comment ends at ;", skode.parse_program("v0 f440 # lead; v1"), [
      Chunk([skode.Voice(0), skode.Freq(440.0)], Some(" lead")),
      Chunk([skode.Voice(1)], None),
    ]),
    check("comment-only line", skode.parse_program("# only"), [Chunk([], Some(" only"))]),
    check("semicolon and newline", list.length(skode.parse_program("v0;v1\nv2")), 3),
    // defers
    check("seconds defer", ops("~1.5 f 440"), [Defer(Seconds, num(1.5), [skode.Freq(440.0)])]),
    check("tick defers chain", ops("+-3 n57 l1 +-5 a-100"), [
      Defer(Beats, num(-3.0), [Note(57, None), skode.Level(1.0)]),
      Defer(Beats, num(-5.0), [skode.Amp(-100.0)]),
    ]),
    check("defer ends the chunk before it", list.length(skode.parse_program("v0 +1 n60")), 2),
    // strings, steps, macros
    check("step", ops("[v0 n57 l1] x12"), [skode.Step([skode.Voice(0), Note(57, None), skode.Level(1.0)], 12)]),
    check("empty step", ops("[] x13"), [skode.Step([], 13)]),
    check("event handler", ops("[y0 z0] e>3"), [skode.OnEvent([skode.Pattern(0), skode.Run(False)], 3)]),
    check("puts / wt / ws on separate chunks", ops("[hi there] puts; [bass] wt 101\n[a/b.wav] /ws 101"), [
      skode.Puts("hi there"), skode.NameWave("bass", 101), skode.LoadWave("a/b.wav", 101),
    ]),
    check("string goes to the atom that fires next", ops("[hi] puts [bass] wt 101"), [
      skode.Puts("bass"), Generic(Command("wt", [num(101.0)], None, None)),
    ]),
    check("print: string first at chunk start", skode.program_to_string(skode.parse_program("[hi] puts")), "[hi] puts"),
    check("print: string after its atom later in a chunk", skode.program_to_string(skode.parse_program("v0 puts [hi]")), "v0 puts [hi]"),
    check("later string overwrites the buffer", ops("[v0] x12 [hi] puts"), [
      skode.Step([Generic(Command("hi", [], None, None))], 12),
      Generic(Command("puts", [], None, None)),
    ]),
    check("macro definition", ops("[play]: v0 y0 z1;"), [MacroDef("play", " v0 y0 z1")]),
    check("label string goes to next atom", ops("[ch 1] vt"), [
      Generic(Command("vt", [], None, Some("ch 1"))),
    ]),
    check("unterminated string swallows input", ops("v0 [abc"), [skode.Voice(0)]),
    check("stray numbers", ops("440"), [skode.Stray([num(440.0)])]),
    // printing
    check("print keeps whole numbers whole", skode.program_to_string(skode.parse_program("v0 f440 l1")), "v0 f440 l1"),
    // blanks after the defer sigil (the guide's "+ 4 ..." form)
    check("spaced beats defer", ops("+ 4 v0"), [Defer(Beats, num(4.0), [skode.Voice(0)])]),
    check("spaced seconds defer", ops("~ 1.5 f 440"), [Defer(Seconds, num(1.5), [skode.Freq(440.0)])]),
    check("spaced negative (ticks) defer", ops("+ -3 n57"), [Defer(Beats, num(-3.0), [Note(57, None)])]),
    check("spaced variable defer", ops("+   $1 v0"), [Defer(Beats, skode.VarRef(1), [skode.Voice(0)])]),
    check("spaced stream defer", ops("~ &3 v0"), [Defer(Seconds, skode.StreamRef(3), [skode.Voice(0)])]),
    check("blank then non-number stays a zero delay", ops("+ v0 a10"), [
      Defer(Beats, num(0.0), [skode.Voice(0), skode.Amp(10.0)]),
    ]),
    check("blanks never cross a chunk end", list.length(skode.parse_program("+ \n4 v0")), 2),
    // `&` takes digits only; a bare $ or & never swallows the next character
    check("& then a letter is not a stream", ops("f &x"), [
      Generic(Command("f", [], None, None)), Generic(Command("x", [], None, None)),
    ]),
    check("bare & in an array", ops("( 1 &a 3 ) /SS"), [
      Generic(Command("/SS", [], Some([num(1.0), num(0.0), num(3.0)]), None)),
    ]),
    check("bare $ in an array", ops("( 1 $xy 3 ) /SS"), [
      Generic(Command("/SS", [], Some([num(1.0), num(0.0), num(3.0)]), None)),
    ]),
    check("bare & in a defer keeps its body", ops("+&x v0"), [
      Defer(Beats, num(0.0), [Generic(Command("x", [], None, None)), skode.Voice(0)]),
    ]),
    check("bare $ in a defer keeps its body", ops("+$v0 a10"), [
      Defer(Beats, num(0.0), [skode.Voice(0), skode.Amp(10.0)]),
    ]),
    // round trips over converter-style lines
    roundtrip("converter voice setup", "v0 [ch 1] vt w0 m0 n60 l1 B1 p-0.6 t0,0,1,0 s0.002,1 g0.001,2 g0 fbp24 a-100 F0 A0"),
    roundtrip("pattern line", "y127 %6 [v0] x127 yp127"),
    roundtrip("step with defers", "[+-2 n57,12 l1 a-4.5 fb0.125 VS512,2048] x12"),
    roundtrip("handler", "[y0 z0 y1 zq1] e>0"),
    roundtrip("macro", "[play]: v0 s0.002,1 l1 y0 z1 y127 z1;"),
    roundtrip("array + comment", "/SS 0 ( 1 - . 3 ) # note"),
    roundtrip("spaced defer", "~ 1.5 f 440\n+ -3 n57,12 l1"),
    roundtrip("bare g", "g"),
    roundtrip("envelope 2-arg and flat", "t0.01,0.05 t"),
    roundtrip("links G, H, HS", "G ( 1 2 ) H ( 3 ) HS ( 0 1 2 )"),
    roundtrip("clock", "M 125 96\nA5,0.025,0.975 /cex 0,4,0 ce 127"),
  ]
  let failed = list.filter(results, fn(r) { !r }) |> list.length
  io.println("")
  io.println(string.inspect(list.length(results)) <> " checks, " <> string.inspect(failed) <> " failed")
}
