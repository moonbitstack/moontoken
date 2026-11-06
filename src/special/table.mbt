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
  text_of : Map[Int32, String]
}

///|
/// A table with nothing in it.
pub fn Table::empty() -> Table {
  { texts: [], ids: [], by_first: Map([]), text_of: Map([]), }
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
pub fn Table::add(self : Table, text : String, id : Int32) -> Unit {
  if text.is_empty() || self.text_of.contains(id) {
    return
  }
  let index = self.texts.length()
  self.texts.push(text)
  self.ids.push(id)
  self.text_of.set(id, text)
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
  let mut found = None
  for index in self.candidates(text, 0) {
    if self.texts[index][:] == text {
      found = Some(self.ids[index])
    }
  }
  found
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
/// The longest reserved token at or after `from`.
pub fn Table::find(self : Table, text : StringView, from : Int32) -> Hit? {
  let mut at = from
  while at < text.length() {
    let mut best = -1
    for index in self.candidates(text, at) {
      let candidate = self.texts[index]
      if candidate.length() > best && at + candidate.length() <= text.length() {
        if text.exact_view(start=at, end=at + candidate.length()) == candidate {
          best = candidate.length()
        }
      }
    }
    if best > 0 {
      let entry = self.id(text.exact_view(start=at, end=at + best)).unwrap()
      return Some({
        start: at,
        text: text.exact_view(start=at, end=at + best).to_owned(),
        id: entry,
      })
    }
    at = at + 1
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
