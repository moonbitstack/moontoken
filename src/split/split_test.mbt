// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The words the published patterns cut a text into, as the reference
/// implementation of the patterns cuts them.
test "the pre-tokenizers agree with the reference" {
  let samples = [
    ("hello world", ["hello", " world"]),
    ("  two  spaces ", [" ", " two", " ", " spaces", " "]),
    ("don't", ["don", "'t"]),
    ("DON'T", ["DON", "'T"]),
    ("3.14", ["3", ".", "14"]),
    ("\n\n", ["\n\n"]),
    ("tab\there", ["tab", "\there"]),
  ]
  for sample in samples {
    let (text, pieces) = sample
    let cut = @split.Cl100k.pieces(text)
    let got : Array[String] = []
    for piece in cut {
      got.push(piece.to_owned())
    }
    assert_eq(got, pieces)
  }
}

///|
test "a pre-tokenizer keeps every byte" {
  for rule in [@split.Cl100k, @split.O200k, @split.Gpt2, @split.Whole] {
    let text = "  mixed 中文 and English, 123!  \n\tend  "
    let joined = StringBuilder()
    for piece in rule.pieces(text) {
      joined.write_string(piece.to_owned())
    }
    assert_eq(joined.to_string(), text)
  }
}

///|
test "whitespace is dropped by the whitespace rule" {
  let pieces = @split.Whitespace.pieces("  a  b  ")
  let got : Array[String] = []
  for piece in pieces {
    got.push(piece.to_owned())
  }
  assert_eq(got, ["a", "b"])
}

///|
test "a word starts at every marker" {
  let pieces = @split.Metaspace.pieces("\u{2581}one\u{2581}two")
  let got : Array[String] = []
  for piece in pieces {
    got.push(piece.to_owned())
  }
  assert_eq(got, ["\u{2581}one", "\u{2581}two"])
}
