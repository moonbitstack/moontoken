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

///|
/// The `=` at the end of a base64 group is padding, not content: a table
/// written without it is the same table, and several writers leave it out.
test "a token without its padding is read" {
  let ranks = @vocab.Ranks::from_tiktoken("YQ 0\nYWI 1\n")
  assert_eq(ranks.length(), 2)
  assert_eq(ranks.token(0), Some(b"a"))
  assert_eq(ranks.token(1), Some(b"ab"))
}

///|
/// A table checked out on Windows carries a carriage return before every line
/// feed, and it is not part of the token or of the rank.
test "a table with carriage returns is read" {
  let ranks = @vocab.Ranks::from_tiktoken("YQ== 0\r\nYg== 1\r\n")
  assert_eq(ranks.length(), 2)
  assert_eq(ranks.token(1), Some(b"b"))
}

///|
test "a token that is not base64 is refused" {
  let cases : Array[String] = ["!!!! 0\n", "Y 0\n", "YQ* 0\n"]
  for file in cases {
    let outcome = Ok(@vocab.Ranks::from_tiktoken(file[:])) catch {
      err => Err(err)
    }
    match outcome {
      Ok(_) => fail("a token that is not base64 was read")
      Err(@refused.Malformed(_, at)) => assert_eq(at, 0)
      Err(_) => fail("refused for another reason")
    }
  }
}

///|
test "a rank that is not an integer is refused" {
  let outcome = Ok(@vocab.Ranks::from_tiktoken("YQ== one\n")) catch {
    err => Err(err)
  }
  match outcome {
    Ok(_) => fail("a rank that is not an integer was read")
    Err(@refused.Malformed(_, at)) => assert_eq(at, 0)
    Err(_) => fail("refused for another reason")
  }
}
