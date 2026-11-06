// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// Counting what a text costs, over a vocabulary this file builds itself.
//
// A real encoder's table comes from the file the model ships; here it is small
// enough to read, which keeps the example about the calls and not about the
// data. Run it with `moon run src/examples/01-count-tokens`.

///|
/// A table with every byte, and a few merges on top.
///
/// Every byte has to be in it: that is what makes a byte-level encoding total
/// over text, and the constructor refuses a table without them.
fn ranks() -> @vocab.Ranks raise {
  let pairs : Array[(Bytes, Int32)] = []
  for b = 0; b < 256; b = b + 1 {
    pairs.push((Bytes::make(1, b.to_byte()), b))
  }
  let merges = [
    ("th", 256),
    ("he", 257),
    ("the", 258),
    ("in", 259),
    ("ing", 260),
    (" and", 261),
    (" world", 262),
  ]
  for i = 0; i < merges.length(); i = i + 1 {
    let (token, rank) = merges[i]
    pairs.push((@utf8.encode(token), rank))
  }
  @vocab.Ranks::from_pairs(pairs)
}

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
  let tokenizer = @moontoken.Tokenizer::cl100k(ranks=ranks()) catch {
    _ => {
      println("the table was refused")
      return
    }
  }
  let text = "the world and the thing"
  let ids = tokenizer.encode(text) catch {
    _ => {
      println("the text was refused")
      return
    }
  }
  println("text       \{text}")
  println("tokens     \{ids.length()}")
  println("ids        \{numbers(ids)}")
  println("bytes      \{tokenizer.decode_bytes(ids).length()}")
  println("decoded    \{tokenizer.decode(ids)}")
  println("count      \{tokenizer.count(text)}")
  println("vocabulary \{tokenizer.length()}")
}
