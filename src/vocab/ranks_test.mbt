// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Two tokens and their ranks, in the layout the published files use.
let table : String = "YQ== 0\nYg== 1\nYWI= 2\n"

///|
test "a table is read in any order" {
  let ranks = @vocab.Ranks::from_tiktoken(table[:])
  assert_eq(ranks.length(), 3)
  assert_eq(ranks.get(b"a"[:]), Some(0))
  assert_eq(ranks.get(b"ab"[:]), Some(2))
  assert_eq(ranks.token(1), Some(b"b"))
  assert_eq(ranks.get(b"z"[:]), None)
  assert_eq(ranks.token(9), None)
}

///|
test "a line that is not a pair is refused" {
  let outcome = Ok(@vocab.Ranks::from_tiktoken("YQ==\n")) catch {
    err => Err(err)
  }
  match outcome {
    Ok(_) => panic()
    Err(@refused.Malformed(_, at)) => assert_eq(at, 0)
    Err(_) => panic()
  }
}

///|
test "a token that appears twice is refused" {
  let outcome = Ok(@vocab.Ranks::from_pairs([(b"a", 0), (b"a", 1)])) catch {
    err => Err(err)
  }
  match outcome {
    Ok(_) => panic()
    Err(@refused.Malformed(_, at)) => assert_eq(at, 1)
    Err(_) => panic()
  }
}

///|
test "a rank that appears twice is refused" {
  let outcome = Ok(@vocab.Ranks::from_pairs([(b"a", 0), (b"b", 0)])) catch {
    err => Err(err)
  }
  match outcome {
    Ok(_) => panic()
    Err(@refused.Malformed(_, at)) => assert_eq(at, 1)
    Err(_) => panic()
  }
}

///|
test "the bytes a table lacks are named" {
  let ranks = @vocab.Ranks::from_pairs([(b"a", 0), (b"b", 1)])
  let missing = ranks.missing_bytes()
  assert_eq(missing.length(), 254)
  assert_false(missing.contains(97))
  assert_true(missing.contains(0))
}
