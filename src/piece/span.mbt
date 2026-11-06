// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What segmentation produced, before the tokens a model reserves are dealt
/// with: a span of the normalised bytes and the piece that covers it.
pub struct Span {
  start : Int32
  stop : Int32
  id : Int32
}

///|
/// The tokens of a segmentation.
///
/// A control piece stands for itself, a character with no piece is spelled out
/// as bytes when the model can do that, and a run of unknown text becomes one
/// token rather than one per character.
fn finish(
  pieces : Pieces,
  bytes : Bytes,
  spans : Array[Span],
) -> Array[Int32] raise @refused.Refused {
  let out : Array[Int32] = []
  let mut previous_was_unknown = false
  for span in spans {
    if span.id < 0 {
      raise @refused.Absent("an unknown character has no piece")
    }
    let kind = pieces.items[span.id].kind
    if kind == Control {
      out.push(span.id)
      previous_was_unknown = false
      continue
    }
    let unknown = span.id == pieces.unk_id()
    if unknown && pieces.byte_fallback() {
      for i = span.start; i < span.stop; i = i + 1 {
        out.push(pieces.byte_id(bytes[i].to_int() & 0xFF))
      }
    } else if !previous_was_unknown || !unknown {
      out.push(span.id)
    }
    previous_was_unknown = unknown
  }
  out
}
