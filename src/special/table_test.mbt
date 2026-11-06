// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "a table holds its tokens by spelling and by id" {
  let table = @special.Table::of([("<|endoftext|>", 7), ("<|pad|>", 8)])
  assert_eq(table.length(), 2)
  assert_eq(table.id("<|endoftext|>"[:]), Some(7))
  assert_eq(table.id("<|missing|>"[:]), None)
  assert_eq(table.text(8), Some("<|pad|>"))
  assert_eq(table.text(9), None)
}

///|
test "a spelling that appears twice keeps the first id" {
  let table = @special.Table::of([("<|a|>", 1), ("<|a|>", 2)])
  assert_eq(table.length(), 1)
  assert_eq(table.id("<|a|>"[:]), Some(1))
}

///|
test "the longest spelling at a position is found" {
  let table = @special.Table::of([("<|a|>", 1), ("<|a|><|b|>", 2)])
  let hit = table.find("x<|a|><|b|>y"[:], 0)
  match hit {
    Some(hit) => {
      assert_eq(hit.start, 1)
      assert_eq(hit.id, 2)
      assert_eq(hit.text, "<|a|><|b|>")
    }
    None => panic()
  }
  assert_true(table.find("nothing here"[:], 0) is None)
}

///|
test "a policy decides what a spelling may be" {
  assert_true(@special.Allow.allows("<|a|>"[:]))
  assert_false(@special.Refuse.allows("<|a|>"[:]))
  assert_false(@special.Ignore.allows("<|a|>"[:]))
  assert_true(@special.Only(["<|a|>"]).allows("<|a|>"[:]))
  assert_false(@special.Only(["<|a|>"]).allows("<|b|>"[:]))
  assert_false(@special.Ignore.recognizes())
  assert_true(@special.Allow.recognizes())
}

///|
test "the published encodings reserve the tokens they document" {
  assert_eq(@special.cl100k_base().id("<|endoftext|>"[:]), Some(100257))
  assert_eq(@special.cl100k_base().id("<|fim_prefix|>"[:]), Some(100258))
  assert_eq(@special.o200k_base().id("<|endoftext|>"[:]), Some(199999))
  assert_eq(@special.r50k_base().id("<|endoftext|>"[:]), Some(50256))
  assert_eq(@special.p50k_edit().id("<|fim_suffix|>"[:]), Some(50283))
  assert_eq(@special.o200k_base().length(), 2)
}

///|
/// A search that walked by code unit would stop inside the surrogate pair of a
/// character outside the basic plane, and a slice that ended there would be
/// refused. The spelling is looked for at every code point instead, so the
/// text after the token can be anything.
test "a token before a character outside the basic plane is found" {
  let table = @special.Table::of([("<|endoftext|>", 7)])
  let text = "0<|endoftext|>\u{1F1E6}"
  match table.find(text[:], 0) {
    Some(hit) => {
      assert_eq(hit.start, 1)
      assert_eq(hit.id, 7)
    }
    None => panic()
  }
  // The same with the token first, last, and twice.
  assert_true(table.find("\u{1F1E6}<|endoftext|>"[:], 0) is Some(_))
  assert_true(table.find("<|endoftext|>\u{1F600}"[:], 0) is Some(_))
  assert_true(
    table.find("<|endoftext|>\u{1F1E6}<|endoftext|>"[:], 14) is Some(_),
  )
}
