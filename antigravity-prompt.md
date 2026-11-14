# Task: fix three `ands` parser defects in octetta/pulp (C), with tests and docs

You are working in the `octetta/pulp` repository. The `ands` lexer lives in `parts/ands.c`; its tests are `parts/tests/ands_parser_tests.c`. Make the change below **minimal and behaviour-preserving for everything not listed**. Do not refactor, rename, reformat or touch unrelated code.

## Why

The guide (`ands_parser_guide.md`) documents defers written with a blank after the sigil (`+ 4 /SS 0 ( 1 2 3 )`, `~ 1.5 f 440`), but the lexer only reads the amount when it touches the sigil. `+ 4 v0` silently becomes a zero delay whose body is `4 v0`. Separately, `&` followed by a letter is accepted as a stream although `ands_var_parse` only reads digits, and a bare `$`/`&` (not followed by a digit) swallows the character after it in arrays and defers. These were confirmed by running the real parser.

## Defects and required behaviour

### 1. Blanks between a defer sigil and its amount (`GET_DEFER_NUMBER`)

- While no amount digits have been read yet, skip blanks (space, tab, comma, i.e. `IS_SEPARATOR`) **only if** a number char, `$`, or `&` follows them. Never skip across a chunk end (`;`, `\n`, `\r`, EOT).
- If blanks are followed by anything else (`+ v0 a10`), keep today's behaviour exactly: zero delay, body ` v0 a10`.
- Attached forms (`+4 v0`, `~1.5`, `+-3`, `+$1`, `+&3`) must be unchanged.
- Expected: `+ 4 v0` is DEFER mode `+`, amount 4; `~ 1.5 f 440` is mode `~`, amount 1.5, body ` f 440`; `+ -3 n57` is amount -3; `+   $1 v0` has variable 1; `~ &3 v0` has stream 3 with `ANDS_STREAM_FLAG`; `+;` is a zero delay.

### 2. `&` takes digits only

- There are three sites that test `isdigit(c) || isalpha(c)` after `&`: the array `&` branch in `GET_ARRAY`, `GET_STREAM`, and the defer `&` branch in `GET_DEFER_NUMBER`. Change each to `isdigit` only, consistent with `ands_var_parse`, the `$` branches and the guide (`&N`).
- Do **not** invent letter-named streams. If you believe they were intended, stop and report instead of implementing.

### 3. A bare `$` / `&` must not swallow the next character

- In `GET_ARRAY` (both the `$` and `&` branches) and in `GET_DEFER_NUMBER` (both the `$` and `&` branches), when the sigil is **not** followed by a digit, step back one character (`ptr--`) so the following character is lexed normally. `GET_VARIABLE` / `GET_STREAM` already handle this by reprocessing; use the same convention.
- Do this together with defect 2. Applying only defect 2 makes it worse (it newly swallows the character after `&`).
- Expected: `f &x;` gives FUNCTION `f` with 0 args, then FUNCTION `x`; `( 1 &a 3 ) vt;` and `( 1 $xy 3 ) vt;` each give an array of 3 values; `+&x v0;` has body `x v0`; `+$v0 a10;` has body `v0 a10`.

## How to verify

The test file builds standalone (no engine needed):

```
gcc -std=gnu11 -Wall -Iparts -o /tmp/ands_tests parts/tests/ands_parser_tests.c parts/ands.c && /tmp/ands_tests
```

It must print `ANDS parser tests passed` with no warnings. Also find and run the project's normal build and test targets (check the Makefile and `CODEX_SESSION.md`; if there is an agent or contributor guide, follow it) and report their results. If a target cannot run in your environment, say so; do not claim it passed.

## Tests to add

Add them to `parts/tests/ands_parser_tests.c` in the existing style (`run_parse`, `expect_event`, `expect_arg`) and call them from `main`:

- `test_defer_space`: the cases under defect 1, including the unchanged `+ v0 a10` and `+;`, and the attached `+4 v0`.
- `test_defer_space_streams`: `+ &3 v0; ~   &5 v1;` (stream provenance and mode preserved) and `+ $2 v0; ~ $4 v1;` (variable provenance preserved). Note there are five events for two chunks: CHUNK_END, DEFER, CHUNK_END, DEFER, CHUNK_END.
- `test_stream_variable_sigil_edges`: the cases under defects 2 and 3.

Confirm the new tests **fail on the unmodified parser and pass after your change** (stash the `ands.c` change to check). The patches in the appendix already contain working versions of all of this; apply them if they fit, otherwise implement by intent. Line numbers will have drifted.

## Docs

Update `ands_parser_guide.md` only where it is now wrong or newly precise:
- State that blanks are allowed between `+`/`~` and the amount when a number, `$N` or `&N` follows, and that `&` takes digits only.
- The guide says macro names are at most 4 characters, but `ands.h` and `test_macro_names_truncate_to_atom_width` show names up to 31 characters. Verify against the source and correct the guide if it is stale.

## Also check, and report (do not change unless required)

- Anything else that re-parses defer text or `$`/`&` syntax independently of `ands.c` (`skode.c` scheduled-defer compile, `skode-event.c`, `midi2skode.c`, converter scripts, any syntax highlighter or JS/WASM UI in the repo). List each and whether it needs the same change.
- Whether any `.sk`, `.ks` or example file in the repo changes meaning. A sigil, blanks, then a number-led body used to mean "zero delay, postfix args"; a repository grep found none, but confirm.
- Whether the repo has a release-note or VERSION convention for parser fixes, and follow it if so. Do not bump versions otherwise.

## Out of scope

- Letter-named streams, any other lexer behaviour, macro expansion, and rebuilding or publishing the WASM bundle.
- Reformatting, renaming, or style changes anywhere.

## Final report

Give: files changed; a short before/after table for the examples above; exact test commands run and their output; anything you could not verify; the other-consumers list.

## Appendix A: patch 1 (blanks after the defer sigil)

```diff
--- a/parts/ands.c	2026-11-13 07:40:34.530349626 +0000
+++ b/parts/ands.c	2026-11-14 06:39:49.992984841 +0000
@@ -972,6 +972,18 @@
                 break;
 
             case GET_DEFER_NUMBER:
+                /* Tolerate blanks between the sigil and its amount ("+ 4 ...",
+                 * "~ 1.5 f 440", as the guide documents). Only skip when a
+                 * number, $var or &stream follows, so "+ v0 a10" still means
+                 * a zero delay with body " v0 a10". Never cross a chunk end. */
+                if (s->num.len == 0 && IS_SEPARATOR(*ptr) && !IS_CHUNK_END(*ptr)) {
+                    char *q = ptr;
+                    while (q < end && IS_SEPARATOR(*q) && !IS_CHUNK_END(*q)) q++;
+                    if (q < end && (IS_NUMBER(*q) || IS_VARIABLE(*q) || IS_STREAM(*q))) {
+                        ptr = q - 1;
+                        break;
+                    }
+                }
                 if (IS_NUMBER(*ptr)) {
                     buffer_push(&s->num, *ptr);
                 } else if (IS_VARIABLE(*ptr)) {
--- a/parts/tests/ands_parser_tests.c	2026-11-14 06:39:59.676486750 +0000
+++ b/parts/tests/ands_parser_tests.c	2026-11-14 08:20:50.654983423 +0000
@@ -490,6 +490,62 @@
   expect_event(test, &r, 2, CHUNK_END, "----");
 }
 
+static void test_defer_space(void) {
+  const char *test = "defer space";
+  recorder_t r;
+
+  char a[] = "+ 4 v0;";                      /* guide: "+ 4 /SS ..." */
+  run_parse(test, a, &r);
+  expect_event(test, &r, 1, DEFER, "----");
+  if (r.len > 1 && !(r.events[1].defer_mode == '+' && near_double(r.events[1].defer_num, 4)))
+    fail(test, "\"+ 4 v0\" should defer 4 beats");
+
+  char b[] = "~ 1.5 f 440;";                 /* guide: "~ 1.5 f 440" */
+  run_parse(test, b, &r);
+  expect_event(test, &r, 1, DEFER, "----");
+  if (r.len > 1 && !(r.events[1].defer_mode == '~' && near_double(r.events[1].defer_num, 1.5)))
+    fail(test, "\"~ 1.5 f 440\" should defer 1.5 seconds");
+  if (r.len > 1 && strcmp(r.events[1].text, " f 440") != 0)
+    fail(test, "\"~ 1.5 f 440\" body should be \" f 440\"");
+
+  char c[] = "+ -3 n57;";                    /* negative = ticks */
+  run_parse(test, c, &r);
+  if (r.len > 1 && !near_double(r.events[1].defer_num, -3)) fail(test, "\"+ -3\" should be -3");
+
+  char d[] = "+   $1 v0;";                   /* several blanks, then a variable */
+  run_parse(test, d, &r);
+  if (r.len > 1 && r.events[1].defer_var != 1) fail(test, "\"+ $1\" lost its variable");
+
+  char e[] = "+ v0 a10;";                     /* unchanged: zero delay, body kept as-is */
+  run_parse(test, e, &r);
+  if (r.len > 1 && !(near_double(r.events[1].defer_num, 0) && strcmp(r.events[1].text, " v0 a10") == 0))
+    fail(test, "\"+ v0 a10\" must stay a zero delay with body \" v0 a10\"");
+
+  char f[] = "+;";                            /* sigil then chunk end: unchanged */
+  run_parse(test, f, &r);
+  if (r.len > 1 && !near_double(r.events[1].defer_num, 0)) fail(test, "\"+;\" should be a zero delay");
+
+  char g[] = "+4 v0;";                        /* attached form still works */
+  run_parse(test, g, &r);
+  if (r.len > 1 && !near_double(r.events[1].defer_num, 4)) fail(test, "attached form broke");
+}
+
+
+static void test_defer_space_streams(void) {
+  const char *test = "defer space streams";
+  recorder_t r;
+  char a[] = "+ &3 v0; ~   &5 v1;";
+  run_parse(test, a, &r);
+  expect_len(test, &r, 5);
+  if (r.len > 1 && r.events[1].defer_var != (3 | ANDS_STREAM_FLAG)) fail(test, "+ &3 lost stream provenance");
+  if (r.len > 3 && r.events[3].defer_var != (5 | ANDS_STREAM_FLAG)) fail(test, "~   &5 lost stream provenance");
+  if (r.len > 1 && r.events[1].defer_mode != '+') fail(test, "mode lost");
+  char b[] = "+ $2 v0; ~ $4 v1;";
+  run_parse(test, b, &r);
+  expect_len(test, &r, 5);
+  if (r.len > 1 && r.events[1].defer_var != 2) fail(test, "+ $2 lost variable provenance");
+  if (r.len > 3 && r.events[3].defer_var != 4) fail(test, "~ $4 lost variable provenance");
+}
 int main(void) {
   test_compact_commands();
   test_strings_and_arrays();
@@ -497,6 +553,8 @@
   test_tie_and_rest_sentinels();
   test_comments_and_chunks();
   test_defer();
+  test_defer_space();
+  test_defer_space_streams();
   test_variable_provenance();
   test_stream_defer();
   test_arrays_with_variables_and_streams();
```

## Appendix B: patch 2 (`&` digits only, bare sigils do not swallow)

Applies on top of patch 1.

```diff
--- a/parts/ands.c	2026-11-14 06:39:49.992984841 +0000
+++ b/parts/ands.c	2026-11-14 08:24:41.021771541 +0000
@@ -854,6 +854,8 @@
                         if (s->data && s->data_len < s->data_cap)
                             s->data[s->data_len++] = val;
                         ptr--;
+                    } else {
+                        ptr--;   /* bare '$': reprocess the next character */
                     }
                 } else if (IS_STREAM(*ptr)) {
                     if (s->num.len > 0) {
@@ -862,12 +864,14 @@
                         buffer_clear(&s->num);
                     }
                     ptr++;
-                    if (ptr < end && (isdigit((unsigned char)*ptr) || isalpha((unsigned char)*ptr))) {
+                    if (ptr < end && isdigit((unsigned char)*ptr)) {
                         int stream = ands_var_parse(&ptr, end);
                         double val = ands_stream_pull(s, stream);
                         if (s->data && s->data_len < s->data_cap)
                             s->data[s->data_len++] = val;
                         ptr--;
+                    } else {
+                        ptr--;   /* bare '&': reprocess the next character */
                     }
                 } else if (IS_SEPARATOR(*ptr)) {
                     if (s->num.len > 0) {
@@ -895,7 +899,7 @@
 
             
             case GET_STREAM:
-                if (isdigit(*ptr) || isalpha(*ptr)) {
+                if (isdigit(*ptr)) {
                     int stream = ands_var_parse(&ptr, end);
                     if (s->arg_len < s->arg_cap) {
                         s->arg[s->arg_len] = 0.0;
@@ -996,12 +1000,13 @@
                     } else {
                         s->defer_num = 0.0;
                         s->defer_var = -1;
+                        ptr--;   /* bare sigil: reprocess the next character */
                     }
                     buffer_clear(&s->num);
                     s->state = GET_DEFER_STRING;
                 } else if (IS_STREAM(*ptr)) {
                     ptr++;
-                    if (ptr < end && (isdigit((unsigned char)*ptr) || isalpha((unsigned char)*ptr))) {
+                    if (ptr < end && isdigit((unsigned char)*ptr)) {
                         int stream = ands_var_parse(&ptr, end);
                         s->defer_num = ands_defer_time_clamp(ands_stream_pull(s, stream));
                         s->defer_var = stream | ANDS_STREAM_FLAG;
@@ -1009,6 +1014,7 @@
                     } else {
                         s->defer_num = 0.0;
                         s->defer_var = -1;
+                        ptr--;   /* bare sigil: reprocess the next character */
                     }
                     buffer_clear(&s->num);
                     s->state = GET_DEFER_STRING;
--- a/parts/tests/ands_parser_tests.c	2026-11-14 11:40:41.133232830 +0000
+++ b/parts/tests/ands_parser_tests.c	2026-11-14 11:40:41.179341379 +0000
@@ -546,6 +546,40 @@
   if (r.len > 1 && r.events[1].defer_var != 2) fail(test, "+ $2 lost variable provenance");
   if (r.len > 3 && r.events[3].defer_var != 4) fail(test, "~ $4 lost variable provenance");
 }
+
+static void test_stream_variable_sigil_edges(void) {
+  const char *test = "bare $ / & sigils";
+  recorder_t r;
+
+  /* '&' needs digits (ands_var_parse only reads digits); a letter is not a stream */
+  char a[] = "f &x;";
+  run_parse(test, a, &r);
+  expect_event(test, &r, 0, FUNCTION, "f---");
+  if (r.len > 0 && r.events[0].argc != 0) fail(test, "\"f &x\" must not gain a phantom argument");
+  expect_event(test, &r, 1, FUNCTION, "x---");
+
+  /* a bare sigil in an array must not swallow the next character */
+  char b[] = "( 1 &a 3 ) vt;";
+  run_parse(test, b, &r);
+  expect_event(test, &r, 0, GOT_ARRAY, "----");
+  if (r.len > 0 && r.events[0].argc != 3) fail(test, "\"( 1 &a 3 )\" should hold 3 values");
+
+  char c[] = "( 1 $xy 3 ) vt;";
+  run_parse(test, c, &r);
+  expect_event(test, &r, 0, GOT_ARRAY, "----");
+  if (r.len > 0 && r.events[0].argc != 3) fail(test, "\"( 1 $xy 3 )\" should hold 3 values");
+
+  /* a bare sigil in a defer must not swallow the first body character */
+  char d[] = "+&x v0;";
+  run_parse(test, d, &r);
+  expect_event(test, &r, 1, DEFER, "----");
+  if (r.len > 1 && strcmp(r.events[1].text, "x v0") != 0) fail(test, "\"+&x v0\" body should be \"x v0\"");
+
+  char e[] = "+$v0 a10;";
+  run_parse(test, e, &r);
+  expect_event(test, &r, 1, DEFER, "----");
+  if (r.len > 1 && strcmp(r.events[1].text, "v0 a10") != 0) fail(test, "\"+$v0 a10\" body should be \"v0 a10\"");
+}
 int main(void) {
   test_compact_commands();
   test_strings_and_arrays();
@@ -555,6 +589,7 @@
   test_defer();
   test_defer_space();
   test_defer_space_streams();
+  test_stream_variable_sigil_edges();
   test_variable_provenance();
   test_stream_defer();
   test_arrays_with_variables_and_streams();
```
