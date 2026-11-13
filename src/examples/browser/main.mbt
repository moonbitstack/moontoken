// The pages' engine: the library compiled to JavaScript, with the specimen
// vocabulary the pages print. Every function returns JSON text, so the page
// draws what the library computed and never re-implements a step of it.

///|
/// The specimen vocabulary: one entry per byte, then merges in an order that
/// shows what a merge buys. Small on purpose — the page prints all of it, and
/// a table a reader can see whole explains the idea better than one they
/// cannot.
fn specimen() -> @vocab.Ranks raise {
  let pairs : Array[(Bytes, Int32)] = []
  for b = 0; b < 256; b = b + 1 {
    pairs.push((Bytes::make(1, b.to_byte()), b))
  }
  let merges : Array[(String, Int32)] = [
    ("th", 256),
    ("he", 257),
    ("the", 258),
    ("in", 259),
    ("ing", 260),
    (" a", 261),
    ("nd", 262),
    (" and", 263),
    (" w", 264),
    ("or", 265),
    ("orl", 266),
    ("orld", 267),
    (" world", 268),
    (" t", 269),
    (" the", 270),
    ("ng", 271),
    ("re", 272),
    ("er", 273),
    ("es", 274),
    ("on", 275),
    ("at", 276),
    ("en", 277),
    ("is", 278),
    ("it", 279),
    ("of", 280),
    ("to", 281),
    ("an", 282),
    ("ou", 283),
    ("ed", 284),
  ]
  for i = 0; i < merges.length(); i = i + 1 {
    let (token, rank) = merges[i]
    pairs.push((@utf8.encode(token), rank))
  }
  @vocab.Ranks::from_pairs(pairs)
}

///|
/// The tokenizer the pages run: the published `cl100k_base` rules over the
/// specimen table, so the splitting is the real thing and only the vocabulary
/// is small.
fn specimen_tokenizer() -> @moontoken.Tokenizer raise {
  @moontoken.Tokenizer::cl100k(ranks=specimen())
}

///|
/// The library's error in one line, for a page that has nowhere to put an
/// error's structure.
fn describe(error : Error) -> String {
  match error {
    @refused.Malformed(what, at) => "malformed at \{at}: \{what}"
    @refused.Absent(name) => "absent: \{name}"
    @refused.Unsupported(what) => "unsupported: \{what}"
    @refused.Missing(id) => "no token with id \{id}"
    @refused.Disallowed(what, at) => "disallowed at \{at}: \{what}"
    _ => "refused"
  }
}

///|
fn refused(message : String) -> String {
  @moonjson.dumps(
    @json.Json::object(Map([("refused", @json.Json::string(message))])),
  )
}

///|
/// Text in: the tokens it became, in order, each with its id and its bytes;
/// the counts a reader wants; and the text the same ids decode back to. The
/// decode is a second trip through the library, not a copy of the input.
pub fn compose(text : String) -> String {
  let tokenizer = specimen_tokenizer() catch {
    e => return refused(describe(e))
  }
  let ids = tokenizer.encode(text) catch { e => return refused(describe(e)) }
  let decoded = tokenizer.decode(ids) catch { e => return refused(describe(e)) }
  let tokens : Array[Json] = []
  let plain : Array[Json] = []
  for id in ids {
    plain.push(@json.Json::number(id.to_double()))
    let bytes = match tokenizer.token_bytes(id) {
      Some(b) => b
      None => Bytes::make(0, 0)
    }
    tokens.push(
      @json.Json::object(
        Map([
          ("id", @json.Json::number(id.to_double())),
          ("hex", @json.Json::string(@base16.encode(bytes))),
          ("bytes", @json.Json::number(bytes.length().to_double())),
        ]),
      ),
    )
  }
  @json.Json::object(
    Map([
      ("tokens", @json.Json::array(tokens)),
      ("ids", @json.Json::array(plain)),
      ("count", @json.Json::number(ids.length().to_double())),
      ("bytes", @json.Json::number(@utf8.encode(text).length().to_double())),
      ("decoded", @json.Json::string(decoded)),
      ("vocabulary", @json.Json::number(tokenizer.length().to_double())),
    ]),
  )
  |> @moonjson.dumps
}

///|
/// Every entry of the specimen table, which the page draws as a type case:
/// id and bytes, in id order.
pub fn table() -> String {
  let ranks = specimen() catch { e => return refused(describe(e)) }
  let entries : Array[Json] = []
  for id = 0; id < ranks.length(); id = id + 1 {
    let bytes = match ranks.token(id) {
      Some(b) => b
      None => Bytes::make(0, 0)
    }
    entries.push(
      @json.Json::object(
        Map([
          ("id", @json.Json::number(id.to_double())),
          ("hex", @json.Json::string(@base16.encode(bytes))),
        ]),
      ),
    )
  }
  @json.Json::object(
    Map([
      ("entries", @json.Json::array(entries)),
      ("vocabulary", @json.Json::number(ranks.length().to_double())),
    ]),
  )
  |> @moonjson.dumps
}

///|
/// What the page says about its own engine: how many entries the table has,
/// how many of them are merges, and whether any byte value is missing.
pub fn spec() -> String {
  let ranks = specimen() catch { e => return refused(describe(e)) }
  @json.Json::object(
    Map([
      ("vocabulary", @json.Json::number(ranks.length().to_double())),
      ("single_bytes", @json.Json::number(256.0)),
      ("merges", @json.Json::number((ranks.length() - 256).to_double())),
      (
        "missing",
        @json.Json::number(ranks.missing_bytes().length().to_double()),
      ),
    ]),
  )
  |> @moonjson.dumps
}
