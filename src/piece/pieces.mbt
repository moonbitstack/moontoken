// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What a piece is for.
#derive(Eq)
pub(all) enum Kind {
  /// segmentation, whether it survives decoding, and whether it stands for a
  /// byte.
  ///
  /// An ordinary piece.
  Normal
  ///
  /// The piece that stands in for text nothing else covers.
  Unknown
  ///
  /// A marker such as `<s>`: never produced from text, never decoded.
  Control
  ///
  /// A piece the caller declared, which is matched before any other rule.
  UserDefined
  ///
  /// A piece kept in the vocabulary but never produced.
  Unused
  ///
  /// One byte, written `<0x41>`, used when a character has no piece.
  RawByte
}

///|
pub extend Kind with Eq::{equal, not_equal}

///|
/// One entry of a vocabulary: the text it stands for, the log probability the
/// trainer gave it, and what it is.
pub(all) struct Piece {
  text : Bytes
  score : Float
  kind : Kind
}

///|
/// A vocabulary of pieces, with the indexes a model needs: one for the pieces
/// segmentation may use, one for everything.
pub struct Pieces {
  items : Array[Piece]
  exact : Map[Bytes, Int32]
  lattice : Map[Bytes, Int32]
  longest : Int32
  unk_id : Int32
  unk_surface : Bytes
  byte_ids : Array[Int32]
  byte_fallback : Bool
}

///|
/// The text of the piece that stands for one byte.
pub fn byte_piece(b : Int32) -> String {
  let digits = "0123456789ABCDEF"
  let out = StringBuilder()
  out.write_string("<0x")
  out.write_char(digits[(b >> 4) & 15].unsafe_to_char())
  out.write_char(digits[b & 15].unsafe_to_char())
  out.write_char('>')
  out.to_string()
}

///|
/// Builds the tables over a list of pieces.
///
/// `unk_id` is the piece that stands in for text nothing covers, and
/// `byte_fallback` says whether the model can spell a character out as bytes.
pub fn Pieces::new(
  items~ : Array[Piece],
  unk_id~ : Int32 = -1,
  unk_surface~ : String = " \u{2047} ",
  byte_fallback~ : Bool = false,
) -> Pieces raise @refused.Refused {
  let exact : Map[Bytes, Int32] = Map([])
  let lattice : Map[Bytes, Int32] = Map([])
  let byte_ids : Array[Int32] = Array::make(256, -1)
  let mut longest = 0
  for i = 0; i < items.length(); i = i + 1 {
    let piece = items[i]
    if piece.text.length() == 0 {
      raise @refused.Malformed("a piece is empty", i)
    }
    if exact.contains(piece.text) {
      raise @refused.Malformed("a piece appears twice", i)
    }
    exact.set(piece.text, i)
    match piece.kind {
      Normal | UserDefined => {
        lattice.set(piece.text, i)
        if piece.text.length() > longest {
          longest = piece.text.length()
        }
      }
      Unused => ()
      RawByte =>
        match byte_of_piece(piece.text) {
          Some(b) => byte_ids[b] = i
          None => raise @refused.Malformed("a byte piece is not <0xNN>", i)
        }
      Unknown | Control => ()
    }
  }
  if byte_fallback {
    for b = 0; b < 256; b = b + 1 {
      if byte_ids[b] < 0 {
        raise @refused.Absent(
          "a byte piece is missing while byte fallback is on",
        )
      }
    }
  }
  {
    items,
    exact,
    lattice,
    longest,
    unk_id,
    unk_surface: @utf8.encode(unk_surface),
    byte_ids,
    byte_fallback,
  }
}

///|
/// The byte a `<0xNN>` piece stands for.
fn byte_of_piece(text : Bytes) -> Int32? {
  if text.length() != 6 {
    return None
  }
  if text[0] != b'<' || text[1] != b'0' || text[2] != b'x' || text[5] != b'>' {
    return None
  }
  let high = hex_digit(text[3])
  let low = hex_digit(text[4])
  match (high, low) {
    (Some(h), Some(l)) => Some(h * 16 + l)
    _ => None
  }
}

///|
fn hex_digit(b : Byte) -> Int32? {
  let n = b.to_int()
  if n >= 0x30 && n <= 0x39 {
    Some(n - 0x30)
  } else if n >= 0x41 && n <= 0x46 {
    Some(n - 0x41 + 10)
  } else if n >= 0x61 && n <= 0x66 {
    Some(n - 0x61 + 10)
  } else {
    None
  }
}

///|
/// How many pieces there are; ids run from 0 to this less one.
pub fn Pieces::length(self : Pieces) -> Int32 {
  self.items.length()
}

///|
/// The piece with this id.
pub fn Pieces::at(self : Pieces, id : Int32) -> Piece raise @refused.Refused {
  if id < 0 || id >= self.items.length() {
    raise @refused.Missing(id)
  }
  self.items[id]
}

///|
/// The id of a piece, whatever kind it is.
pub fn Pieces::id(self : Pieces, text : BytesView) -> Int32? {
  self.exact.get_from_bytes(text)
}

///|
/// The id of a piece segmentation may use: an ordinary one or a declared one.
pub fn Pieces::lattice_id(self : Pieces, text : BytesView) -> Int32? {
  self.lattice.get_from_bytes(text)
}

///|
/// The longest piece segmentation may use, in bytes.
pub fn Pieces::longest(self : Pieces) -> Int32 {
  self.longest
}

///|
/// The id of the piece that stands in for uncovered text, or -1.
pub fn Pieces::unk_id(self : Pieces) -> Int32 {
  self.unk_id
}

///|
/// The text an unknown token stands for when it is decoded.
pub fn Pieces::unk_surface(self : Pieces) -> Bytes {
  self.unk_surface
}

///|
/// Whether a character with no piece may be spelled out as bytes.
pub fn Pieces::byte_fallback(self : Pieces) -> Bool {
  self.byte_fallback
}

///|
/// The id of the piece for one byte, or -1.
pub fn Pieces::byte_id(self : Pieces, b : Int32) -> Int32 {
  self.byte_ids[b]
}
