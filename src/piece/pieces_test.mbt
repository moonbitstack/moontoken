// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn piece(text : String, score : Float, kind : @piece.Kind) -> @piece.Piece {
  { text: @utf8.encode(text), score, kind, }
}

///|
test "a piece is found by its text and by its id" {
  let pieces = @piece.Pieces::new(
    items=[
      piece("<unk>", 0.0F, Unknown),
      piece("a", -1.0F, Normal),
      piece("ab", -2.0F, Normal),
      piece("<SPECIAL>", 0.0F, UserDefined),
      piece("<0x41>", 0.0F, RawByte),
    ],
    unk_id=0,
  )
  assert_eq(pieces.length(), 5)
  assert_eq(pieces.id(b"ab"[:]), Some(2))
  assert_eq(pieces.id(b"zz"[:]), None)
  assert_eq(pieces.lattice_id(b"ab"[:]), Some(2))
  // A reserved symbol is not part of the lattice a segmentation walks.
  assert_eq(pieces.lattice_id(b"<unk>"[:]), None)
  assert_eq(pieces.lattice_id(b"<SPECIAL>"[:]), Some(3))
  assert_eq(pieces.byte_id(0x41), 4)
  // A reserved symbol takes part in segmentation, and can be the longest one.
  assert_eq(pieces.longest(), 9)
}

///|
test "a piece that appears twice is refused" {
  let outcome = Ok(
    @piece.Pieces::new(items=[
      piece("a", 0.0F, Normal),
      piece("a", 0.0F, Normal),
    ]),
  ) catch {
    err => Err(err)
  }
  match outcome {
    Ok(_) => panic()
    Err(@refused.Malformed(_, at)) => assert_eq(at, 1)
    Err(_) => panic()
  }
}

///|
test "byte fallback without every byte is refused" {
  let outcome = Ok(
    @piece.Pieces::new(
      items=[piece("a", 0.0F, Normal), piece("<0x41>", 0.0F, RawByte)],
      byte_fallback=true,
    ),
  ) catch {
    err => Err(err)
  }
  match outcome {
    Ok(_) => panic()
    Err(_) => ()
  }
}

///|
test "a byte is written the way the model files write it" {
  assert_eq(@piece.byte_piece(0), "<0x00>")
  assert_eq(@piece.byte_piece(0x41), "<0x41>")
  assert_eq(@piece.byte_piece(0xFF), "<0xFF>")
}

///|
test "an id outside the vocabulary is refused" {
  let pieces = @piece.Pieces::new(items=[piece("a", 0.0F, Normal)])
  let outcome = Ok(pieces.at(7)) catch { err => Err(err) }
  match outcome {
    Ok(_) => panic()
    Err(@refused.Missing(id)) => assert_eq(id, 7)
    Err(_) => panic()
  }
}
