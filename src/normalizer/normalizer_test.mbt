// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "identity leaves the text alone" {
  let normalizer = @normalizer.Normalizer::identity()
  assert_eq(
    normalizer.apply("  Mixed  text \u{00E9}  "),
    "  Mixed  text \u{00E9}  ",
  )
  assert_false(normalizer.strips_leading_marker())
}

///|
test "a chain applies its steps in order" {
  let normalizer = @normalizer.Normalizer::chain([
    @normalizer.Nfkc,
    @normalizer.Lowercase,
    @normalizer.Prepend("> "),
    @normalizer.Replace("ab", "x"),
    @normalizer.Trim,
  ])
  assert_eq(normalizer.apply("  \u{FF21}\u{FF22}  "), ">   x")
}

///|
test "the pad step respects a text that already starts with it" {
  let padded = @normalizer.Normalizer::chain([
    @normalizer.Pad(" "),
    @normalizer.Pad(" "),
  ])
  assert_eq(padded.apply("word"), " word")
  assert_eq(padded.apply(" word"), " word")
}

///|
test "escaping a space writes the marker pieces use" {
  let escaped = @normalizer.Normalizer::chain([@normalizer.EscapeSpace])
  assert_eq(escaped.apply("a b"), "a\u{2581}b")
  assert_true(escaped.strips_leading_marker())
}
