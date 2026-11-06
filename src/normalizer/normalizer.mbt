// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The normalisation a model expects: the rule table it was trained with, and
/// the three switches around whitespace.
pub(all) struct Spec {
  name : String
  charsmap : Bytes
  add_dummy_prefix : Bool
  remove_extra_whitespaces : Bool
  escape_whitespaces : Bool
}

///|
/// One step of a normalisation that is a list of Unicode operations rather
/// than a rule table.
pub(all) enum Stage {
  ///
  /// Canonical composition.
  Nfc
  ///
  /// Canonical decomposition.
  Nfd
  ///
  /// Compatibility composition.
  Nfkc
  ///
  /// Compatibility decomposition.
  Nfkd
  ///
  /// Unicode lower case.
  Lowercase
  ///
  /// Put this text in front.
  Prepend(String)
  ///
  /// Put this text in front unless the text already starts with it, which is
  /// how a cut that keeps its word break stays honest about a text that has
  /// one already.
  Pad(String)
  ///
  /// Replace every occurrence of the first text with the second.
  Replace(String, String)
  ///
  /// Drop whitespace from both ends.
  Trim
  ///
  /// Replace a space with U+2581, the marker pieces use for a word break.
  EscapeSpace
}

///|
/// Which of the three normalisations this is.
pub enum Mode {
  Identity
  Rule
  Chain
}

///|
/// The normalisation applied before segmentation.
///
/// A model file carries its own rule table, which is why this is not just a
/// list of operations: the table is a trie of a few thousand replacements, and
/// applying it is what makes two spellings of one character segment alike.
pub struct Normalizer {
  mode : Mode
  add_dummy_prefix : Bool
  remove_extra_whitespaces : Bool
  escape_whitespaces : Bool
  treat_whitespace_as_suffix : Bool
  trie : Array[UInt32]
  replacements : Bytes
  user_defined : Map[Int32, Array[Bytes]]
  stages : Array[Stage]
}

///|
/// What one broken byte of the input becomes.
let replacement : Bytes = b"\xEF\xBF\xBD"

///|
/// A normalisation that changes nothing.
pub fn Normalizer::identity() -> Normalizer {
  {
    mode: Identity,
    add_dummy_prefix: false,
    remove_extra_whitespaces: false,
    escape_whitespaces: false,
    treat_whitespace_as_suffix: false,
    trie: [],
    replacements: b"",
    user_defined: Map([]),
    stages: [],
  }
}

///|
/// A normalisation from a list of operations, applied in order.
pub fn Normalizer::chain(stages : Array[Stage]) -> Normalizer {
  {
    mode: Chain,
    add_dummy_prefix: false,
    remove_extra_whitespaces: false,
    escape_whitespaces: false,
    treat_whitespace_as_suffix: false,
    trie: [],
    replacements: b"",
    user_defined: Map([]),
    stages,
  }
}

///|
/// The rule table of a model file.
///
/// `user_defined` are the symbols the caller reserved: the normaliser hands
/// them through untouched, so that a piece spelled the way the caller wrote it
/// stays findable.
pub fn Normalizer::rule(
  spec~ : Spec,
  user_defined~ : Array[Bytes] = [],
  treat_whitespace_as_suffix~ : Bool = false,
) -> Normalizer raise @refused.Refused {
  let mut units : Array[UInt32] = []
  let mut replacements = b""
  if !spec.charsmap.is_empty() {
    let blob = spec.charsmap
    if blob.length() <= 4 {
      raise @refused.Malformed("the rule table is too short", 0)
    }
    let size = (blob[0].to_int() & 0xFF) |
      ((blob[1].to_int() & 0xFF) << 8) |
      ((blob[2].to_int() & 0xFF) << 16) |
      ((blob[3].to_int() & 0xFF) << 24)
    if size < 1024 || size % 1024 != 0 || size + 4 >= blob.length() {
      raise @refused.Malformed("the rule table has no room for its trie", size)
    }
    units = Trie::of(blob[4:4 + size].to_owned()).units
    replacements = blob[4 + size:].to_owned()
    if replacements[replacements.length() - 1] != b'\x00' {
      raise @refused.Malformed(
        "the replacement text is not terminated",
        replacements.length(),
      )
    }
  }
  let by_first = user_index(user_defined)
  {
    mode: Rule,
    add_dummy_prefix: spec.add_dummy_prefix,
    remove_extra_whitespaces: spec.remove_extra_whitespaces,
    escape_whitespaces: spec.escape_whitespaces,
    treat_whitespace_as_suffix,
    trie: units,
    replacements,
    user_defined: by_first,
    stages: [],
  }
}

///|
/// The replacement text that starts at `at`, up to its terminator.
fn Normalizer::entry(self : Normalizer, at : Int32) -> BytesView {
  let mut stop = at
  while stop < self.replacements.length() && self.replacements[stop] != b'\x00' {
    stop = stop + 1
  }
  self.replacements[at:stop]
}

///|
/// The next chunk of the input and how many bytes it used: a reserved symbol,
/// a rule match, or one code point.
fn Normalizer::prefix(
  self : Normalizer,
  input : Bytes,
  at : Int32,
) -> (BytesView, Int32) raise @refused.Refused {
  match longest_reserved(self.user_defined, input, at) {
    Some(width) => return (input[at:at + width], width)
    None => ()
  }
  let mut longest = 0
  let mut value = 0
  if !self.trie.is_empty() {
    let trie : Trie = { units: self.trie, }
    for hit in trie.prefixes(input, at, input.length()) {
      let (length, offset) = hit
      if length > longest {
        longest = length
        value = offset
      }
    }
  }
  if longest == 0 ||
    at + longest > input.length() ||
    value >= self.replacements.length() {
    let width = @split.utf8_width_at(input, at)
    if width == 0 {
      return (replacement[:], 1)
    }
    return (input[at:at + width], width)
  }
  (self.entry(value), longest)
}

///|
/// The normalised bytes.
fn Normalizer::apply_rule(
  self : Normalizer,
  input : Bytes,
) -> Bytes raise @refused.Refused {
  let out : Array[Byte] = []
  if input.length() == 0 {
    return b""
  }
  let spaces : Bytes = if self.escape_whitespaces {
    b"\xE2\x96\x81"
  } else {
    b" "
  }
  let mut at = 0
  if self.remove_extra_whitespaces {
    while at < input.length() {
      let (chunk, width) = self.prefix(input, at)
      if chunk.length() != 1 || chunk[0] != b' ' {
        break
      }
      at = at + width
    }
  }
  if at >= input.length() {
    return b""
  }
  if !self.treat_whitespace_as_suffix && self.add_dummy_prefix {
    for i = 0; i < spaces.length(); i = i + 1 {
      out.push(spaces[i])
    }
  }
  let mut previous_was_space = self.remove_extra_whitespaces
  while at < input.length() {
    let (chunk, width) = self.prefix(input, at)
    let mut from = 0
    if previous_was_space {
      while from < chunk.length() && chunk[from] == b' ' {
        from = from + 1
      }
    }
    if from < chunk.length() {
      for i = from; i < chunk.length(); i = i + 1 {
        if chunk[i] == b' ' {
          for k = 0; k < spaces.length(); k = k + 1 {
            out.push(spaces[k])
          }
        } else {
          out.push(chunk[i])
        }
      }
      previous_was_space = chunk[chunk.length() - 1] == b' '
    }
    at = at + width
    if !self.remove_extra_whitespaces {
      previous_was_space = false
    }
  }
  if self.remove_extra_whitespaces {
    while out.length() >= spaces.length() {
      let mut tail = true
      for i = 0; i < spaces.length(); i = i + 1 {
        if out[out.length() - spaces.length() + i] != spaces[i] {
          tail = false
          break
        }
      }
      if !tail {
        break
      }
      for i = 0; i < spaces.length(); i = i + 1 {
        ignore(out.pop())
      }
    }
  }
  if self.treat_whitespace_as_suffix && self.add_dummy_prefix {
    for i = 0; i < spaces.length(); i = i + 1 {
      out.push(spaces[i])
    }
  }
  Bytes::from_array(out)
}

///|
/// Replaces every space with U+2581.
fn replace_space(bytes : Bytes) -> Bytes {
  let out : Array[Byte] = []
  for i = 0; i < bytes.length(); i = i + 1 {
    if bytes[i] == b' ' {
      out.push(b'\xE2')
      out.push(b'\x96')
      out.push(b'\x81')
    } else {
      out.push(bytes[i])
    }
  }
  Bytes::from_array(out)
}

///|
/// Applies one operation of a chain.
fn apply_stage(stage : Stage, text : String) -> String {
  match stage {
    Nfc => @normalize.normalize(@normalize.NFC, text[:])
    Nfd => @normalize.normalize(@normalize.NFD, text[:])
    Nfkc => @normalize.normalize(@normalize.NFKC, text[:])
    Nfkd => @normalize.normalize(@normalize.NFKD, text[:])
    Lowercase => @ucd.lower(text[:])
    Prepend(prefix) => prefix + text
    Pad(prefix) => if text.has_prefix(prefix[:]) { text } else { prefix + text }
    Replace(from, to) => text.replace_all(old=from[:], new=to[:])
    Trim => text[:].trim().to_owned()
    EscapeSpace => @utf8.decode_lossy(replace_space(@utf8.encode(text[:])))
  }
}

///|
/// Whether a word-break marker at the very front of the text stands for a space
/// the text does not have, rather than one it does.
///
/// A model that adds a leading space puts a marker there on the way in, and
/// taking it off again on the way out is what makes the round trip exact. A
/// model that also drops runs of whitespace keeps taking them off until the
/// text has a character in it, because everything it saw at the front was
/// whitespace it meant to discard.
pub fn Normalizer::strips_leading_marker(self : Normalizer) -> Bool {
  match self.mode {
    Identity => false
    Rule => self.add_dummy_prefix || self.remove_extra_whitespaces
    Chain => {
      let mut found = false
      for stage in self.stages {
        match stage {
          Pad(text) => if text.contains_char('\u{2581}') { found = true }
          EscapeSpace => found = true
          _ => ()
        }
      }
      found
    }
  }
}

///|
/// Whether every marker at the front comes off, not only the first.
pub fn Normalizer::strips_every_leading_marker(self : Normalizer) -> Bool {
  match self.mode {
    Rule => self.remove_extra_whitespaces
    _ => false
  }
}

///|
/// The text as it goes into segmentation.
pub fn Normalizer::apply(
  self : Normalizer,
  text : StringView,
) -> String raise @refused.Refused {
  match self.mode {
    Identity => text.to_owned()
    Rule => @utf8.decode_lossy(self.apply_rule(@utf8.encode(text)))
    Chain => {
      let mut current = text.to_owned()
      for stage in self.stages {
        current = apply_stage(stage, current)
      }
      current
    }
  }
}
