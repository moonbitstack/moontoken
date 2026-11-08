// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Settings that change the work rather than the result.
pub(all) struct Options {
  ///
  /// Remember the tokens of the words already seen. A tokenizer sees the same
  /// words over and over, so the table pays for itself on the second
  /// occurrence, and it never changes a result.
  cache : Bool
  ///
  /// How many words to remember before dropping the whole table. Roughly the
  /// size at which a page of text repeats itself.
  cache_limit : Int32
}

///|
/// The settings a tokenizer starts with: the cache on, at 16384 words.
pub let options : Options = { cache: true, cache_limit: 1 << 14, }

///|
/// A byte-level byte-pair encoder: text is cut into words, each word is taken
/// as UTF-8 bytes, and the merge table turns those bytes into tokens.
///
/// Every byte has a token of its own, which is what makes the encoding total:
/// any text, valid or not, has an encoding of at least one token per byte.
pub struct ByteBpe {
  ranks : @vocab.Ranks
  split : @split.Split
  cache : Map[String, Array[Int32]]
  options : Options
}

///|
/// Builds an encoder over a table of ranks.
///
/// Raises when a single byte has no token, because such a table cannot encode
/// text that happens to contain that byte, and finding out mid-sentence is
/// worse than finding out here.
pub fn ByteBpe::new(
  ranks~ : @vocab.Ranks,
  split~ : @split.Split,
  options~ : Options = options,
) -> ByteBpe raise @refused.Refused {
  let missing = ranks.missing_bytes()
  if !missing.is_empty() {
    raise @refused.Malformed("a single byte has no token", missing[0])
  }
  { ranks, split, cache: Map([]), options, }
}

///|
/// The rank of the bytes between two offsets, or -1 when no merge produced
/// them.
fn ByteBpe::rank_between(
  self : ByteBpe,
  bytes : Bytes,
  start : Int32,
  stop : Int32,
) -> Int32 {
  match self.ranks.get(bytes[start:stop]) {
    Some(rank) => rank
    None => -1
  }
}

///|
/// The token of one span of a word. A span is either one byte, or a run the
/// merge table joined, so a rank is always there; a missing one would mean the
/// table contradicts itself.
fn ByteBpe::id_of_span(
  self : ByteBpe,
  bytes : Bytes,
  start : Int32,
  stop : Int32,
) -> Int32 raise @refused.Refused {
  match self.ranks.get(bytes[start:stop]) {
    Some(rank) => rank
    None => raise @refused.Malformed("a span has no token", start)
  }
}

///|
/// Merges the word into tokens, lowest rank first, which is the order the
/// trainer performed the merges in and therefore the only order that rebuilds
/// the intended segmentation.
fn ByteBpe::merge(
  self : ByteBpe,
  bytes : Bytes,
) -> Array[Int32] raise @refused.Refused {
  let n = bytes.length()
  let starts : Array[Int32] = []
  let pair : Array[Int32] = []
  for i = 0; i < n; i = i + 1 {
    starts.push(i)
    pair.push(if i + 1 < n { self.rank_between(bytes, i, i + 2) } else { -1 })
  }
  starts.push(n)
  pair.push(-1)
  let mut count = n + 1
  while count > 2 {
    let mut best = -1
    let mut at = -1
    for k = 0; k < count - 1; k = k + 1 {
      let rank = pair[k]
      if rank >= 0 && (best < 0 || rank < best) {
        best = rank
        at = k
      }
    }
    if at < 0 {
      break
    }
    ignore(starts.remove(at + 1))
    ignore(pair.remove(at + 1))
    count = count - 1
    // Only the two pairs that touched the merge can have changed.
    if at > 0 {
      pair[at - 1] = self.rank_between(bytes, starts[at - 1], starts[at + 1])
    }
    if at <= count - 3 {
      pair[at] = self.rank_between(bytes, starts[at], starts[at + 2])
    } else {
      pair[at] = -1
    }
  }
  let ids : Array[Int32] = []
  for k = 0; k < count - 1; k = k + 1 {
    ids.push(self.id_of_span(bytes, starts[k], starts[k + 1]))
  }
  ids
}

///|
/// The tokens of one word, from the table when it is there and from the merge
/// otherwise.
fn ByteBpe::word_into(
  self : ByteBpe,
  word : StringView,
  ids : Array[Int32],
) -> Unit raise @refused.Refused {
  if word.is_empty() {
    return
  }
  let bytes = @utf8.encode(word)
  match self.ranks.get(bytes[:]) {
    Some(id) => {
      ids.push(id)
      return
    }
    None => ()
  }
  if self.options.cache {
    match self.cache.get_from_string(word) {
      Some(cached) => {
        for id in cached {
          ids.push(id)
        }
        return
      }
      None => ()
    }
  }
  let merged = self.merge(bytes)
  for id in merged {
    ids.push(id)
  }
  if self.options.cache {
    if self.cache.length() >= self.options.cache_limit {
      self.cache.clear()
    }
    self.cache.set(word.to_owned(), merged)
  }
}

///|
/// The tokens of `text`.
pub fn ByteBpe::encode(
  self : ByteBpe,
  text : StringView,
) -> Array[Int32] raise @refused.Refused {
  let ids : Array[Int32] = []
  for word in self.split.pieces(text) {
    self.word_into(word, ids)
  }
  ids
}

///|
/// The tokens of one word, without cutting it first.
pub fn ByteBpe::encode_word(
  self : ByteBpe,
  word : StringView,
) -> Array[Int32] raise @refused.Refused {
  let ids : Array[Int32] = []
  self.word_into(word, ids)
  ids
}

///|
/// How many tokens the vocabulary has.
pub fn ByteBpe::length(self : ByteBpe) -> Int32 {
  self.ranks.length()
}

///|
/// The bytes one token stands for.
pub fn ByteBpe::token_bytes(self : ByteBpe, id : Int32) -> Bytes? {
  self.ranks.token(id)
}

///|
/// The bytes a list of tokens stands for.
///
/// The result need not be valid UTF-8: a caller that cut a character in half
/// gets the two halves back, which is what makes re-encoding exact.
pub fn ByteBpe::decode_bytes(
  self : ByteBpe,
  ids : ArrayView[Int32],
) -> Bytes raise @refused.Refused {
  let out : Array[Byte] = []
  for id in ids {
    match self.ranks.token(id) {
      Some(bytes) =>
        for i = 0; i < bytes.length(); i = i + 1 {
          out.push(bytes[i])
        }
      None => raise @refused.Missing(id)
    }
  }
  Bytes::from_array(out)
}

///|
/// The text a list of tokens stands for, with U+FFFD standing in for the byte
/// sequences that are not text.
pub fn ByteBpe::decode(
  self : ByteBpe,
  ids : ArrayView[Int32],
) -> String raise @refused.Refused {
  @utf8.decode_lossy(self.decode_bytes(ids)[:])
}
