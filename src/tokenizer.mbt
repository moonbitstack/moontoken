// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
pub using @refused {type Refused}

///|
/// What a tokenizer needs from a segmentation algorithm.
///
/// The four models this library ships are byte-level byte-pair encoding, the
/// two sentence-piece models, and the pair-merge model of a `tokenizer.json`
/// file. A caller with a fifth implements this and gets the whole surface:
/// text in, tokens out, and the special tokens around them.
pub(open) trait Model {
  ///|
  /// The tokens of text that holds no reserved token.
  fn encode(Self, StringView) -> Array[Int32] raise Refused
  ///|
  /// The bytes a list of tokens stands for.
  fn decode_bytes(Self, Array[Int32]) -> Bytes raise Refused
  ///|
  /// The text a list of tokens stands for.
  fn decode(Self, Array[Int32]) -> String raise Refused
  ///|
  /// The bytes one token stands for, when the vocabulary has it.
  fn token_bytes(Self, Int32) -> Bytes?
  ///|
  /// How many tokens the vocabulary has.
  fn length(Self) -> Int32
}

///|
impl Model for @bpe.ByteBpe with fn encode(self, text) {
  @bpe.ByteBpe::encode(self, text)
}

///|
impl Model for @bpe.ByteBpe with fn decode_bytes(self, ids) {
  @bpe.ByteBpe::decode_bytes(self, ids)
}

///|
impl Model for @bpe.ByteBpe with fn decode(self, ids) {
  @bpe.ByteBpe::decode(self, ids)
}

///|
impl Model for @bpe.ByteBpe with fn token_bytes(self, id) {
  @bpe.ByteBpe::token_bytes(self, id)
}

///|
impl Model for @bpe.ByteBpe with fn length(self) {
  @bpe.ByteBpe::length(self)
}

///|
impl Model for @bpe.WordBpe with fn encode(self, text) {
  @bpe.WordBpe::encode(self, text)
}

///|
impl Model for @bpe.WordBpe with fn decode_bytes(self, ids) {
  @bpe.WordBpe::decode_bytes(self, ids)
}

///|
impl Model for @bpe.WordBpe with fn decode(self, ids) {
  @bpe.WordBpe::decode(self, ids)
}

///|
impl Model for @bpe.WordBpe with fn token_bytes(self, id) {
  @bpe.WordBpe::token_bytes(self, id)
}

///|
impl Model for @bpe.WordBpe with fn length(self) {
  @bpe.WordBpe::length(self)
}

///|
impl Model for @piece.Unigram with fn encode(self, text) {
  @piece.Unigram::encode(self, text)
}

///|
impl Model for @piece.Unigram with fn decode_bytes(self, ids) {
  @utf8.encode(@piece.Unigram::decode(self, ids))
}

///|
impl Model for @piece.Unigram with fn decode(self, ids) {
  @piece.Unigram::decode(self, ids)
}

///|
impl Model for @piece.Unigram with fn token_bytes(self, id) {
  @piece.Unigram::token_bytes(self, id)
}

///|
impl Model for @piece.Unigram with fn length(self) {
  @piece.Unigram::length(self)
}

///|
impl Model for @piece.PieceBpe with fn encode(self, text) {
  @piece.PieceBpe::encode(self, text)
}

///|
impl Model for @piece.PieceBpe with fn decode_bytes(self, ids) {
  @utf8.encode(@piece.PieceBpe::decode(self, ids))
}

///|
impl Model for @piece.PieceBpe with fn decode(self, ids) {
  @piece.PieceBpe::decode(self, ids)
}

///|
impl Model for @piece.PieceBpe with fn token_bytes(self, id) {
  @piece.PieceBpe::token_bytes(self, id)
}

///|
impl Model for @piece.PieceBpe with fn length(self) {
  @piece.PieceBpe::length(self)
}

///|
/// A tokenizer: a model, the tokens it reserves, and what may happen to them.
///
/// Text goes in and tokens come out, and the tokens come back as the same
/// text, including the bytes that are not text on their own. The vocabulary is
/// the caller's: this library reads one it is handed and never opens a file.
pub struct Tokenizer {
  model : &Model
  specials : @special.Table
  policy : @special.Policy
}

///|
/// A tokenizer over any model.
pub fn Tokenizer::new(
  model~ : &Model,
  specials~ : @special.Table = @special.Table::empty(),
  policy~ : @special.Policy = Refuse,
) -> Tokenizer {
  { model, specials, policy, }
}

///|
/// A tokenizer over a byte-level byte-pair table.
pub fn Tokenizer::byte_bpe(
  ranks~ : @vocab.Ranks,
  split~ : @split.Split,
  specials~ : @special.Table = @special.Table::empty(),
  policy~ : @special.Policy = Refuse,
  options~ : @bpe.Options = @bpe.options,
) -> Tokenizer raise Refused {
  let model = @bpe.ByteBpe::new(ranks~, split~, options~)
  Tokenizer::new(model~, specials~, policy~)
}

///|
/// A tokenizer over a sentence-piece vocabulary that segments by the most
/// likely sequence of pieces.
pub fn Tokenizer::unigram(
  pieces~ : @piece.Pieces,
  normalizer~ : @normalizer.Normalizer = @normalizer.Normalizer::identity(),
  specials~ : @special.Table = @special.Table::empty(),
  policy~ : @special.Policy = Refuse,
) -> Tokenizer {
  let model = @piece.Unigram::new(pieces~, normalizer~)
  Tokenizer::new(model~, specials~, policy~)
}

///|
/// A tokenizer over a sentence-piece vocabulary that segments by merging
/// neighbouring symbols.
pub fn Tokenizer::piece_bpe(
  pieces~ : @piece.Pieces,
  normalizer~ : @normalizer.Normalizer = @normalizer.Normalizer::identity(),
  user_defined~ : Array[Bytes] = [],
  specials~ : @special.Table = @special.Table::empty(),
  policy~ : @special.Policy = Refuse,
) -> Tokenizer {
  let model = @piece.PieceBpe::new(pieces~, normalizer~, user_defined~)
  Tokenizer::new(model~, specials~, policy~)
}

///|
/// A tokenizer from a sentence-piece model file.
pub fn Tokenizer::of_proto(bytes : Bytes) -> Tokenizer raise Refused {
  let proto = @piece.Proto::of(bytes)
  let trainer = proto.trainer()
  let pieces = proto.pieces()
  let normalizer = proto.normalizer()
  match trainer.kind {
    @piece.Unigram =>
      Tokenizer::new(
        model=@piece.Unigram::new(pieces~, normalizer~),
        policy=Refuse,
      )
    @piece.Bpe =>
      Tokenizer::new(
        model=@piece.PieceBpe::new(
          pieces~,
          normalizer~,
          user_defined=proto.user_defined(),
        ),
        policy=Refuse,
      )
    @piece.Word => raise @refused.Unsupported("a word model")
    @piece.Char => raise @refused.Unsupported("a character model")
  }
}

///|
/// The tokens of `cl100k_base`, given the table of ranks that encoding uses.
pub fn Tokenizer::cl100k(
  ranks~ : @vocab.Ranks,
  policy~ : @special.Policy = @special.Allow,
) -> Tokenizer raise Refused {
  Tokenizer::byte_bpe(
    ranks~,
    split=@split.Cl100k,
    specials=@special.cl100k_base(),
    policy~,
  )
}

///|
/// The tokens of `o200k_base`, given the table of ranks that encoding uses.
pub fn Tokenizer::o200k(
  ranks~ : @vocab.Ranks,
  policy~ : @special.Policy = @special.Allow,
) -> Tokenizer raise Refused {
  Tokenizer::byte_bpe(
    ranks~,
    split=@split.O200k,
    specials=@special.o200k_base(),
    policy~,
  )
}

///|
/// The tokens of `r50k_base`, given the table of ranks that encoding uses.
pub fn Tokenizer::r50k(
  ranks~ : @vocab.Ranks,
  policy~ : @special.Policy = @special.Allow,
) -> Tokenizer raise Refused {
  Tokenizer::byte_bpe(
    ranks~,
    split=@split.Gpt2,
    specials=@special.r50k_base(),
    policy~,
  )
}

///|
/// The tokens of `p50k_edit`, given the table of ranks that encoding uses.
pub fn Tokenizer::p50k_edit(
  ranks~ : @vocab.Ranks,
  policy~ : @special.Policy = @special.Allow,
) -> Tokenizer raise Refused {
  Tokenizer::byte_bpe(
    ranks~,
    split=@split.Gpt2,
    specials=@special.p50k_edit(),
    policy~,
  )
}

///|
/// A tokenizer with a different answer for the text that holds a reserved
/// token.
pub fn Tokenizer::with_policy(
  self : Tokenizer,
  special : @special.Policy,
) -> Tokenizer {
  { ..self, policy: special, }
}

///|
/// What this tokenizer does with the text that holds a reserved token.
pub fn Tokenizer::policy(self : Tokenizer) -> @special.Policy {
  self.policy
}

///|
/// The tokens `text` holds.
///
/// `special` overrides the policy this tokenizer was built with, for a caller
/// that knows this one string came from a model that emits the reserved
/// spelling itself.
pub fn Tokenizer::encode(
  self : Tokenizer,
  text : StringView,
  special? : @special.Policy,
) -> Array[Int32] raise Refused {
  let policy = match special {
    Some(policy) => policy
    None => self.policy
  }
  if !policy.recognizes() || self.specials.length() == 0 {
    return self.model.encode(text)
  }
  let out : Array[Int32] = []
  let mut at = 0
  while at < text.length() {
    let hit = match self.specials.find(text, at) {
      Some(hit) => hit
      None => break
    }
    if hit.start > at {
      let head = text.exact_view(start=at, end=hit.start)
      for id in self.model.encode(head) {
        out.push(id)
      }
    }
    if !policy.allows(hit.text[:]) {
      raise @refused.Disallowed(hit.text, hit.start)
    }
    out.push(hit.id)
    at = hit.start + hit.text.length()
  }
  if at < text.length() {
    let tail = text.exact_view(start=at, end=text.length())
    for id in self.model.encode(tail) {
      out.push(id)
    }
  }
  out
}

///|
/// The tokens of text that holds no reserved token, whatever the policy says.
pub fn Tokenizer::encode_ordinary(
  self : Tokenizer,
  text : StringView,
) -> Array[Int32] raise Refused {
  self.model.encode(text)
}

///|
/// How many tokens `text` holds.
///
/// This is `encode` with every reserved token recognised, which is the number
/// a caller budgeting a context window wants: the reserved spellings cost
/// their one token rather than being taken apart as text.
pub fn Tokenizer::count(
  self : Tokenizer,
  text : StringView,
  special? : @special.Policy,
) -> Int32 raise Refused {
  let policy = match special {
    Some(policy) => policy
    None => Allow
  }
  self.encode(text, special=policy).length()
}

///|
/// The bytes a list of tokens stands for.
pub fn Tokenizer::decode_bytes(
  self : Tokenizer,
  ids : Array[Int32],
  reserved~ : Bool = true,
) -> Bytes raise Refused {
  let out : Array[Byte] = []
  let run : Array[Int32] = []
  for id in ids {
    match self.specials.text(id) {
      Some(text) => {
        if !reserved {
          continue
        }
        if !run.is_empty() {
          for byte in self.model.decode_bytes(run)[:] {
            out.push(byte)
          }
          run.clear()
        }
        for byte in @utf8.encode(text)[:] {
          out.push(byte)
        }
      }
      None => run.push(id)
    }
  }
  if !run.is_empty() {
    for byte in self.model.decode_bytes(run)[:] {
      out.push(byte)
    }
  }
  Bytes::from_array(out)
}

///|
/// The text a list of tokens stands for, with U+FFFD standing in for the byte
/// sequences that are not text.
pub fn Tokenizer::decode(
  self : Tokenizer,
  ids : Array[Int32],
  reserved~ : Bool = true,
) -> String raise Refused {
  @utf8.decode_lossy(self.decode_bytes(ids, reserved~)[:])
}

///|
/// The bytes one token stands for.
pub fn Tokenizer::token_bytes(self : Tokenizer, id : Int32) -> Bytes? {
  match self.specials.text(id) {
    Some(text) => Some(@utf8.encode(text))
    None => self.model.token_bytes(id)
  }
}

///|
/// How many tokens the vocabulary has, reserved ones not counted.
pub fn Tokenizer::length(self : Tokenizer) -> Int32 {
  self.model.length()
}
