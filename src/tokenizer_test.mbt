// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A table with every byte value and a few merges on top, so a sentence costs
/// fewer tokens than its bytes and the reserved tokens sit above the table the
/// way the published encodings put them.
fn specimen() -> @vocab.Ranks raise @refused.Refused {
  let pairs : Array[(Bytes, Int32)] = []
  for b = 0; b < 256; b = b + 1 {
    pairs.push((Bytes::make(1, b.to_byte()), b))
  }
  pairs.push((b"th", 256))
  pairs.push((b"he", 257))
  pairs.push((b"the", 258))
  pairs.push((b" the", 259))
  @vocab.Ranks::from_pairs(pairs)
}

///|
/// Two reserved spellings, one a prefix of the other, at ids the table does not
/// reach.
fn reserved() -> @special.Table {
  @special.Table::of([("<|endoftext|>", 900), ("<|endoftext|>|fim|", 901)])
}

///|
fn specimen_bpe(
  specials : @special.Table,
  policy : @special.Policy,
) -> @moontoken.Tokenizer raise @refused.Refused {
  @moontoken.Tokenizer::byte_bpe(
    ranks=specimen(),
    split=@split.Cl100k,
    specials~,
    policy~,
  )
}

///|
/// Every answer a caller asks of a tokenizer goes through the model it was
/// handed: the count of the vocabulary, the ids, and the bytes of one id.
test "a tokenizer answers through the model it was built on" {
  let tokenizer = @moontoken.Tokenizer::byte_bpe(
    ranks=specimen(),
    split=@split.Cl100k,
  )
  assert_eq(tokenizer.length(), 260)
  assert_eq(tokenizer.encode("the"), [258])
  let bytes = tokenizer.token_bytes(258)
  assert_eq(bytes is Some(b"the"), true)
  assert_eq(tokenizer.token_bytes(5000), None)
}

///|
/// The reserved ids are the model's, not the table's, and the bytes of one is
/// the spelling a reader would write.
test "a reserved token stands for the spelling it is written with" {
  let tokenizer = specimen_bpe(reserved(), Allow)
  assert_eq(tokenizer.token_bytes(900), Some(b"<|endoftext|>"))
  assert_eq(tokenizer.decode([900]), "<|endoftext|>")
  assert_eq(tokenizer.decode([900], reserved=false), "")
}

///|
/// A reserved spelling at either end of the text, and two of them side by side,
/// are the boundary cases of the scan: the text before the first and after the
/// last is still encoded rather than dropped.
test "reserved tokens at the edges leave the text around them encoded" {
  let tokenizer = specimen_bpe(reserved(), Allow)
  assert_eq(tokenizer.encode("<|endoftext|><|endoftext|>"), [900, 900])
  assert_eq(tokenizer.encode("<|endoftext|>a"), [900, 97])
  assert_eq(tokenizer.encode("a<|endoftext|>"), [97, 900])
  assert_eq(tokenizer.encode("a<|endoftext|>b"), [97, 900, 98])
}

///|
/// `count` is the number a caller budgeting a context window wants, so it takes
/// the reserved spellings as tokens even when the tokenizer is built to refuse
/// them: the same text handed to `encode` under that policy is an error.
test "counting takes the reserved tokens as tokens" {
  let tokenizer = specimen_bpe(reserved(), Refuse)
  assert_eq(tokenizer.count("a<|endoftext|>b"), 3)
  assert_eq(tokenizer.encode("a<|endoftext|>b", special=Allow).length(), 3)
  let outcome = Ok(tokenizer.encode("a<|endoftext|>b")) catch {
    err => Err(err)
  }
  assert_eq(outcome is Err(_), true)
}

///|
/// A policy can be replaced on the tokenizer, and the replacement is what the
/// next call uses.
test "the policy a tokenizer carries can be replaced" {
  let refusing = specimen_bpe(reserved(), Refuse)
  let allowing = refusing.with_policy(Allow)
  assert_eq(allowing.encode("<|endoftext|>"), [900])
  assert_eq(allowing.encode("<|endoftext|>|fim|"), [901])
  let unaffected = Ok(refusing.encode("<|endoftext|>")) catch {
    err => Err(err)
  }
  assert_eq(unaffected is Err(_), true)
}

///|
/// `Only` names the spellings that are taken as tokens; the rest are refused
/// with the offset they stand at, which is the half of the policy a caller can
/// act on.
test "only the spellings named are taken as tokens" {
  let tokenizer = specimen_bpe(reserved(), Allow)
  assert_eq(
    tokenizer.encode("<|endoftext|>|fim|", special=Only(["<|endoftext|>|fim|"])),
    [901],
  )
  let outcome = Ok(
    tokenizer.encode("a<|endoftext|>", special=Only(["<|endoftext|>|fim|"])),
  ) catch {
    err => Err(err)
  }
  match outcome {
    Err(@refused.Disallowed(what, at)) => {
      assert_eq(what, "<|endoftext|>")
      assert_eq(at, 1)
    }
    _ => panic()
  }
}

///|
/// A tokenizer with no reserved tokens has nothing to look for, so text that
/// happens to hold a spelling a model reserves is text.
test "a tokenizer without reserved tokens encodes everything as text" {
  let tokenizer = specimen_bpe(@special.Table::empty(), Allow)
  assert_eq(tokenizer.encode("<|endoftext|>").length(), 13)
  assert_eq(tokenizer.encode_ordinary("<|endoftext|>").length(), 13)
}

///|
/// A model that is not one of this library's: it answers the segmentation of
/// the table it wraps with every id moved by a thousand, so a test can tell
/// whether the tokenizer asked the model or worked the answer out itself.
struct Shifted {
  inner : @bpe.ByteBpe
}

///|
fn Shifted::shift(ids : Array[Int32], by : Int32) -> Array[Int32] {
  let out : Array[Int32] = []
  for id in ids {
    out.push(id + by)
  }
  out
}

///|
impl Model for Shifted with fn encode(self, text) {
  Shifted::shift(@bpe.ByteBpe::encode(self.inner, text), 1000)
}

///|
impl Model for Shifted with fn decode_bytes(self, ids) {
  @bpe.ByteBpe::decode_bytes(self.inner, Shifted::shift(ids, -1000))
}

///|
impl Model for Shifted with fn decode(self, ids) {
  @bpe.ByteBpe::decode(self.inner, Shifted::shift(ids, -1000))
}

///|
impl Model for Shifted with fn token_bytes(self, id) {
  @bpe.ByteBpe::token_bytes(self.inner, id - 1000)
}

///|
impl Model for Shifted with fn length(self) {
  @bpe.ByteBpe::length(self.inner)
}

///|
/// The trait is open, and a tokenizer built over a model of the caller's keeps
/// the reserved tokens and the policy while taking every id from the model.
test "a model of one's own is the one the tokenizer asks" {
  let inner = @bpe.ByteBpe::new(ranks=specimen(), split=@split.Cl100k)
  let tokenizer = @moontoken.Tokenizer::new(
    model={ inner, },
    specials=reserved(),
    policy=Allow,
  )
  assert_eq(tokenizer.encode("the"), [1258])
  assert_eq(tokenizer.decode([1258]), "the")
  assert_eq(tokenizer.token_bytes(1258), Some(b"the"))
  assert_eq(tokenizer.length(), 260)
  // The reserved id is the table's own number: the tokenizer reads it from the
  // policy's table and does not ask the model for it.
  assert_eq(tokenizer.encode("a<|endoftext|>"), [1097, 900])
  assert_eq(tokenizer.decode([1097, 900]), "a<|endoftext|>")
}

///|
/// The constructors for the published encodings take the reserved tokens as
/// tokens until told otherwise, which is what a model emitting them expects.
test "a published encoding reserves its own tokens" {
  let tokenizer = @moontoken.Tokenizer::cl100k(ranks=specimen())
  assert_eq(tokenizer.encode("<|endoftext|>"), [100257])
  assert_eq(tokenizer.encode("<|endofprompt|>"), [100276])
  let as_text = tokenizer.encode("<|endoftext|>", special=Ignore)
  assert_eq(as_text.length(), 13)
}

///|
/// Text that is not ASCII survives the round trip: the pieces stand for bytes,
/// so a script the table never merged costs one token a byte and still comes
/// back whole.
test "text comes back the way it went in" {
  let tokenizer = specimen_bpe(reserved(), Allow)
  let text = "the 世界 café 🜁 the"
  let ids = tokenizer.encode(text)
  assert_eq(tokenizer.decode(ids), text)
  assert_eq(tokenizer.decode_bytes(ids), @utf8.encode(text))
  assert_eq(tokenizer.count(text), ids.length())
}

///|
/// An empty text is a valid input with no tokens, not an error and not a
/// special case a caller has to guard.
test "an empty text is no tokens, and back" {
  let tokenizer = specimen_bpe(reserved(), Allow)
  assert_eq(tokenizer.encode(""), [])
  assert_eq(tokenizer.encode_ordinary(""), [])
  assert_eq(tokenizer.count(""), 0)
  assert_eq(tokenizer.decode([]), "")
}

///|
/// An id the vocabulary does not have is refused by number, which is the one
/// error a stream of ids from a different table produces.
test "an id outside the vocabulary is refused by number" {
  let tokenizer = specimen_bpe(reserved(), Allow)
  let outcome = Ok(tokenizer.decode([258, 100000])) catch { err => Err(err) }
  match outcome {
    Err(@refused.Missing(id)) => assert_eq(id, 100000)
    _ => panic()
  }
}

///|
/// The harmony encoding takes its control words as one token each, at the ids
/// the published vocabulary gives them, and gives one back as its spelling.
test "the harmony control words are the ids the encoding reserves" {
  let tokenizer = @moontoken.Tokenizer::o200k_harmony(ranks=specimen())
  assert_eq(tokenizer.encode("<|start|>"), [200006])
  assert_eq(tokenizer.encode("<|reserved_200004|>"), [200004])
  assert_eq(tokenizer.encode("<|start|>user<|message|>"), [
    200006, 117, 115, 101, 114, 200008,
  ])
  assert_eq(tokenizer.token_bytes(200012), Some(b"<|call|>"))
  assert_eq(tokenizer.decode([200006, 200007]), "<|start|><|end|>")
}
