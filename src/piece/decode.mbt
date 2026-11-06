// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The text a list of tokens stands for.
///
/// Three things happen on the way out: control tokens vanish, byte tokens are
/// held back until the bytes they carry spell a character, and the word-break
/// marker becomes a space, minus the one the normaliser put at the front.
fn decode_pieces(
  pieces : Pieces,
  normalizer : @normalizer.Normalizer,
  ids : ArrayView[Int32],
) -> String raise @refused.Refused {
  let out : Array[Byte] = []
  let pending : Array[Byte] = []
  let symbol : Bytes = b"\xE2\x96\x81"
  let mut at_first = true
  for id in ids {
    let piece = pieces.at(id)
    if piece.kind == RawByte {
      match byte_of_piece(piece.text) {
        Some(b) => pending.push(b.to_byte())
        None => raise @refused.Malformed("a byte piece is not <0xNN>", id)
      }
      continue
    }
    flush_bytes(pending, out)
    if !out.is_empty() {
      at_first = false
    }
    if piece.kind == Control {
      continue
    }
    let mut text = piece.text
    let mut dropped = false
    if at_first && normalizer.drops_leading_space() {
      if starts_with(text, symbol) {
        text = text[symbol.length():].to_owned()
        dropped = true
      }
    }
    if piece.kind == Unknown {
      append(out, pieces.unk_surface[:])
    } else {
      append_replaced(out, text[:], symbol, b' ')
    }
    if dropped || !out.is_empty() {
      at_first = false
    }
  }
  flush_bytes(pending, out)
  @utf8.decode_lossy(Bytes::from_array(out)[:])
}

///|
fn append(out : Array[Byte], bytes : BytesView) -> Unit {
  for i = 0; i < bytes.length(); i = i + 1 {
    out.push(bytes[i])
  }
}

///|
fn starts_with(bytes : Bytes, prefix : Bytes) -> Bool {
  if bytes.length() < prefix.length() {
    return false
  }
  for i = 0; i < prefix.length(); i = i + 1 {
    if bytes[i] != prefix[i] {
      return false
    }
  }
  true
}

///|
/// Appends `bytes`, writing `instead` wherever `from` appears.
fn append_replaced(
  out : Array[Byte],
  bytes : BytesView,
  from : Bytes,
  instead : Byte,
) -> Unit {
  let mut i = 0
  while i < bytes.length() {
    let mut same = i + from.length() <= bytes.length()
    if same {
      for k = 0; k < from.length(); k = k + 1 {
        if bytes[i + k] != from[k] {
          same = false
          break
        }
      }
    }
    if same {
      out.push(instead)
      i = i + from.length()
    } else {
      out.push(bytes[i])
      i = i + 1
    }
  }
}

///|
/// Turns the bytes held back by byte tokens into text, standing U+FFFD in for
/// the sequences that are not text.
fn flush_bytes(pending : Array[Byte], out : Array[Byte]) -> Unit {
  if pending.is_empty() {
    return
  }
  let bytes = Bytes::from_array(pending)
  pending.clear()
  let mut at = 0
  while at < bytes.length() {
    let width = @split.utf8_width_at(bytes, at)
    if width == 0 {
      out.push(b'\xEF')
      out.push(b'\xBF')
      out.push(b'\xBD')
      at = at + 1
    } else {
      for i = 0; i < width; i = i + 1 {
        out.push(bytes[at + i])
      }
      at = at + width
    }
  }
}
