// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The mergeable ranks of a byte-level encoding: byte sequences and the order
/// in which the trainer picked them.
///
/// A rank doubles as the token id, which is how the published encodings are
/// numbered, and the reason a table loaded here needs no second index.
pub struct Ranks {
  encoder : Map[Bytes, Int32]
  decoder : Map[Int32, Bytes]
}

///|
/// An empty table.
pub fn Ranks::empty() -> Ranks {
  { encoder: Map([]), decoder: Map([]), }
}

///|
/// A table from tokens and their ranks.
///
/// Raises when one token or one rank appears twice: a table like that has no
/// single answer for an id, and the encodings never contain one.
pub fn Ranks::from_pairs(
  pairs : Array[(Bytes, Int32)],
) -> Ranks raise @refused.Refused {
  let encoder : Map[Bytes, Int32] = Map([])
  let decoder : Map[Int32, Bytes] = Map([])
  for i = 0; i < pairs.length(); i = i + 1 {
    let token = pairs[i].0
    let rank = pairs[i].1
    if token.length() == 0 {
      raise @refused.Malformed("token 0 is empty", i)
    }
    if encoder.contains(token) {
      raise @refused.Malformed("duplicate token", i)
    }
    if decoder.contains(rank) {
      raise @refused.Malformed("duplicate rank", i)
    }
    encoder.set(token, rank)
    decoder.set(rank, token)
  }
  { encoder, decoder, }
}

///|
/// Reads the layout the published encodings ship: one `base64 rank` pair per
/// line, in whatever order.
pub fn Ranks::from_tiktoken(text : StringView) -> Ranks raise @refused.Refused {
  let pairs : Array[(Bytes, Int32)] = []
  let mut offset = 0
  for line in text.split("\n") {
    let at = offset
    offset = offset + line.length() + 1
    let body = if line.has_suffix("\r") {
      line.exact_view(start=0, end=line.length() - 1)
    } else {
      line
    }
    if body.is_empty() {
      continue
    }
    let space = match body.rev_find(" ") {
      Some(i) => i
      None => raise @refused.Malformed("a line is not `base64 rank`", at)
    }
    let token = @base64.decode(body.exact_view(start=0, end=space)) catch {
      _ => raise @refused.Malformed("token is not base64", at)
    }
    let rank = @string.parse_int(
      body.exact_view(start=space + 1, end=body.length()),
    ) catch {
      _ => raise @refused.Malformed("rank is not an integer", at)
    }
    pairs.push((token, rank))
  }
  Ranks::from_pairs(pairs)
}

///|
/// The rank of a token, or `None` when the table does not have it.
pub fn Ranks::get(self : Ranks, token : BytesView) -> Int32? {
  self.encoder.get_from_bytes(token)
}

///|
/// The token of a rank.
pub fn Ranks::token(self : Ranks, rank : Int32) -> Bytes? {
  self.decoder.get(rank)
}

///|
/// How many tokens the table holds.
pub fn Ranks::length(self : Ranks) -> Int32 {
  self.encoder.length()
}

///|
/// The bytes that have no token of their own.
///
/// A byte-level encoding is total over byte strings only when every byte is in
/// the table; without this check an encoding built from a partial table would
/// fail in the middle of a word instead of at the door.
pub fn Ranks::missing_bytes(self : Ranks) -> Array[Int32] {
  let missing : Array[Int32] = []
  for b = 0; b < 256; b = b + 1 {
    let one = Bytes::make(1, b.to_byte())
    if !self.encoder.contains(one) {
      missing.push(b)
    }
  }
  missing
}
