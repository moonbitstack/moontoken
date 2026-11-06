// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The width of the UTF-8 sequence that starts at `at`, or 0 when the bytes
/// there are not one.
pub fn utf8_width_at(bytes : Bytes, at : Int32) -> Int32 {
  let b = bytes[at].to_int() & 0xFF
  let width = if b < 0x80 {
    1
  } else if b >= 0xC2 && b <= 0xDF {
    2
  } else if b >= 0xE0 && b <= 0xEF {
    3
  } else if b >= 0xF0 && b <= 0xF4 {
    4
  } else {
    return 0
  }
  if at + width > bytes.length() {
    return 0
  }
  for i = 1; i < width; i = i + 1 {
    let c = bytes[at + i].to_int() & 0xFF
    if c < 0x80 || c > 0xBF {
      return 0
    }
  }
  width
}
