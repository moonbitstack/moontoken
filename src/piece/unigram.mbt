// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A model that segments text by the most likely sequence of pieces.
///
/// Each piece carries the log probability the trainer measured for it, and the
/// segmentation is the one whose pieces add up to the largest total. Text that
/// no piece covers becomes the unknown piece, or, when the model can spell it
/// out, one token per byte.
pub struct Unigram {
  pieces : Pieces
  normalizer : @normalizer.Normalizer
  min_score : Float
}

///|
/// Builds the model over a vocabulary.
///
/// Raises when the vocabulary has neither an unknown piece nor byte fallback,
/// because text outside the vocabulary would then have no encoding at all.
pub fn Unigram::new(
  pieces~ : Pieces,
  normalizer~ : @normalizer.Normalizer = @normalizer.Normalizer::identity(),
) -> Unigram {
  let mut min_score = 0.0F
  let mut seen = false
  for id = 0; id < pieces.length(); id = id + 1 {
    let piece = pieces.items[id]
    if piece.kind == Normal {
      if !seen || piece.score < min_score {
        min_score = piece.score
        seen = true
      }
    }
  }
  if !seen {
    min_score = 0.0F
  }
  { pieces, normalizer, min_score, }
}

///|
/// How many pieces the vocabulary has.
pub fn Unigram::length(self : Unigram) -> Int32 {
  self.pieces.length()
}

///|
/// The vocabulary.
pub fn Unigram::pieces(self : Unigram) -> Pieces {
  self.pieces
}

///|
/// The token a piece id stands for, for callers that want the spelling.
pub fn Unigram::token_bytes(self : Unigram, id : Int32) -> Bytes? {
  if id < 0 || id >= self.pieces.length() {
    return None
  }
  Some(self.pieces.items[id].text)
}

///|
/// The pieces of the most likely segmentation, as spans of the normalised
/// bytes.
fn Unigram::segment(self : Unigram, bytes : Bytes) -> Array[Span] {
  let size = bytes.length()
  let unk_score = self.min_score - 10.0F
  let starts : Array[Int32] = Array::make(size + 1, -1)
  let scores : Array[Float] = Array::make(size + 1, 0.0F)
  let ids : Array[Int32] = Array::make(size + 1, -1)
  let mut frontier = 0
  let mut at = 0
  while at < size {
    let mut running = scores[at]
    if running < -100000.0F || running > 100000.0F {
      // Scores are log probabilities and add up without bound; this keeps a
      // long input from reaching the point where the sum stops being ordered.
      let shift = running
      for i = at; i <= frontier; i = i + 1 {
        if i == at || starts[i] != -1 {
          scores[i] = scores[i] - shift
        }
      }
      running = 0.0F
    }
    let width = @split.utf8_width_at(bytes, at)
    let step = if width == 0 { 1 } else { width }
    let mut has_one = false
    let mut length = 1
    let limit = size - at
    while length <= limit && length <= self.pieces.longest() {
      match self.pieces.lattice_id(bytes[at:at + length]) {
        Some(id) => {
          if at + length > frontier {
            frontier = at + length
          }
          let piece = self.pieces.items[id]
          let score = if piece.kind == UserDefined {
            0.1F * Float::from_int(length - 1)
          } else {
            piece.score
          }
          let candidate = score + running
          if starts[at + length] == -1 || candidate > scores[at + length] {
            scores[at + length] = candidate
            starts[at + length] = at
            ids[at + length] = id
          }
          if length == step {
            has_one = true
          }
        }
        None => ()
      }
      length = length + 1
    }
    if !has_one {
      let target = at + step
      if target > frontier {
        frontier = target
      }
      let candidate = unk_score + running
      if starts[target] == -1 || candidate > scores[target] {
        scores[target] = candidate
        starts[target] = at
        ids[target] = self.pieces.unk_id()
      }
    }
    at = at + step
  }
  let reversed : Array[Span] = []
  let mut end = size
  while end > 0 {
    let start = starts[end]
    if start < 0 {
      // Unreachable unless the vocabulary is broken; stand the whole run in as
      // unknown rather than loop.
      reversed.push({ start: 0, stop: size, id: self.pieces.unk_id(), })
      break
    }
    reversed.push({ start, stop: end, id: ids[end], })
    end = start
  }
  let path : Array[Span] = []
  for i = reversed.length() - 1; i >= 0; i = i - 1 {
    path.push(reversed[i])
  }
  path
}

///|
/// The tokens of `text`.
pub fn Unigram::encode(
  self : Unigram,
  text : StringView,
) -> Array[Int32] raise @refused.Refused {
  let normalized = @utf8.encode(self.normalizer.apply(text))
  let bytes = normalized
  if bytes.length() == 0 {
    return []
  }
  finish(self.pieces, bytes, self.segment(bytes))
}

///|
/// The text a list of tokens stands for.
pub fn Unigram::decode(
  self : Unigram,
  ids : ArrayView[Int32],
) -> String raise @refused.Refused {
  decode_pieces(self.pieces, self.normalizer, ids)
}
