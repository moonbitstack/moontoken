// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How a token's spelling turns back into text.
#derive(Eq)
pub(all) enum Decoding {
  ///
  /// The spelling is the byte-level alphabet, so every character stands for
  /// one byte of the original.
  Alphabet
  ///
  /// The spelling uses U+2581 where the text had a space.
  Marker
  ///
  /// The spelling is the text.
  Plain
}

///|
pub extend Decoding with Eq::{equal, not_equal}

///|
/// A model that merges neighbouring tokens in the order a list of rules gives.
///
/// This is the model a `tokenizer.json` file describes: a vocabulary of
/// spellings, a list of merges, and the order they were learned in. It differs
/// from a byte-level table in that the order is a list rather than a rank, and
/// in that a character the vocabulary lacks is a hole rather than an
/// impossibility.
pub struct WordBpe {
  vocab : Map[String, Int32]
  text_of : Map[Int32, String]
  chars : Map[Char, Int32]
  merges : Map[Int32, Map[Int32, Int32]]
  results : Array[Int32]
  unk_id : Int32
  byte_ids : Array[Int32]
  byte_fallback : Bool
  fuse_unk : Bool
  ignore_merges : Bool
  decoding : Decoding
  normalizer : @normalizer.Normalizer
  split : @split.Split
  alphabet : Array[Char]
  reverse : Map[Int32, Int32]
}

///|
/// Settings of a word-level byte-pair model.
pub(all) struct WordOptions {
  ///
  /// The id of the token that stands in for a character the vocabulary lacks.
  unk_id : Int32
  ///
  /// Whether a character the vocabulary lacks is spelled out as bytes.
  byte_fallback : Bool
  ///
  /// Whether a token chooses the whole word over the merges that would cut it.
  ignore_merges : Bool
}

///|
/// The settings a word-level model starts with: no unknown id, no byte
/// fallback, and merges taken even when a whole word is in the vocabulary.
pub let word_options : WordOptions = {
  unk_id: -1,
  byte_fallback: false,
  ignore_merges: false,
}

///|
/// The alphabet the byte-level version of this model writes its vocabulary in:
/// one character per byte, indexed by the byte.
///
/// The bytes that are printable in Latin-1 keep their own character and the
/// rest are laid out over the code points above U+0100, so that a token never
/// holds a control character or half of a character.
pub fn byte_alphabet() -> Array[Char] {
  let alphabet : Array[Char] = Array::make(256, ' ')
  let mut extra = 0
  for b = 0; b < 256; b = b + 1 {
    if (b >= 0x21 && b <= 0x7E) || (b >= 0xA1 && b <= 0xAC) || b >= 0xAE {
      alphabet[b] = b.unsafe_to_char()
    }
  }
  for b = 0; b < 256; b = b + 1 {
    if !((b >= 0x21 && b <= 0x7E) || (b >= 0xA1 && b <= 0xAC) || b >= 0xAE) {
      alphabet[b] = (256 + extra).unsafe_to_char()
      extra = extra + 1
    }
  }
  alphabet
}

///|
/// Builds a model from a vocabulary and the merges between its tokens.
///
/// `merges` are pairs of spellings in the order the trainer learned them; a
/// merge whose sides are not both in the vocabulary is refused, because the
/// result would be a rule that can never fire.
pub fn WordBpe::new(
  vocab~ : Array[(String, Int32)],
  merges~ : Array[(String, String)],
  options~ : WordOptions = word_options,
  decoding~ : Decoding = Plain,
  normalizer~ : @normalizer.Normalizer = @normalizer.Normalizer::identity(),
  split~ : @split.Split = @split.Whole,
) -> WordBpe raise @refused.Refused {
  let by_text : Map[String, Int32] = Map([])
  let text_of : Map[Int32, String] = Map([])
  let chars : Map[Char, Int32] = Map([])
  let mut size = 0
  for entry in vocab {
    let (text, id) = entry
    if text.is_empty() {
      raise @refused.Malformed("a token is empty", 0)
    }
    by_text.set(text, id)
    text_of.set(id, text)
    let single = text[:].to_array()
    if single.length() == 1 {
      if !chars.contains(single[0]) {
        chars.set(single[0], id)
      }
    }
    if id + 1 > size {
      size = id + 1
    }
  }
  let rules : Map[Int32, Map[Int32, Int32]] = Map([])
  let results : Array[Int32] = []
  for i = 0; i < merges.length(); i = i + 1 {
    let (left, right) = merges[i]
    let left_id = match by_text.get(left) {
      Some(id) => id
      None =>
        raise @refused.Absent("a merge names a token the vocabulary lacks")
    }
    let right_id = match by_text.get(right) {
      Some(id) => id
      None =>
        raise @refused.Absent("a merge names a token the vocabulary lacks")
    }
    let joined = match by_text.get(left + right) {
      Some(id) => id
      None =>
        raise @refused.Absent("a merge names a result the vocabulary lacks")
    }
    let inner = match rules.get(left_id) {
      Some(inner) => inner
      None => {
        let inner : Map[Int32, Int32] = Map([])
        rules.set(left_id, inner)
        inner
      }
    }
    inner.set(right_id, results.length())
    results.push(joined)
  }
  let byte_ids : Array[Int32] = Array::make(256, -1)
  if options.byte_fallback {
    for b = 0; b < 256; b = b + 1 {
      let high = (b >> 4) & 15
      let low = b & 15
      let hex = "0123456789ABCDEF"
      let text = "<0x" + hex[high].to_string() + hex[low].to_string() + ">"
      match by_text.get(text) {
        Some(id) => byte_ids[b] = id
        None =>
          raise @refused.Absent(
            "a byte token is missing while byte fallback is on",
          )
      }
    }
  }
  let alphabet = byte_alphabet()
  let reverse : Map[Int32, Int32] = Map([])
  for b = 0; b < 256; b = b + 1 {
    reverse.set(alphabet[b].to_int(), b)
  }
  {
    vocab: by_text,
    text_of,
    chars,
    merges: rules,
    results,
    unk_id: options.unk_id,
    byte_ids,
    byte_fallback: options.byte_fallback,
    fuse_unk: true,
    ignore_merges: options.ignore_merges,
    decoding,
    normalizer,
    split,
    alphabet,
    reverse,
  }
}

///|
/// How many tokens the vocabulary has.
pub fn WordBpe::length(self : WordBpe) -> Int32 {
  self.vocab.length()
}

///|
/// The spelling of one token.
pub fn WordBpe::token_bytes(self : WordBpe, id : Int32) -> Bytes? {
  match self.text_of.get(id) {
    Some(text) => Some(@utf8.encode(text))
    None => None
  }
}

///|
/// The tokens of one word, before the merges.
///
/// A character the vocabulary has no token for is spelled out in bytes when the
/// model has a byte fallback, and stands in as the unknown token when it has
/// one. A model with neither has nothing to say about that character, which is
/// the one case where encoding fails on text that is otherwise fine.
fn WordBpe::word_ids(
  self : WordBpe,
  word : Bytes,
) -> Array[Int32] raise @refused.Refused {
  let ids : Array[Int32] = []
  if self.decoding == Alphabet {
    for i = 0; i < word.length(); i = i + 1 {
      let b = word[i].to_int() & 0xFF
      match self.chars.get(self.alphabet[b]) {
        Some(id) => ids.push(id)
        None => ids.push(self.id_for_byte(b))
      }
    }
  } else {
    let text = @utf8.decode_lossy(word[:])
    for c in text {
      match self.chars.get(c) {
        Some(id) => ids.push(id)
        None =>
          if self.byte_fallback {
            for byte in @utf8.encode(c.to_string())[:] {
              ids.push(self.id_for_byte(byte.to_int() & 0xFF))
            }
          } else {
            ids.push(self.unknown())
          }
      }
    }
  }
  ids
}

///|
/// The token for one byte: the byte spelling when the model has one, and the
/// unknown token otherwise.
fn WordBpe::id_for_byte(
  self : WordBpe,
  b : Int32,
) -> Int32 raise @refused.Refused {
  if self.byte_fallback {
    let id = self.byte_ids[b]
    if id >= 0 {
      return id
    }
  }
  self.unknown()
}

///|
/// The unknown token, which a model is allowed not to have.
fn WordBpe::unknown(self : WordBpe) -> Int32 raise @refused.Refused {
  if self.unk_id < 0 {
    raise @refused.Absent(
      "a character has no token and the model has no unknown",
    )
  }
  self.unk_id
}

///|
/// The tokens of one word, after the merges.
fn WordBpe::merged(
  self : WordBpe,
  word : Bytes,
) -> Array[Int32] raise @refused.Refused {
  if self.ignore_merges {
    match self.vocab.get(@utf8.decode_lossy(word[:])) {
      Some(id) => return [id]
      None => ()
    }
  }
  let mut ids = self.word_ids(word)
  while ids.length() > 1 {
    let mut best = -1
    let mut best_rank = -1
    for i = 0; i + 1 < ids.length(); i = i + 1 {
      let rank = match self.merges.get(ids[i]) {
        Some(inner) => inner.get(ids[i + 1])
        None => None
      }
      match rank {
        Some(rank) =>
          if best_rank < 0 || rank < best_rank {
            best_rank = rank
            best = i
          }
        None => ()
      }
    }
    if best < 0 {
      break
    }
    let joined = self.results[best_rank]
    let left = ids[best]
    let right = ids[best + 1]
    let next : Array[Int32] = []
    let mut i = 0
    while i < ids.length() {
      if i + 1 < ids.length() && ids[i] == left && ids[i + 1] == right {
        next.push(joined)
        i = i + 2
      } else {
        next.push(ids[i])
        i = i + 1
      }
    }
    ids = next
  }
  if self.fuse_unk && self.unk_id >= 0 {
    let fused : Array[Int32] = []
    for id in ids {
      if id != self.unk_id ||
        fused.is_empty() ||
        fused[fused.length() - 1] != self.unk_id {
        fused.push(id)
      }
    }
    ids = fused
  }
  ids
}

///|
/// The tokens of `text`.
pub fn WordBpe::encode(
  self : WordBpe,
  text : StringView,
) -> Array[Int32] raise @refused.Refused {
  let out : Array[Int32] = []
  for word in self.split.pieces(self.normalizer.apply(text)) {
    for id in self.merged(@utf8.encode(word)) {
      out.push(id)
    }
  }
  out
}

///|
/// The tokens of one word, without cutting it first.
pub fn WordBpe::encode_word(
  self : WordBpe,
  word : StringView,
) -> Array[Int32] raise @refused.Refused {
  self.merged(@utf8.encode(word))
}

///|
/// The bytes a list of tokens stands for.
pub fn WordBpe::decode_bytes(
  self : WordBpe,
  ids : ArrayView[Int32],
) -> Bytes raise @refused.Refused {
  let out : Array[Byte] = []
  for id in ids {
    match self.text_of.get(id) {
      Some(text) =>
        match self.decoding {
          Alphabet =>
            for c in text {
              match self.reverse.get(c.to_int()) {
                Some(b) => out.push(b.to_byte())
                None =>
                  for byte in @utf8.encode(c.to_string())[:] {
                    out.push(byte)
                  }
              }
            }
          Marker =>
            for c in text {
              if c.to_int() == 0x2581 {
                out.push(b' ')
              } else {
                for byte in @utf8.encode(c.to_string())[:] {
                  out.push(byte)
                }
              }
            }
          Plain =>
            for byte in @utf8.encode(text)[:] {
              out.push(byte)
            }
        }
      None => raise @refused.Missing(id)
    }
  }
  Bytes::from_array(out)
}

///|
/// The text a list of tokens stands for.
pub fn WordBpe::decode(
  self : WordBpe,
  ids : ArrayView[Int32],
) -> String raise @refused.Refused {
  @utf8.decode_lossy(self.decode_bytes(ids)[:])
}

///|
/// The tokens of `text`, cut by the pre-tokenizer the file named.
pub fn WordBpe::size(self : WordBpe) -> Int32 {
  self.vocab.length()
}
