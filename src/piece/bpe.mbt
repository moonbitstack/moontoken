// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One pair of neighbouring symbols waiting to be merged, with the score of
/// the piece they would form.
priv struct Pair {
  score : Float
  left : Int32
  right : Int32
  size : Int32
}

///|
/// The order the merges happen in: the highest score first, and on a tie the
/// pair further left, which is what makes the result independent of the order
/// the vocabulary was written in.
fn Pair::before(a : Pair, b : Pair) -> Bool {
  a.score < b.score || (a.score == b.score && a.left > b.left)
}

///|
fn heap_push(heap : Array[Pair], item : Pair) -> Unit {
  heap.push(item)
  let mut i = heap.length() - 1
  while i > 0 {
    let parent = (i - 1) / 2
    if Pair::before(heap[parent], heap[i]) {
      let swap = heap[parent]
      heap[parent] = heap[i]
      heap[i] = swap
      i = parent
    } else {
      break
    }
  }
}

///|
fn heap_pop(heap : Array[Pair]) -> Pair? {
  if heap.is_empty() {
    return None
  }
  let top = heap[0]
  let last = heap.pop().unwrap()
  if heap.is_empty() {
    return Some(top)
  }
  heap[0] = last
  let mut i = 0
  let n = heap.length()
  while true {
    let l = i * 2 + 1
    let r = l + 1
    let mut biggest = i
    if l < n && Pair::before(heap[biggest], heap[l]) {
      biggest = l
    }
    if r < n && Pair::before(heap[biggest], heap[r]) {
      biggest = r
    }
    if biggest == i {
      break
    }
    let swap = heap[biggest]
    heap[biggest] = heap[i]
    heap[i] = swap
    i = biggest
  }
  Some(top)
}

///|
/// A model that segments text by merging neighbouring symbols, the
/// sentence-piece flavour: symbols are merged in order of the score of the
/// piece they would form, until no merge is left that the vocabulary has.
pub struct PieceBpe {
  pieces : Pieces
  normalizer : @normalizer.Normalizer
  user_defined : Map[Int32, Array[Bytes]]
}

///|
/// A BPE SentencePiece model over a vocabulary: `pieces` in vocabulary order,
/// `normalizer` for the text before it is cut, and the user-defined symbols
/// that the file reserves.
pub fn PieceBpe::new(
  pieces~ : Pieces,
  normalizer~ : @normalizer.Normalizer = @normalizer.Normalizer::identity(),
  user_defined~ : Array[Bytes] = [],
) -> PieceBpe {
  { pieces, normalizer, user_defined: @normalizer.user_index(user_defined), }
}

///|
/// How many pieces the vocabulary has.
pub fn PieceBpe::length(self : PieceBpe) -> Int32 {
  self.pieces.length()
}

///|
/// The vocabulary.
pub fn PieceBpe::pieces(self : PieceBpe) -> Pieces {
  self.pieces
}

///|
/// The token a piece id stands for.
pub fn PieceBpe::token_bytes(self : PieceBpe, id : Int32) -> Bytes? {
  if id < 0 || id >= self.pieces.length() {
    return None
  }
  Some(self.pieces.items[id].text)
}

///|
/// The pieces of `text`, as spans of the normalised bytes.
fn PieceBpe::segment(
  self : PieceBpe,
  bytes : Bytes,
) -> Array[Span] raise @refused.Refused {
  let size = bytes.length()
  let beg : Array[Int32] = []
  let end : Array[Int32] = []
  let frozen : Array[Bool] = []
  let alive : Array[Bool] = []
  let mut at = 0
  while at < size {
    let reserved = @normalizer.longest_reserved(self.user_defined, bytes, at)
    let width = match reserved {
      Some(width) => width
      None => {
        let width = @split.utf8_width_at(bytes, at)
        if width == 0 {
          1
        } else {
          width
        }
      }
    }
    beg.push(at)
    end.push(at + width)
    frozen.push(reserved is Some(_))
    alive.push(true)
    at = at + width
  }
  let count = beg.length()
  let prev : Array[Int32] = []
  let next : Array[Int32] = []
  for i = 0; i < count; i = i + 1 {
    prev.push(i - 1)
    next.push(if i + 1 < count { i + 1 } else { -1 })
  }
  let reversed : Map[Bytes, (Bytes, Bytes)] = Map([])
  let heap : Array[Pair] = []
  let try_pair = fn(left : Int32, right : Int32) {
    if left < 0 || right < 0 || frozen[left] || frozen[right] {
      return
    }
    let start = beg[left]
    let stop = end[right]
    match self.pieces.id(bytes[start:stop]) {
      Some(id) => {
        let kind = self.pieces.items[id].kind
        if id == self.pieces.unk_id() {
          return
        }
        if kind != Normal && kind != UserDefined && kind != Unused {
          return
        }
        heap_push(heap, {
          score: self.pieces.items[id].score,
          left,
          right,
          size: stop - start,
        })
        if kind == Unused {
          let left_text = bytes[beg[left]:end[left]].to_owned()
          let right_text = bytes[beg[right]:end[right]].to_owned()
          reversed.set(bytes[start:stop].to_owned(), (left_text, right_text))
        }
      }
      None => ()
    }
  }
  for i = 0; i + 1 < count; i = i + 1 {
    try_pair(i, i + 1)
  }
  while !heap.is_empty() {
    let pair = heap_pop(heap).unwrap()
    let left = pair.left
    let right = pair.right
    if !alive[left] ||
      !alive[right] ||
      end[left] - beg[left] + (end[right] - beg[right]) != pair.size {
      continue
    }
    end[left] = end[right]
    next[left] = next[right]
    if next[right] >= 0 {
      prev[next[right]] = left
    }
    alive[right] = false
    try_pair(prev[left], left)
    try_pair(left, next[left])
  }
  let spans : Array[Span] = []
  let mut i = 0
  while i >= 0 && i < count {
    if alive[i] {
      self.resegment(bytes, beg[i], end[i], reversed, spans, 0)
    }
    i = next[i]
  }
  spans
}

///|
/// Turns one merged symbol into tokens, splitting again the pieces the
/// trainer kept but never produces.
fn PieceBpe::resegment(
  self : PieceBpe,
  bytes : Bytes,
  start : Int32,
  stop : Int32,
  reversed : Map[Bytes, (Bytes, Bytes)],
  out : Array[Span],
  depth : Int32,
) -> Unit raise @refused.Refused {
  if depth > 100 {
    out.push({ start, stop, id: self.pieces.unk_id(), })
    return
  }
  let text = bytes[start:stop]
  match self.pieces.id(text) {
    Some(id) => {
      let kind = self.pieces.items[id].kind
      if id == self.pieces.unk_id() ||
        (kind != Normal && kind != UserDefined && kind != Unused) {
        out.push({ start, stop, id: self.pieces.unk_id(), })
        return
      }
      if kind != Unused {
        out.push({ start, stop, id, })
        return
      }
      match reversed.get_from_bytes(text) {
        Some(pair) => {
          let (left, _right) = pair
          self.resegment(
            bytes,
            start,
            start + left.length(),
            reversed,
            out,
            depth + 1,
          )
          self.resegment(
            bytes,
            start + left.length(),
            stop,
            reversed,
            out,
            depth + 1,
          )
        }
        None => out.push({ start, stop, id: self.pieces.unk_id(), })
      }
    }
    None => out.push({ start, stop, id: self.pieces.unk_id(), })
  }
}

///|
/// The tokens of `text`.
pub fn PieceBpe::encode(
  self : PieceBpe,
  text : StringView,
) -> Array[Int32] raise @refused.Refused {
  let bytes = @utf8.encode(self.normalizer.apply(text))
  if bytes.length() == 0 {
    return []
  }
  finish(self.pieces, bytes, self.segment(bytes))
}

///|
/// The text a list of tokens stands for.
pub fn PieceBpe::decode(
  self : PieceBpe,
  ids : ArrayView[Int32],
) -> String raise @refused.Refused {
  decode_pieces(self.pieces, self.normalizer, ids)
}
