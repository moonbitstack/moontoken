// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Why an input was refused.
///
/// `Malformed` carries the offset, `Absent` the name of what was missing, and
/// `Missing` the id that is not in the vocabulary, so that a caller reading a
/// table of a hundred thousand entries can find the one that broke.
pub(all) suberror Refused {
  ///
  /// The bytes are not the shape this reader accepts.
  Malformed(String, Int32)
  ///
  /// A required piece of the input is not there.
  Absent(String)
  ///
  /// The input asks for something this reader does not implement.
  Unsupported(String)
  ///
  /// There is no token with this id.
  Missing(Int32)
  ///
  /// The text holds a token that the caller did not allow here.
  Disallowed(String, Int32)
}
