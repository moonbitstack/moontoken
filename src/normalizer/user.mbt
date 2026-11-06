// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// An index of the symbols a caller reserved, by their first byte, so that
/// finding the one at a position costs a map lookup rather than a scan of the
/// whole list.
pub fn user_index(symbols : Array[Bytes]) -> Map[Int32, Array[Bytes]] {
  let index : Map[Int32, Array[Bytes]] = Map([])
  for symbol in symbols {
    if symbol.length() == 0 {
      continue
    }
    let key = symbol[0].to_int() & 0xFF
    match index.get(key) {
      Some(list) => list.push(symbol)
      None => index.set(key, [symbol])
    }
  }
  index
}

///|
/// The number of bytes of the longest reserved symbol that starts at `at`.
pub fn longest_reserved(
  index : Map[Int32, Array[Bytes]],
  input : Bytes,
  at : Int32,
) -> Int32? {
  match index.get(input[at].to_int() & 0xFF) {
    Some(list) => {
      let mut longest = -1
      for symbol in list {
        if symbol.length() > longest && at + symbol.length() <= input.length() {
          let mut same = true
          for i = 0; i < symbol.length(); i = i + 1 {
            if symbol[i] != input[at + i] {
              same = false
              break
            }
          }
          if same {
            longest = symbol.length()
          }
        }
      }
      if longest < 0 {
        None
      } else {
        Some(longest)
      }
    }
    None => None
  }
}
