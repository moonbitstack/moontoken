// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The model file, as the reader takes it.
fn model_of(text : String) -> @moontoken.Tokenizer raise @refused.Refused {
  let bytes = @base64.decode(text, whitespace=true) catch {
    _ => raise @refused.Malformed("the model is not base64", 0)
  }
  @moontoken.Tokenizer::of_proto(bytes)
}

///|
/// A unigram vocabulary, with the rule table that replaces a handful of
/// characters before segmentation, byte fallback for the rest, and two symbols
/// the caller reserved.
test "a unigram model agrees with the reference vectors" {
  let tokenizer = model_of(unigram_model())
  for vector in unigram_encoded() {
    let (text, want) = vector
    assert_eq(tokenizer.encode_ordinary(text), want)
  }
  for case in unigram_decoded() {
    let (ids, want) = case
    assert_eq(tokenizer.decode(ids), want)
  }
}

///|
test "a sentence-piece merge model agrees with the reference vectors" {
  let tokenizer = model_of(merges_model())
  for vector in merges_encoded() {
    let (text, want) = vector
    assert_eq(tokenizer.encode_ordinary(text), want)
  }
  for case in merges_decoded() {
    let (ids, want) = case
    assert_eq(tokenizer.decode(ids), want)
  }
}

///|
/// The same vocabulary with the dummy prefix and the whitespace folding turned
/// off, which is a different model as far as a caller is concerned.
test "a model that keeps whitespace agrees with the reference vectors" {
  let tokenizer = model_of(spaces_model())
  for vector in spaces_encoded() {
    let (text, want) = vector
    assert_eq(tokenizer.encode_ordinary(text), want)
  }
  for case in spaces_decoded() {
    let (ids, want) = case
    assert_eq(tokenizer.decode(ids), want)
  }
}

///|
test "the pieces of a model are readable" {
  let tokenizer = model_of(unigram_model())
  assert_true(tokenizer.length() > 300)
  let bytes = tokenizer.token_bytes(0)
  assert_true(bytes is Some(_))
  assert_true(tokenizer.token_bytes(100000) is None)
}

///|
test "a model file that is not one is refused" {
  let outcome = Ok(@moontoken.Tokenizer::of_proto(b"\x08\x01\x12\x03abc")) catch {
    err => Err(err)
  }
  match outcome {
    Ok(_) => panic()
    Err(_) => ()
  }
}

///|
/// What a round trip gives back when the model folds whitespace: the words are
/// the same ones, and the spaces between them are the ones the model kept. The
/// leading and trailing runs go, which is the whole point of the folding, and
/// is what the reference does with the same text.
test "a model that folds whitespace does not give back the edges" {
  let tokenizer = model_of(unigram_model())
  for
    case in [
      ("  inside  ", "inside"),
      (" ", ""),
      ("\u{3000}x", "x"),
      ("a  b", "a b"),
      ("\n\n", "\n\n"),
    ] {
    let (text, want) = case
    assert_eq(tokenizer.decode(tokenizer.encode_ordinary(text)), want)
  }
}

///|
/// A reserved symbol is taken whole, and what follows it may be a character
/// outside the basic plane, which is two code units wide.
test "a reserved symbol before a character outside the basic plane" {
  let tokenizer = model_of(unigram_model())
  let text = "<SPECIAL>\u{1F1E6}"
  let ids = tokenizer.encode(text)
  assert_eq(ids[1], 3)
  assert_eq(tokenizer.decode(ids), text)
}
