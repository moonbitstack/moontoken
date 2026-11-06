// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// `cl100k_base` over the texts of the generated vectors, and back again.
///
/// The vectors come from the reference implementation running the published
/// pattern over the same table, so this pins the merges, the pattern and the
/// ids at once.
test "cl100k_base agrees with the reference vectors" {
  let ranks = @vocab.Ranks::from_tiktoken(cl100k_table()[:])
  let tokenizer = @moontoken.Tokenizer::cl100k(ranks~)
  for vector in cl100k_vectors() {
    let (text, want) = vector
    assert_eq(tokenizer.encode_ordinary(text), want)
    assert_eq(tokenizer.decode(want), text)
  }
}

///|
test "o200k_base agrees with the reference vectors" {
  let ranks = @vocab.Ranks::from_tiktoken(o200k_table()[:])
  let tokenizer = @moontoken.Tokenizer::o200k(ranks~)
  for vector in o200k_vectors() {
    let (text, want) = vector
    assert_eq(tokenizer.encode_ordinary(text), want)
    assert_eq(tokenizer.decode(want), text)
  }
}

///|
/// The texts below hold a reserved token, which the policy around them decides
/// what to do with. The column of ids on the left is the text taken as text;
/// the one on the right is the same text with the reserved spelling taken as a
/// token.
test "reserved tokens follow the policy" {
  let ranks = @vocab.Ranks::from_tiktoken(cl100k_table()[:])
  let specials = @special.Table::of([
    ("<|endoftext|>", 500000),
    ("<|endoftext|>|fim|", 500001),
  ])
  let ordinary = @moontoken.Tokenizer::byte_bpe(
    ranks~,
    split=@split.Cl100k,
    specials~,
    policy=Ignore,
  )
  let allowed = @moontoken.Tokenizer::byte_bpe(
    ranks~,
    split=@split.Cl100k,
    specials~,
    policy=Allow,
  )
  let refused = @moontoken.Tokenizer::byte_bpe(
    ranks~,
    split=@split.Cl100k,
    specials~,
    policy=Refuse,
  )
  for vector in special_cases() {
    let (text, as_text, as_token) = vector
    assert_eq(ordinary.encode(text), as_text)
    assert_eq(allowed.encode(text), as_token)
    assert_eq(allowed.count(text), as_token.length())
  }
  let outcome = Ok(refused.encode("before <|endoftext|> after")) catch {
    err => Err(err)
  }
  match outcome {
    Ok(_) => panic()
    Err(@refused.Disallowed(text, at)) => {
      assert_eq(text, "<|endoftext|>")
      assert_eq(at, 7)
    }
    Err(_) => panic()
  }
}

///|
test "a policy can be overridden for one call" {
  let ranks = @vocab.Ranks::from_tiktoken(cl100k_table()[:])
  let tokenizer = @moontoken.Tokenizer::cl100k(ranks~)
  let with_token = tokenizer.encode("<|endoftext|>", special=Allow)
  let as_text = tokenizer.encode("<|endoftext|>", special=Ignore)
  assert_eq(with_token, [100257])
  assert_true(as_text.length() > 1)
}

///|
/// When one reserved spelling is a prefix of another, the longest one wins.
///
/// The reference implementation joins the spellings into one alternation and
/// takes the first that matches, in an order that comes from a hash map and
/// therefore changes between runs. A tokenizer cannot be defined by that, so
/// the longer spelling is taken here, which is also what keeps a model that
/// reserves both from reading the shorter one out of the middle of the longer.
test "the longest reserved token wins" {
  let ranks = @vocab.Ranks::from_tiktoken(cl100k_table()[:])
  let specials = @special.Table::of([
    ("<|endoftext|>", 500000),
    ("<|endoftext|>|fim|", 500001),
  ])
  let tokenizer = @moontoken.Tokenizer::byte_bpe(
    ranks~,
    split=@split.Cl100k,
    specials~,
    policy=Allow,
  )
  assert_eq(tokenizer.encode("<|endoftext|>|fim|"), [500001])
  assert_eq(tokenizer.encode("<|endoftext|>").length(), 1)
}

///|
test "decoding can drop the reserved tokens" {
  let ranks = @vocab.Ranks::from_tiktoken(cl100k_table()[:])
  let tokenizer = @moontoken.Tokenizer::cl100k(ranks~)
  let ids = tokenizer.encode("a<|endoftext|>b", special=Allow)
  assert_eq(tokenizer.decode(ids), "a<|endoftext|>b")
  assert_eq(tokenizer.decode(ids, reserved=false), "ab")
}
