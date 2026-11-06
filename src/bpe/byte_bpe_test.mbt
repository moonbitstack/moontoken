// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A table with every byte, and three merges that build `abc` from `a` and
/// `bc`, in an order that is not the order the bytes appear in.
fn table() -> @vocab.Ranks raise @refused.Refused {
  let pairs : Array[(Bytes, Int32)] = []
  for b = 0; b < 256; b = b + 1 {
    pairs.push((Bytes::make(1, b.to_byte()), b))
  }
  pairs.push((b"ab", 300))
  pairs.push((b"bc", 301))
  pairs.push((b"abc", 302))
  @vocab.Ranks::from_pairs(pairs)
}

///|
test "the lowest rank merges first" {
  let encoder = @bpe.ByteBpe::new(ranks=table(), split=@split.Whole)
  assert_eq(encoder.encode("abc"), [302])
  assert_eq(encoder.encode_word("abc"), [302])
}

///|
/// A merge that only becomes available after another one has happened is the
/// case a tokenizer gets wrong when it merges a whole pass at a time.
test "a merge continues from the one before it" {
  let pairs : Array[(Bytes, Int32)] = []
  for b = 0; b < 256; b = b + 1 {
    pairs.push((Bytes::make(1, b.to_byte()), b))
  }
  pairs.push((b"ab", 400))
  pairs.push((b"abc", 401))
  pairs.push((b"bc", 399))
  let encoder = @bpe.ByteBpe::new(
    ranks=@vocab.Ranks::from_pairs(pairs),
    split=@split.Whole,
  )
  // `bc` is merged first, and the pair `a` + `bc` is then looked up again: a
  // merge that only exists after another one still happens.
  assert_eq(encoder.encode("abc"), [401])
}

///|
test "the cache does not change the answer" {
  let ranks = table()
  let cached = @bpe.ByteBpe::new(ranks~, split=@split.Cl100k)
  let plain = @bpe.ByteBpe::new(ranks~, split=@split.Cl100k, options={
    cache: false,
    cache_limit: 0,
  })
  for text in ["hello world", "hello world", "abc abc abc", "中文 abc", ""] {
    assert_eq(cached.encode(text), plain.encode(text))
  }
}

///|
test "a byte that has no token is refused at the door" {
  let outcome = Ok(
    @bpe.ByteBpe::new(
      ranks=@vocab.Ranks::from_pairs([(b"a", 0)]),
      split=@split.Whole,
    ),
  ) catch {
    err => Err(err)
  }
  match outcome {
    Ok(_) => panic()
    Err(@refused.Malformed(_, at)) => assert_eq(at, 0)
    Err(_) => panic()
  }
}

///|
test "decoding gives back the bytes, even the ones that are not text" {
  let encoder = @bpe.ByteBpe::new(ranks=table(), split=@split.Whole)
  let ids = encoder.encode("a\u{00E9}b")
  assert_eq(encoder.decode(ids), "a\u{00E9}b")
  // An id outside the table has no bytes, and says so.
  let outcome = Ok(encoder.decode_bytes([100000])) catch { err => Err(err) }
  match outcome {
    Ok(_) => panic()
    Err(@refused.Missing(id)) => assert_eq(id, 100000)
    Err(_) => panic()
  }
}

///|
test "a word that is one token is not merged again" {
  let pairs : Array[(Bytes, Int32)] = []
  for b = 0; b < 256; b = b + 1 {
    pairs.push((Bytes::make(1, b.to_byte()), b))
  }
  pairs.push((b"ab", 300))
  pairs.push((b"abab", 299))
  let encoder = @bpe.ByteBpe::new(
    ranks=@vocab.Ranks::from_pairs(pairs),
    split=@split.Whole,
  )
  assert_eq(encoder.encode("abab"), [299])
  assert_eq(encoder.encode("ababab"), [299, 300])
}
