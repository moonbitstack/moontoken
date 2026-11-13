// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Where a special token was found.
pub(all) struct Hit {
  ///
  /// The offset of its first code unit.
  start : Int32
  ///
  /// The text it is written as.
  text : String
  ///
  /// The id it stands for.
  id : Int32
}

///|
/// What may happen to the tokens a model reserves.
///
/// A model reserves a handful of spellings, `<|endoftext|>` and the like, that
/// stand for structure rather than text. Whether text that happens to contain
/// one is taken as the token, taken as text, or refused is the caller's
/// decision, never the library's.
pub(all) enum Policy {
  ///
  /// No reserved token is recognised, and text that holds one is refused.
  Refuse
  ///
  /// Every reserved token in the table is recognised.
  Allow
  ///
  /// No reserved token is recognised; text that holds one is encoded as text.
  Ignore
  ///
  /// Only the named tokens are recognised, and the rest are refused.
  Only(Array[String])
}

///|
/// The tokens a model reserves, by spelling.
pub struct Table {
  texts : Array[String]
  ids : Array[Int32]
  by_first : Map[Int32, Array[Int32]]
  index_of : Map[String, Int32]
  text_of : Map[Int32, String]
}

///|
/// A table with nothing in it.
pub fn Table::empty() -> Table {
  {
    texts: [],
    ids: [],
    by_first: Map([]),
    index_of: Map([]),
    text_of: Map([]),
  }
}

///|
/// A table from spellings and their ids.
///
/// A spelling that appears twice keeps the first id, which is how a model file
/// that lists the same control token twice still has one answer.
pub fn Table::of(pairs : Array[(String, Int32)]) -> Table {
  let table = Table::empty()
  for pair in pairs {
    table.add(pair.0, pair.1)
  }
  table
}

///|
/// Adds a spelling. An empty spelling is ignored: it would match everywhere.
///
/// Two spellings may share an id, which is how a vocabulary that renamed one
/// of its placeholders keeps the old spelling readable; the first spelling
/// added is the one the id is written back as, so the reverse direction stays
/// single-valued.
pub fn Table::add(self : Table, text : String, id : Int32) -> Unit {
  if text.is_empty() || self.index_of.contains(text) {
    return
  }
  let index = self.texts.length()
  self.texts.push(text)
  self.ids.push(id)
  self.index_of.set(text, index)
  if !self.text_of.contains(id) {
    self.text_of.set(id, text)
  }
  let key = text.at(0).to_int()
  match self.by_first.get(key) {
    Some(list) => list.push(index)
    None => self.by_first.set(key, [index])
  }
}

///|
/// How many tokens the table holds.
pub fn Table::length(self : Table) -> Int32 {
  self.texts.length()
}

///|
/// The spelling of an id, when the id is one the table holds.
pub fn Table::text(self : Table, id : Int32) -> String? {
  self.text_of.get(id)
}

///|
/// The id of a spelling.
pub fn Table::id(self : Table, text : StringView) -> Int32? {
  match self.index_of.get_from_string(text) {
    Some(index) => Some(self.ids[index])
    None => None
  }
}

///|
/// The indexes of the spellings that could start with the code unit at `at`.
fn Table::candidates(
  self : Table,
  text : StringView,
  at : Int32,
) -> Array[Int32] {
  if at >= text.length() {
    return []
  }
  match self.by_first.get(text.at(at).to_int()) {
    Some(list) => list
    None => []
  }
}

///|
/// The offset just past the code point at `at`.
fn advance(text : StringView, at : Int32) -> Int32 {
  let unit = text.at(at).to_int()
  if unit >= 0xD800 && unit <= 0xDBFF && at + 1 < text.length() {
    let low = text.at(at + 1).to_int()
    if low >= 0xDC00 && low <= 0xDFFF {
      return at + 2
    }
  }
  at + 1
}

///|
/// Whether the spelling `candidate` stands at `at`.
///
/// Compared a code unit at a time rather than by slicing, because a spelling
/// is shorter than the text it is looked for in and a slice of that text can
/// land in the middle of a surrogate pair.
fn stands_at(text : StringView, at : Int32, candidate : String) -> Bool {
  for i = 0; i < candidate.length(); i = i + 1 {
    if text.at(at + i).to_int() != candidate.at(i).to_int() {
      return false
    }
  }
  true
}

///|
/// The longest reserved token at or after `from`, and where it stands.
pub fn Table::find(self : Table, text : StringView, from : Int32) -> Hit? {
  let mut at = from
  while at < text.length() {
    let mut best = -1
    for index in self.candidates(text, at) {
      let candidate = self.texts[index]
      let width = candidate.length()
      if width > best &&
        at + width <= text.length() &&
        stands_at(text, at, candidate) {
        best = width
      }
    }
    if best > 0 {
      let spelling = text.exact_view(start=at, end=at + best)
      match self.id(spelling) {
        Some(id) => return Some({ start: at, text: spelling.to_owned(), id, })
        None => ()
      }
    }
    at = advance(text, at)
  }
  None
}

///|
/// Whether `policy` recognises `text`.
pub fn Policy::allows(self : Policy, text : StringView) -> Bool {
  match self {
    Allow => true
    Refuse | Ignore => false
    Only(names) => {
      let mut found = false
      for name in names {
        if name[:] == text {
          found = true
        }
      }
      found
    }
  }
}

///|
/// Whether the policy looks for reserved tokens at all.
pub fn Policy::recognizes(self : Policy) -> Bool {
  match self {
    Ignore => false
    _ => true
  }
}

///|
/// The special tokens of `cl100k_base`, and of `o200k_base` and the two
/// earlier encodings, which share the first one.
///
/// The ids are the ones the published encodings give them, and the file of
/// mergeable ranks does not carry them: they are part of the encoding's
/// definition, not of the table a caller loads.
pub fn cl100k_base() -> Table {
  Table::of([
    ("<|endoftext|>", 100257),
    ("<|fim_prefix|>", 100258),
    ("<|fim_middle|>", 100259),
    ("<|fim_suffix|>", 100260),
    ("<|endofprompt|>", 100276),
  ])
}

///|
/// The special tokens of `o200k_base`.
pub fn o200k_base() -> Table {
  Table::of([("<|endoftext|>", 199999), ("<|endofprompt|>", 200018)])
}

///|
/// The special tokens of `o200k_harmony`, the encoding the harmony chat format
/// writes its control words with over the `o200k_base` table.
///
/// Ten spellings carry meaning and the rest of the range the format reserves is
/// spelled `<|reserved_NNNNNN|>`: a message written before a control word had a
/// name still decodes, rather than the id falling off the end of the vocabulary.
/// Id 200018 is both — `<|endofprompt|>` was named first, and the placeholder
/// over the same id is kept as an alias, which is the one place a spelling and
/// its id do not pair up.
pub fn o200k_harmony() -> Table {
  let table = o200k_base()
  let named : Array[(String, Int32)] = [
    ("<|startoftext|>", 199998),
    ("<|return|>", 200002),
    ("<|constrain|>", 200003),
    ("<|channel|>", 200005),
    ("<|start|>", 200006),
    ("<|end|>", 200007),
    ("<|message|>", 200008),
    ("<|call|>", 200012),
  ]
  for pair in named {
    let (text, id) = pair
    table.add(text, id)
  }
  for id = 200000; id <= 201087; id = id + 1 {
    if table.text(id) is None {
      table.add("<|reserved_\{id}|>", id)
    }
  }
  table.add("<|reserved_200018|>", 200018)
  table
}

///|
/// The special token of `r50k_base` and `p50k_base`.
pub fn r50k_base() -> Table {
  Table::of([("<|endoftext|>", 50256)])
}

///|
/// The special tokens of `p50k_edit`, the pair of `r50k_base` plus the three
/// fill-in-the-middle markers.
pub fn p50k_edit() -> Table {
  Table::of([
    ("<|endoftext|>", 50256),
    ("<|fim_prefix|>", 50281),
    ("<|fim_middle|>", 50282),
    ("<|fim_suffix|>", 50283),
  ])
}
