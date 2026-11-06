// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A double-array trie, the shape a sentence-piece normalisation rule table
/// ships in.
///
/// The table maps byte strings to offsets in the replacement text, so it is
/// read as a plain array of 32-bit units; two bits of the unit widen the
/// offset, which is why the arithmetic below is unsigned.
priv struct Trie {
  units : Array[UInt32]
}

///|
fn Trie::of(blob : Bytes) -> Trie raise @refused.Refused {
  if blob.length() % 4 != 0 {
    raise @refused.Malformed("the trie is not a whole number of units", 0)
  }
  let units : Array[UInt32] = []
  let mut i = 0
  while i < blob.length() {
    let word = (blob[i].to_int() & 0xFF).reinterpret_as_uint() |
      ((blob[i + 1].to_int() & 0xFF).reinterpret_as_uint() << 8) |
      ((blob[i + 2].to_int() & 0xFF).reinterpret_as_uint() << 16) |
      ((blob[i + 3].to_int() & 0xFF).reinterpret_as_uint() << 24)
    units.push(word)
    i = i + 4
  }
  if units.is_empty() {
    raise @refused.Absent("the trie has no units")
  }
  { units, }
}

///|
fn Trie::unit(self : Trie, at : Int32) -> UInt32 raise @refused.Refused {
  if at < 0 || at >= self.units.length() {
    raise @refused.Malformed("the trie points outside itself", at)
  }
  self.units[at]
}

///|
fn Trie::label(unit : UInt32) -> UInt32 {
  unit & 0x800000FFU
}

///|
fn Trie::has_leaf(unit : UInt32) -> Bool {
  ((unit >> 8) & 1U) == 1U
}

///|
fn Trie::value(unit : UInt32) -> Int32 {
  (unit & 0x7FFFFFFFU).reinterpret_as_int()
}

///|
fn Trie::offset(unit : UInt32) -> UInt32 {
  unit >> 10 << ((unit & 0x200U) >> 6).reinterpret_as_int()
}

///|
/// Every key that is a prefix of the bytes in `[from, to)`, as the length of
/// the key and the value stored with it.
fn Trie::prefixes(
  self : Trie,
  key : BytesView,
  from : Int32,
  to : Int32,
) -> Array[(Int32, Int32)] raise @refused.Refused {
  let found : Array[(Int32, Int32)] = []
  let unit0 = self.unit(0)
  let mut at = Trie::offset(unit0)
  let mut i = from
  while i < to {
    let b = (key[i].to_int() & 0xFF).reinterpret_as_uint()
    at = at ^ b
    let unit = self.unit(at.reinterpret_as_int())
    if Trie::label(unit) != b {
      return found
    }
    at = at ^ Trie::offset(unit)
    if Trie::has_leaf(unit) {
      found.push(
        (i + 1 - from, Trie::value(self.unit(at.reinterpret_as_int()))),
      )
    }
    i = i + 1
  }
  found
}
