// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A tokenizer file small enough to read: four letters, four merges, and a
/// byte-level cut, which is the shape a `tokenizer.json` for a byte-level
/// model has.
fn byte_level_file() -> String {
  let text =
    #|{
    #|  "model": {
    #|    "type": "BPE",
    #|    "vocab": {"h": 0, "e": 1, "l": 2, "o": 3, "he": 4, "hel": 5, "hell": 6, "hello": 7},
    #|    "merges": ["h e", "he l", "hel l", "hell o"]
    #|  },
    #|  "pre_tokenizer": {"type": "ByteLevel", "add_prefix_space": false},
    #|  "decoder": {"type": "ByteLevel"}
    #|}
  text
}

///|
/// The same model as an object, parsed.
fn byte_level() -> @moontoken.Tokenizer raise @refused.Refused {
  @moontoken.Tokenizer::parse(byte_level_file()[:])
}

///|
fn two_hex(b : Int32) -> String {
  let digits = "0123456789ABCDEF"
  let out = StringBuilder()
  out.write_char(digits[(b >> 4) & 15].unsafe_to_char())
  out.write_char(digits[b & 15].unsafe_to_char())
  out.to_string()
}

///|
/// A unigram file whose vocabulary holds a few pieces and the 256 byte
/// spellings a model with byte fallback carries, so that text outside the
/// vocabulary still has a spelling.
fn byte_fallback_file() -> String {
  let vocab = StringBuilder()
  vocab.write_string("[\"<unk>\", 0], [\"\u{2581}\", -1], [\"a\", -2]")
  for b = 0; b < 256; b = b + 1 {
    vocab.write_string(
      ", [\"<0x" + two_hex(b) + ">\", " + (-20 - b).to_string() + "]",
    )
  }
  let head =
    #|{
    #|  "model": {
    #|    "type": "Unigram",
    #|    "unk_id": 0,
    #|    "byte_fallback": true,
    #|    "fuse_unk": true,
    #|    "vocab":
  let tail =
    #|  },
    #|  "pre_tokenizer": {"type": "Metaspace", "replacement": "\u2581", "prepend_scheme": "always"},
    #|  "added_tokens": [{"id": 300, "content": "<|end|>"}]
    #|}
  head + "[" + vocab.to_string() + "]" + tail
}

///|
fn byte_fallback() -> @moontoken.Tokenizer raise @refused.Refused {
  @moontoken.Tokenizer::parse(byte_fallback_file()[:])
}

///|
test "a byte-level file reads, encodes and decodes" {
  let tokenizer = byte_level()
  assert_eq(tokenizer.length(), 8)
  assert_eq(tokenizer.encode("hello"), [7])
  // `h` and `e` merge before `hel` exists, and the merge that needs the result
  // still happens after it.
  // `p` has no token and this model has no byte fallback, so the word has no
  // spelling at all.
  let outcome = Ok(tokenizer.encode("help")) catch { err => Err(err) }
  assert_true(outcome is Err(_))
  assert_eq(tokenizer.decode([7]), "hello")
  assert_eq(tokenizer.decode([4, 2, 2, 3]), "hello")
}

///|
test "the cut the file names is the cut that runs" {
  // With `use_regex` off the whole text is one word, so `hellohello` merges
  // only as far as the vocabulary allows.
  let file = byte_level_file().replace(
    old="\"add_prefix_space\": false",
    new="\"add_prefix_space\": false, \"use_regex\": false",
  )
  let tokenizer = @moontoken.Tokenizer::parse(file[:])
  assert_eq(tokenizer.encode("hellohello"), [7, 7])
}

///|
test "a reserved token in the file is taken whole" {
  let tokenizer = byte_fallback()
  assert_eq(tokenizer.encode("<|end|>"), [300])
  assert_eq(tokenizer.decode([300]), "<|end|>")
}

///|
/// A character the vocabulary has no piece for is spelled out in bytes, which
/// is the whole point of the byte fallback: the text survives the round trip
/// even though nothing in the vocabulary stands for it.
test "byte fallback spells out what the vocabulary does not have" {
  let tokenizer = byte_fallback()
  let ids = tokenizer.encode("\u{1F600}")
  // The cut puts a word-break marker in front, and the four bytes follow it.
  assert_eq(ids.length(), 5)
  assert_eq(ids[0], 1)
  for i = 1; i < ids.length(); i = i + 1 {
    assert_true(ids[i] >= 3 && ids[i] < 259)
  }
  assert_eq(tokenizer.decode(ids), "\u{1F600}")
  // `a` has a piece of its own, so it is one token and not a byte, and the
  // marker the cut puts in front is the other.
  assert_eq(tokenizer.encode("a"), [1, 2])
}

///|
test "a file this reader cannot read is refused by name" {
  let cases = [
    ("{}", "a tokenizer file with no model"),
    ("{\"model\": {}}", "a model with no type"),
    ("{\"model\": {\"type\": \"BPE\"}}", "a model with no vocabulary"),
    (
      "{\"model\": {\"type\": \"WordPiece\", \"vocab\": {}}}", "the model WordPiece",
    ),
    (
      "{\"model\": {\"type\": \"BPE\", \"vocab\": {}}, \"pre_tokenizer\": {\"type\": \"Split\"}}",
      "the pre-tokenizer Split",
    ),
  ]
  for case in cases {
    let (file, want) = case
    let outcome = Ok(@moontoken.Tokenizer::parse(file[:])) catch {
      err => Err(err)
    }
    match outcome {
      Ok(_) => fail("a file that should have been refused was read")
      Err(@refused.Absent(what)) => assert_eq(what, want)
      Err(@refused.Unsupported(what)) => assert_eq(what, want)
      Err(_) => fail("refused for another reason than \{want}")
    }
  }
}

///|
/// A byte-level model has no piece for a character outside the alphabet it
/// writes, and with no byte fallback there is nothing to say about it.
test "a word with no spelling at all is refused" {
  let tokenizer = byte_level()
  let outcome = Ok(tokenizer.encode("\u{4E2D}")) catch { err => Err(err) }
  match outcome {
    Ok(_) => fail("a character with no token was encoded")
    Err(@refused.Absent(what)) =>
      assert_eq(what, "a character has no token and the model has no unknown")
    Err(_) => fail("refused for another reason")
  }
}
