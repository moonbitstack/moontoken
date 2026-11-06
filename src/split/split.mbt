// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How text is cut into the words a model is applied to.
///
/// The three named rules are the published pre-tokenizers of the byte-level
/// encodings: `r50k`/`p50k`/`gpt2`, `cl100k_base` and `o200k_base`. They are
/// scanners here rather than regular expressions because the patterns lean on
/// lookahead and possessive quantifiers, and because a tokenizer runs them once
/// per word over the whole input.
pub(all) enum Split {
  ///
  /// The whole text is one word.
  Whole
  ///
  /// `'(?:[sdmt]|ll|ve|re)| ?\p{L}++| ?\p{N}++| ?[^\s\p{L}\p{N}]++|\s++$|\s+(?!\S)|\s`
  Gpt2
  ///
  /// `'(?i:[sdmt]|ll|ve|re)|[^\r\n\p{L}\p{N}]?+\p{L}++|\p{N}{1,3}+| ?[^\s\p{L}\p{N}]++[\r\n]*+|\s++$|\s*[\r\n]|\s+(?!\S)|\s`
  Cl100k
  ///
  /// The `o200k_base` rule, which separates runs of capitals from runs of
  /// lower-case letters, so that `word` and `Word` are different words.
  O200k
  ///
  /// Runs of non-whitespace; the whitespace between them is dropped.
  Whitespace
  ///
  /// A word starts at every U+2581, the marker that whitespace becomes during
  /// normalisation. Text that arrived unescaped keeps its spaces inside words.
  Metaspace
  ///
  /// Digits on their own, either one by one or as runs.
  Digits(Digits)
  ///
  /// The rules applied one after another.
  Sequence(Array[Split])
}

///|
/// Whether digits are cut one at a time or as a run.
pub(all) struct Digits {
  individual : Bool
}

///|
pub let digits_individual : Digits = { individual: true, }

///|
pub let digits_run : Digits = { individual: false, }

///|
/// The code point at a UTF-16 offset.
fn char_at(text : StringView, i : Int32) -> Char {
  let n = text.at(i).to_int()
  if n >= 0xD800 && n <= 0xDBFF && i + 1 < text.length() {
    let v = text.at(i + 1).to_int()
    if v >= 0xDC00 && v <= 0xDFFF {
      return (0x10000 + (n - 0xD800) * 0x400 + (v - 0xDC00)).unsafe_to_char()
    }
  }
  n.unsafe_to_char()
}

///|
/// The offset just past the code point that starts at `i`.
fn step(text : StringView, i : Int32) -> Int32 {
  let n = text.at(i).to_int()
  if n >= 0xD800 && n <= 0xDBFF && i + 1 < text.length() {
    let v = text.at(i + 1).to_int()
    if v >= 0xDC00 && v <= 0xDFFF {
      return i + 2
    }
  }
  i + 1
}

///|
fn ascii_lower(c : Char) -> Char {
  let n = c.to_int()
  if n >= 0x41 && n <= 0x5A {
    return (n + 32).unsafe_to_char()
  }
  c
}

///|
/// The length of `(?i:'s|'t|'re|'ve|'m|'ll|'d)` at `i`, or 0 when there is
/// none. The case-insensitive flag of the encoding patterns covers exactly
/// these ASCII letters, so folding to lower case is the whole of it.
fn contraction_len(text : StringView, i : Int32, len : Int32) -> Int32 {
  if i >= len || char_at(text, i) != '\'' {
    return 0
  }
  let j = step(text, i)
  if j >= len {
    return 0
  }
  let first = ascii_lower(char_at(text, j))
  if first == 's' || first == 't' || first == 'm' || first == 'd' {
    return step(text, j) - i
  }
  if (first == 'l' || first == 'v' || first == 'r') && j + 1 < len {
    let second = ascii_lower(char_at(text, j + 1))
    if (first == 'l' && second == 'l') ||
      (first == 'v' && second == 'e') ||
      (first == 'r' && second == 'e') {
      return j + 2 - i
    }
  }
  0
}

///|
/// The end of `i` extended by a contraction when one starts there.
fn with_contraction(text : StringView, i : Int32, len : Int32) -> Int32 {
  let width = contraction_len(text, i, len)
  if width == 0 {
    i
  } else {
    i + width
  }
}

///|
/// The end of the longest run from `i` of characters `accept` takes.
fn run_end(
  text : StringView,
  i : Int32,
  len : Int32,
  accept : (Char) -> Bool,
) -> Int32 {
  let mut e = i
  while e < len && accept(char_at(text, e)) {
    e = step(text, e)
  }
  e
}

///|
/// The end of the whitespace run at `i`, and the start of its last character.
fn space_run(text : StringView, i : Int32, len : Int32) -> (Int32, Int32) {
  let mut e = i
  let mut last = i
  while e < len && is_space(char_at(text, e)) {
    last = e
    e = step(text, e)
  }
  (e, last)
}

///|
/// Punctuation, symbols and everything else that is neither whitespace nor a
/// letter nor a number, which is what `[^\s\p{L}\p{N}]` collects.
fn is_other(c : Char) -> Bool {
  !(is_space(c) || is_letter(c) || is_number(c))
}

///|
fn is_line_break(c : Char) -> Bool {
  c == '\r' || c == '\n'
}

///|
/// `[\r\n/]`, the tail the `o200k_base` punctuation rule keeps.
fn is_line_or_slash(c : Char) -> Bool {
  c == '\r' || c == '\n' || c == '/'
}

///|
/// `[^\r\n\p{L}\p{N}]?`, the single character the case-aware rules may take
/// ahead of a word.
fn is_word_prefix(c : Char) -> Bool {
  !(is_cr(c) || is_lf(c) || is_letter(c) || is_number(c))
}

///|
/// `[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]*[\p{Ll}\p{Lm}\p{Lo}\p{M}]+` followed by an
/// optional contraction. The run of capitals is shortened one character at a
/// time until the trailing part can start, which is the order the machine
/// tries them in.
fn capitals_then_word(text : StringView, start : Int32, len : Int32) -> Int32 {
  let capitals = run_end(text, start, len, is_upper_class)
  let mut k = capitals
  while k >= start {
    if k < len && is_lower_class(char_at(text, k)) {
      return with_contraction(text, run_end(text, k, len, is_lower_class), len)
    }
    if k == start {
      break
    }
    k -= 1
  }
  -1
}

///|
/// `[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]+[\p{Ll}\p{Lm}\p{Lo}\p{M}]*` followed by an
/// optional contraction. Shortening the leading part cannot move the end,
/// because the two classes overlap on exactly the characters that would be
/// handed over.
fn word_then_rest(text : StringView, start : Int32, len : Int32) -> Int32 {
  let capitals = run_end(text, start, len, is_upper_class)
  if capitals == start {
    return -1
  }
  with_contraction(text, run_end(text, capitals, len, is_lower_class), len)
}

///|
/// The end of the `o200k_base` match at `i`.
fn o200k_end(text : StringView, i : Int32, len : Int32) -> Int32 {
  let c = char_at(text, i)
  let prefixed = is_word_prefix(c) && i + 1 < len
  let after = if prefixed { step(text, i) } else { i }
  if prefixed {
    let e = capitals_then_word(text, after, len)
    if e >= 0 {
      return e
    }
  }
  let e = capitals_then_word(text, i, len)
  if e >= 0 {
    return e
  }
  if prefixed {
    let e = word_then_rest(text, after, len)
    if e >= 0 {
      return e
    }
  }
  let e = word_then_rest(text, i, len)
  if e >= 0 {
    return e
  }
  if is_number(c) {
    let mut e = i
    let mut n = 0
    while n < 3 && e < len && is_number(char_at(text, e)) {
      e = step(text, e)
      n += 1
    }
    return e
  }
  if c == ' ' && after < len && is_other(char_at(text, after)) {
    return run_end(
      text,
      run_end(text, after, len, is_other),
      len,
      is_line_or_slash,
    )
  }
  if is_other(c) {
    return run_end(text, run_end(text, i, len, is_other), len, is_line_or_slash)
  }
  let (stop, last) = space_run(text, i, len)
  let mut k = last
  while k >= i {
    if is_line_break(char_at(text, k)) {
      return run_end(text, k, len, is_line_break)
    }
    if k == i {
      break
    }
    k -= 1
  }
  if stop == len {
    return stop
  }
  if last > i {
    return last
  }
  stop
}

///|
/// The end of the `cl100k_base` match at `i`.
fn cl100k_end(text : StringView, i : Int32, len : Int32) -> Int32 {
  let c = char_at(text, i)
  let width = contraction_len(text, i, len)
  if width > 0 {
    return i + width
  }
  let after = if is_word_prefix(c) { step(text, i) } else { i }
  if after < len && is_letter(char_at(text, after)) {
    return run_end(text, after, len, is_letter)
  }
  if is_number(c) {
    let mut e = i
    let mut n = 0
    while n < 3 && e < len && is_number(char_at(text, e)) {
      e = step(text, e)
      n += 1
    }
    return e
  }
  if c == ' ' && after < len && is_other(char_at(text, after)) {
    return run_end(
      text,
      run_end(text, after, len, is_other),
      len,
      is_line_break,
    )
  }
  if is_other(c) {
    return run_end(text, run_end(text, i, len, is_other), len, is_line_break)
  }
  let (stop, last) = space_run(text, i, len)
  if stop == len {
    return stop
  }
  // `\s*[\r\n]` takes one line break together with the whitespace before it,
  // so a run of line breaks becomes one word each.
  let mut k = last
  while k >= i {
    if is_line_break(char_at(text, k)) {
      return step(text, k)
    }
    if k == i {
      break
    }
    k -= 1
  }
  if last > i {
    return last
  }
  stop
}

///|
/// The end of the `r50k`/`gpt2` match at `i`.
fn gpt2_end(text : StringView, i : Int32, len : Int32) -> Int32 {
  let c = char_at(text, i)
  if c == '\'' {
    // This pattern predates the case-insensitive flag, so `'S` stays outside.
    let j = step(text, i)
    if j < len {
      let first = char_at(text, j)
      let lower = ascii_lower(first) == first
      if lower && contraction_len(text, i, len) > 0 {
        return i + contraction_len(text, i, len)
      }
    }
  }
  let after = if c == ' ' { step(text, i) } else { i }
  if after < len && is_letter(char_at(text, after)) {
    return run_end(text, after, len, is_letter)
  }
  if after < len && is_number(char_at(text, after)) {
    return run_end(text, after, len, is_number)
  }
  if after < len && is_other(char_at(text, after)) {
    return run_end(text, after, len, is_other)
  }
  let (stop, last) = space_run(text, i, len)
  if stop == len {
    return stop
  }
  if last > i {
    return last
  }
  stop
}

///|
/// Appends the words of `text` under `rule` to `out`.
fn split_into(rule : Split, text : StringView, out : Array[StringView]) -> Unit {
  let len = text.length()
  match rule {
    Whole => out.push(text)
    Cl100k => {
      let mut i = 0
      while i < len {
        let e = cl100k_end(text, i, len)
        out.push(text.exact_view(start=i, end=e))
        i = e
      }
    }
    O200k => {
      let mut i = 0
      while i < len {
        let e = o200k_end(text, i, len)
        out.push(text.exact_view(start=i, end=e))
        i = e
      }
    }
    Gpt2 => {
      let mut i = 0
      while i < len {
        let e = gpt2_end(text, i, len)
        out.push(text.exact_view(start=i, end=e))
        i = e
      }
    }
    Whitespace => {
      let mut i = 0
      while i < len {
        if is_space(char_at(text, i)) {
          i = step(text, i)
          continue
        }
        let e = run_end(text, i, len, fn(c) { !is_space(c) })
        out.push(text.exact_view(start=i, end=e))
        i = e
      }
    }
    Metaspace => {
      let mut i = 0
      let mut start = 0
      let mut started = false
      while i < len {
        if char_at(text, i).to_int() == 0x2581 {
          if started {
            out.push(text.exact_view(start~, end=i))
          }
          start = i
          started = true
        }
        i = step(text, i)
      }
      if i > start {
        out.push(text.exact_view(start~, end=i))
      }
    }
    Digits(d) => {
      let mut i = 0
      while i < len {
        let e = if is_number(char_at(text, i)) {
          if d.individual {
            step(text, i)
          } else {
            run_end(text, i, len, is_number)
          }
        } else {
          run_end(text, i, len, fn(c) { !is_number(c) })
        }
        out.push(text.exact_view(start=i, end=e))
        i = e
      }
    }
    Sequence(rules) => {
      let mut current : Array[StringView] = [text]
      for rule in rules {
        let next : Array[StringView] = []
        for piece in current {
          split_into(rule, piece, next)
        }
        current = next
      }
      for piece in current {
        out.push(piece)
      }
    }
  }
}

///|
/// The words of `text`, in order. Joining them gives back the text under every
/// rule but `Whitespace`, which drops what it splits on.
pub fn Split::pieces(self : Split, text : StringView) -> Array[StringView] {
  let out : Array[StringView] = []
  split_into(self, text, out)
  out
}
