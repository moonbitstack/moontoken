// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The program the conformance runs drive.
//
// A reference implementation cannot be linked into this library, so the two
// sides are compared through a text protocol instead: records in, tokens out.
// `scripts/diff_reference.py` starts this program and compares what it prints
// with what the reference implementation prints for the same records.
//
// Records are separated by U+001E. Each mode prints one line per record:
//
//   split <rule>                      the words, as hex of their UTF-8 bytes
//   encode-tiktoken-<name> <table>    the token ids
//   decode-tiktoken-<name> <table>    the text, as hex of its UTF-8 bytes
//   encode-piece <model>              the token ids
//   decode-piece <model>              the text, as hex of its UTF-8 bytes
//   encode-json <file>                the token ids
//   decode-json <file>                the text, as hex of its UTF-8 bytes
//
// Decoding keeps a reserved token as the text it is written as, which is what
// every reference does; `Tokenizer::decode` takes a switch for the other
// reading, and the tests cover it.
//
// A record the library refuses prints a single `!`, which the reference side
// reports as an error for that record too.

///|
fn hex_of(bytes : Bytes) -> String {
  let digits = "0123456789abcdef"
  let out = StringBuilder()
  for i = 0; i < bytes.length(); i = i + 1 {
    let b = bytes[i].to_int() & 0xFF
    out.write_char(digits[(b >> 4) & 15].unsafe_to_char())
    out.write_char(digits[b & 15].unsafe_to_char())
  }
  out.to_string()
}

///|
fn ids_of(record : StringView) -> Array[Int32] {
  let ids : Array[Int32] = []
  for part in record.split(" ") {
    if !part.is_empty() {
      let id = @string.parse_int(part) catch { _ => -1 }
      if id >= 0 {
        ids.push(id)
      }
    }
  }
  ids
}

///|
fn print_ids(ids : Array[Int32]) -> Unit {
  let out = StringBuilder()
  let mut separator = ""
  for id in ids {
    out.write_string(separator)
    out.write_string(id.to_string())
    separator = " "
  }
  println(out.to_string())
}

///|
/// The pieces of a split, one record per line, as hex.
fn split_lines(rule : @split.Split, records : Iter[StringView]) -> Unit {
  for record in records {
    let out = StringBuilder()
    let mut separator = ""
    for word in rule.pieces(record) {
      out.write_string(separator)
      out.write_string(hex_of(@utf8.encode(word)))
      separator = " "
    }
    println(out.to_string())
  }
}

///|
/// A tokenizer over one of the published tables, which the caller supplies.
fn published(name : String, path : String) -> @moontoken.Tokenizer raise {
  let ranks = @vocab.Ranks::from_tiktoken(@fs.read_file_to_string(path)[:])
  match name {
    "cl100k" => @moontoken.Tokenizer::cl100k(ranks~, policy=@special.Allow)
    "o200k" => @moontoken.Tokenizer::o200k(ranks~, policy=@special.Allow)
    "r50k" => @moontoken.Tokenizer::r50k(ranks~, policy=@special.Allow)
    _ => @moontoken.Tokenizer::p50k_edit(ranks~, policy=@special.Allow)
  }
}

///|
fn main raise {
  let args = @env.args()
  if args.length() < 4 {
    println("usage: moontoken-conformance <mode> <source> <input>")
    return
  }
  let mode = args[1]
  let source = args[2]
  let records = @fs.read_file_to_string(args[3]).split("\u{1e}")
  if mode == "split" {
    split_lines(
      match source {
        "cl100k" => @split.Cl100k
        "o200k" => @split.O200k
        "gpt2" => @split.Gpt2
        _ => @split.Whole
      },
      records,
    )
    return
  }
  let parts : Array[StringView] = []
  for part in mode.split("-") {
    parts.push(part)
  }
  let family = if parts.length() > 1 { parts[1].to_owned() } else { "" }
  let name = if parts.length() > 2 { parts[2].to_owned() } else { "" }
  let encoding = mode.has_prefix("encode")
  let tokenizer = if family == "tiktoken" {
    published(name, source)
  } else if family == "piece" {
    @moontoken.Tokenizer::of_proto(@fs.read_file_to_bytes(source))
  } else {
    @moontoken.Tokenizer::parse(@fs.read_file_to_string(source)[:])
  }
  for record in records {
    if encoding {
      match (Ok(tokenizer.encode(record)) catch { _ => Err(()) }) {
        Ok(ids) => print_ids(ids)
        Err(_) => println("!")
      }
    } else {
      match (Ok(tokenizer.decode(ids_of(record))) catch { _ => Err(()) }) {
        Ok(text) => println(hex_of(@utf8.encode(text)))
        Err(_) => println("!")
      }
    }
  }
}
