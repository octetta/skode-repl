// Stand-in for the skred WASM engine: same Module surface the Gleam FFI calls.
// Parsing is done by the Gleam lexer (skodePlan); only the sound is improvised here.
(function () {
  var ctx = null, voices = {}, cur = 0, out = [];
  function voice(n) {
    if (!voices[n]) {
      var osc = ctx.createOscillator(), gain = ctx.createGain();
      gain.gain.value = 0; osc.frequency.value = 440;
      osc.connect(gain); gain.connect(ctx.destination); osc.start();
      voices[n] = { osc: osc, gain: gain };
    }
    return voices[n];
  }
  function run(cmd) {
    var plan = (globalThis.skodePlan ? globalThis.skodePlan(cmd) : "").split("\n").filter(Boolean);
    plan.forEach(function (line) {
      var m = /^(\S+) (\S+) ?(.*)$/.exec(line);
      if (!m) return;
      var t = parseFloat(m[1]), kind = m[2], val = m[3], at = ctx.currentTime + t, v;
      var when = t > 0 ? "t+" + t.toFixed(2) + "s " : "";
      if (kind === "voice") { cur = parseInt(val, 10); voice(cur); out.push(when + "voice " + cur); }
      else if (kind === "freq") { voice(cur).osc.frequency.setValueAtTime(parseFloat(val), at); out.push(when + "v" + cur + " freq " + val); }
      else if (kind === "note") { var f = 440 * Math.pow(2, (parseInt(val, 10) - 69) / 12); voice(cur).osc.frequency.setValueAtTime(f, at); out.push(when + "v" + cur + " note " + val + " (" + f.toFixed(1) + " Hz)"); }
      else if (kind === "amp_db") { var g = Math.min(1, Math.pow(10, parseFloat(val) / 20)) * 0.2; voice(cur).gain.gain.setValueAtTime(g, at); out.push(when + "v" + cur + " amp " + val + " dB"); }
      else if (kind === "level") { var l = Math.min(1, Math.max(0, parseFloat(val))) * 0.2; voice(cur).gain.gain.setValueAtTime(l, at); out.push(when + "v" + cur + " level " + val); }
      else if (kind === "-") { out.push(when + "parsed, no stand-in sound: " + val.replace(/^unsupported /, "")); }
    });
  }
  globalThis.Module = {
    _skred_start: function () {
      var AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return -1;
      ctx = new AC(); voices = {}; cur = 0; return 0;
    },
    _skred_stop: function () { if (ctx) { ctx.close(); } ctx = null; voices = {}; },
    ccall: function (name, _r, _t, args) { if (name === "skred_command" && ctx && args[0] !== "log 1") run(args[0]); },
    _skred_log: function () { return 1; },
    UTF8ToString: function () { var s = out.join("\n"); out = []; return s; }
  };
})();
