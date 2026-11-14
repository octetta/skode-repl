// Thin bridge to the Emscripten `Module` that skred_api.js puts on globalThis.
// Mirrors the calls used in skred-web's help.html.

const UNAVAILABLE = -1000;
const mod = () => globalThis.Module;

export function start_engine() {
  const m = mod();
  if (!m || typeof m._skred_start !== "function") return UNAVAILABLE;
  // skred_start(buffer_frames, max_voices, udp_port)
  const code = m._skred_start(128, 256, 0);
  // turn on API logging so skred_log() returns command output
  m.ccall("skred_command", null, ["string"], ["log 1"]);
  return code;
}

export function stop_engine() {
  const m = mod();
  if (m && typeof m._skred_stop === "function") m._skred_stop();
}

export function send_command(cmd) {
  const m = mod();
  m.ccall("skred_command", null, ["string"], [cmd]);
  const ptr = m._skred_log();
  return ptr ? m.UTF8ToString(ptr) : "";
}

// After Lustre patches the DOM: keep output pinned to the bottom, refocus input.
export function after_render() {
  requestAnimationFrame(() => {
    const out = document.getElementById("output");
    if (out) out.scrollTop = out.scrollHeight;
    const cmd = document.getElementById("cmd");
    if (cmd && !cmd.disabled) cmd.focus();
  });
}
