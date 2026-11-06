// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// A sentence-piece vocabulary, written out by hand.
//
// A model file is a protobuf this library reads; here the vocabulary is spelled
// out so the example shows what a segmentation weighs. Run it with
// `moon run src/examples/02-sentence-piece`.

///|
/// One entry of a vocabulary: the piece, its log probability, and what it is.
fn piece(text : String, score : Float, kind : @piece.Kind) -> @piece.Piece {
  { text: @utf8.encode(text), score, kind, }
}

///|
fn vocabulary() -> @piece.Pieces raise {
  @piece.Pieces::new(
    items=[
      piece("<unk>", 0.0F, @piece.Unknown),
      piece("\u{2581}", -3.0F, @piece.Normal),
      piece("\u{2581}the", -1.2F, @piece.Normal),
      piece("\u{2581}quick", -1.6F, @piece.Normal),
      piece("\u{2581}brown", -1.7F, @piece.Normal),
      piece("\u{2581}fox", -1.9F, @piece.Normal),
      piece("th", -2.1F, @piece.Normal),
      piece("the", -1.4F, @piece.Normal),
      piece("e", -2.6F, @piece.Normal),
      piece("q", -3.1F, @piece.Normal),
      piece("u", -2.8F, @piece.Normal),
      piece("i", -2.7F, @piece.Normal),
      piece("c", -2.9F, @piece.Normal),
      piece("k", -2.9F, @piece.Normal),
      piece("f", -3.0F, @piece.Normal),
      piece("o", -2.5F, @piece.Normal),
      piece("x", -3.2F, @piece.Normal),
      piece("b", -3.3F, @piece.Normal),
      piece("r", -2.9F, @piece.Normal),
      piece("w", -3.1F, @piece.Normal),
      piece("n", -2.8F, @piece.Normal),
      piece("<MOON>", 0.0F, @piece.UserDefined),
    ],
    unk_id=0,
  )
}

///|

///|
/// A list of numbers on one line, which is what a reader wants to see and what
/// `Show` would wrap in brackets.
fn numbers(ids : Array[Int32]) -> String {
  let out = StringBuilder()
  let mut separator = ""
  for id in ids {
    out.write_string(separator)
    out.write_string(id.to_string())
    separator = " "
  }
  out.to_string()
}

///|
fn main raise {
  let normalizer = @normalizer.Normalizer::chain([
    @normalizer.Nfkc,
    @normalizer.EscapeSpace,
    @normalizer.Pad("\u{2581}"),
  ])
  let tokenizer = @moontoken.Tokenizer::unigram(
    pieces=vocabulary(),
    normalizer~,
  )
  // The second text holds a symbol the vocabulary reserved, which is matched
  // as one piece and never broken up.
  for text in ["the quick brown fox", "the <MOON> fox", "th e fox"] {
    let ids = tokenizer.encode(text)
    let pieces : Array[String] = []
    for id in ids {
      let bytes = tokenizer.token_bytes(id).unwrap()
      pieces.push(@utf8.decode_lossy(bytes[:]))
    }
    println("\{text} -> \{numbers(ids)}")
    let shown = StringBuilder()
    for piece in pieces {
      shown.write_string("[")
      shown.write_string(piece)
      shown.write_string("]")
    }
    println("  pieces  \{shown.to_string()}")
    println("  count   \{tokenizer.count(text)}")
    println("  back    \{tokenizer.decode(ids)}")
  }
}
