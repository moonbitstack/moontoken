// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The Unicode general categories a pre-tokenizer rule refers to, as the
/// patterns are written in terms of `\p{L}`, `\p{N}` and `\p{M}`.
///
/// Decoding a code point twice for one character would show up in the profile
/// of any tokenizer, so the ASCII range is answered from a table instead.
fn is_letter(c : Char) -> Bool {
  let n = c.to_int()
  if n < 0x80 {
    return (n >= 0x41 && n <= 0x5A) || (n >= 0x61 && n <= 0x7A)
  }
  match @ucd.category(c) {
    Lu | Ll | Lt | Lm | Lo => true
    _ => false
  }
}

///|
fn is_number(c : Char) -> Bool {
  let n = c.to_int()
  if n < 0x80 {
    return n >= 0x30 && n <= 0x39
  }
  match @ucd.category(c) {
    Nd | Nl | No => true
    _ => false
  }
}

///|
/// The `\s` of the patterns. Rust's `regex` crate reads it as the
/// `White_Space` property rather than as the `Z` category, and the two differ on
/// U+0009 to U+000D and U+0085.
fn is_space(c : Char) -> Bool {
  let n = c.to_int()
  if n < 0x80 {
    return n == 0x20 || (n >= 0x09 && n <= 0x0D)
  }
  @ucd.has(c, @ucd.WhiteSpace)
}

///|
/// `[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]`, the leading class of the case-aware
/// rules.
fn is_upper_class(c : Char) -> Bool {
  let n = c.to_int()
  if n < 0x80 {
    return n >= 0x41 && n <= 0x5A
  }
  match @ucd.category(c) {
    Lu | Lt | Lm | Lo | Mn | Mc | Me => true
    _ => false
  }
}

///|
/// `[\p{Ll}\p{Lm}\p{Lo}\p{M}]`, the trailing class of the case-aware rules.
fn is_lower_class(c : Char) -> Bool {
  let n = c.to_int()
  if n < 0x80 {
    return n >= 0x61 && n <= 0x7A
  }
  match @ucd.category(c) {
    Ll | Lm | Lo | Mn | Mc | Me => true
    _ => false
  }
}

///|
fn is_cr(c : Char) -> Bool {
  c == '\r'
}

///|
fn is_lf(c : Char) -> Bool {
  c == '\n'
}
