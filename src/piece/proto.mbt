// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A reader for the protobuf wire format, covering only what a model file
/// uses: tags, length-delimited fields, varints and 32-bit floats.
priv struct Wire {
  bytes : Bytes
  mut pos : Int32
}

///|
fn Wire::new(bytes : Bytes) -> Wire {
  { bytes, pos: 0, }
}

///|
fn Wire::done(self : Wire) -> Bool {
  self.pos >= self.bytes.length()
}

///|
fn Wire::varint(self : Wire) -> Int32 raise @refused.Refused {
  let mut value = 0
  let mut shift = 0
  while shift <= 63 {
    if self.pos >= self.bytes.length() {
      raise @refused.Malformed("a varint runs past the end", self.pos)
    }
    let b = self.bytes[self.pos].to_int() & 0xFF
    self.pos = self.pos + 1
    value = value | ((b & 0x7F) << shift)
    if b < 0x80 {
      return value
    }
    shift = shift + 7
  }
  raise @refused.Malformed("a varint is longer than a word", self.pos)
}

///|
/// The field number and wire type of the next field.
fn Wire::tag(self : Wire) -> (Int32, Int32) raise @refused.Refused {
  let tag = self.varint()
  (tag >> 3, tag & 7)
}

///|
fn Wire::take(self : Wire, count : Int32) -> Bytes raise @refused.Refused {
  if count < 0 || self.pos + count > self.bytes.length() {
    raise @refused.Malformed("a field runs past the end", self.pos)
  }
  let slice = self.bytes[self.pos:self.pos + count]
  self.pos = self.pos + count
  slice.to_owned()
}

///|
fn Wire::delim(self : Wire) -> Bytes raise @refused.Refused {
  let count = self.varint()
  self.take(count)
}

///|
fn Wire::float(self : Wire) -> Float raise @refused.Refused {
  let raw = self.take(4)
  let bits = (raw[0].to_int() & 0xFF) |
    ((raw[1].to_int() & 0xFF) << 8) |
    ((raw[2].to_int() & 0xFF) << 16) |
    ((raw[3].to_int() & 0xFF) << 24)
  Float::reinterpret_from_int(bits)
}

///|
fn Wire::skip(self : Wire, wire : Int32) -> Unit raise @refused.Refused {
  match wire {
    0 => ignore(self.varint())
    1 => ignore(self.take(8))
    2 => ignore(self.delim())
    5 => ignore(self.take(4))
    _ =>
      raise @refused.Malformed(
        "a field uses a wire type this reader does not take",
        self.pos,
      )
  }
}

///|
/// What kind of model a file was trained as.
#derive(Eq)
pub(all) enum ModelKind {
  ///
  /// Segmentation by the most likely sequence of pieces.
  Unigram
  ///
  /// Segmentation by merged pairs, the sentence-piece flavour.
  Bpe
  ///
  /// One piece per word.
  Word
  ///
  /// One piece per character.
  Char
}

///|
pub extend ModelKind with Eq::{equal, not_equal}

///|
/// The settings a model was trained with that change how it runs.
pub(all) struct Trainer {
  kind : ModelKind
  unk_id : Int32
  byte_fallback : Bool
  treat_whitespace_as_suffix : Bool
  unk_piece : String
  unk_surface : String
}

///|
/// A model file: its pieces, how it was trained, and how text is normalised
/// before segmentation.
pub struct Proto {
  pieces : Pieces
  trainer : Trainer
  normalizer : @normalizer.Spec
}

///|
/// Reads one length-delimited piece.
fn read_piece(bytes : Bytes, at : Int32) -> Piece raise @refused.Refused {
  let wire = Wire::new(bytes)
  let mut text = b""
  let mut score = 0.0F
  let mut kind = Normal
  while !wire.done() {
    let (field, type_) = wire.tag()
    match (field, type_) {
      (1, 2) => text = wire.delim()
      (2, 5) => score = wire.float()
      (3, 0) =>
        kind = match wire.varint() {
          1 => Normal
          2 => Unknown
          3 => Control
          4 => UserDefined
          5 => Unused
          6 => RawByte
          other =>
            raise @refused.Malformed("a piece has an unknown type", other)
        }
      _ => wire.skip(type_)
    }
  }
  ignore(at)
  { text, score, kind, }
}

///|
fn read_normalizer(bytes : Bytes) -> @normalizer.Spec raise @refused.Refused {
  let wire = Wire::new(bytes)
  let mut spec : @normalizer.Spec = {
    name: "",
    charsmap: b"",
    add_dummy_prefix: true,
    remove_extra_whitespaces: true,
    escape_whitespaces: true,
  }
  while !wire.done() {
    let (field, type_) = wire.tag()
    match (field, type_) {
      (1, 2) => spec = { ..spec, name: @utf8.decode_lossy(wire.delim()[:]), }
      (2, 2) => spec = { ..spec, charsmap: wire.delim(), }
      (3, 0) => spec = { ..spec, add_dummy_prefix: wire.varint() != 0, }
      (4, 0) => spec = { ..spec, remove_extra_whitespaces: wire.varint() != 0, }
      (5, 0) => spec = { ..spec, escape_whitespaces: wire.varint() != 0, }
      _ => wire.skip(type_)
    }
  }
  spec
}

///|
fn read_trainer(bytes : Bytes) -> Trainer raise @refused.Refused {
  let wire = Wire::new(bytes)
  let mut trainer = {
    kind: Unigram,
    unk_id: 0,
    byte_fallback: false,
    treat_whitespace_as_suffix: false,
    unk_piece: "<unk>",
    unk_surface: " \u{2047} ",
  }
  while !wire.done() {
    let (field, type_) = wire.tag()
    match (field, type_) {
      (3, 0) =>
        trainer = {
          ..trainer,
          kind: match wire.varint() {
            1 => Unigram
            2 => Bpe
            3 => Word
            4 => Char
            other =>
              raise @refused.Unsupported(
                "a model type this reader does not take: \{other}",
              )
          },
        }
      (24, 0) =>
        trainer = { ..trainer, treat_whitespace_as_suffix: wire.varint() != 0, }
      (35, 0) => trainer = { ..trainer, byte_fallback: wire.varint() != 0, }
      (40, 0) => trainer = { ..trainer, unk_id: wire.varint(), }
      (44, 2) =>
        trainer = {
          ..trainer,
          unk_surface: @utf8.decode_lossy(wire.delim()[:]),
        }
      (45, 2) =>
        trainer = { ..trainer, unk_piece: @utf8.decode_lossy(wire.delim()[:]), }
      _ => wire.skip(type_)
    }
  }
  trainer
}

///|
/// Reads a model file.
pub fn Proto::of(bytes : Bytes) -> Proto raise @refused.Refused {
  let wire = Wire::new(bytes)
  let items : Array[Piece] = []
  let mut trainer = {
    kind: Unigram,
    unk_id: 0,
    byte_fallback: false,
    treat_whitespace_as_suffix: false,
    unk_piece: "<unk>",
    unk_surface: " \u{2047} ",
  }
  let mut normalizer : @normalizer.Spec = {
    name: "",
    charsmap: b"",
    add_dummy_prefix: true,
    remove_extra_whitespaces: true,
    escape_whitespaces: true,
  }
  while !wire.done() {
    let (field, type_) = wire.tag()
    match (field, type_) {
      (1, 2) => {
        let at = wire.pos
        let body = wire.delim()
        items.push(read_piece(body, at))
      }
      (2, 2) => trainer = read_trainer(wire.delim())
      (3, 2) => normalizer = read_normalizer(wire.delim())
      _ => wire.skip(type_)
    }
  }
  if items.is_empty() {
    raise @refused.Absent("the file has no pieces")
  }
  {
    pieces: Pieces::new(
      items~,
      unk_id=trainer.unk_id,
      unk_surface=trainer.unk_surface,
      byte_fallback=trainer.byte_fallback,
    ),
    trainer,
    normalizer,
  }
}

///|
/// The vocabulary.
pub fn Proto::pieces(self : Proto) -> Pieces {
  self.pieces
}

///|
/// How the model was trained.
pub fn Proto::trainer(self : Proto) -> Trainer {
  self.trainer
}

///|
/// The normalisation the model expects, as written in the file.
pub fn Proto::spec(self : Proto) -> @normalizer.Spec {
  self.normalizer
}

///|
/// The symbols the caller reserved, in the order the file lists them.
pub fn Proto::user_defined(self : Proto) -> Array[Bytes] {
  let out : Array[Bytes] = []
  for piece in self.pieces.items {
    if piece.kind == UserDefined {
      out.push(piece.text)
    }
  }
  out
}

///|
/// The normalisation the model expects, ready to apply.
pub fn Proto::normalizer(
  self : Proto,
) -> @normalizer.Normalizer raise @refused.Refused {
  @normalizer.Normalizer::rule(
    spec=self.normalizer,
    user_defined=self.user_defined(),
    treat_whitespace_as_suffix=self.trainer.treat_whitespace_as_suffix,
  )
}
