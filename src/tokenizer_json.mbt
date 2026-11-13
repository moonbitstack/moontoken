// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The value of a field of a JSON object.
fn field(json : Json, name : String) -> Json? {
  match json {
    Object(object) => object.get(name)
    _ => None
  }
}

///|
fn object_of(json : Json) -> Map[String, Json]? {
  match json {
    Object(object) => Some(object)
    _ => None
  }
}

///|
fn as_text(json : Json) -> String? {
  match json {
    String(text) => Some(text)
    _ => None
  }
}

///|
fn as_number(json : Json) -> Double? {
  match json {
    Number(number, ..) => Some(number)
    _ => None
  }
}

///|
fn as_bool(json : Json) -> Bool? {
  match json {
    True => Some(true)
    False => Some(false)
    _ => None
  }
}

///|
fn as_array(json : Json) -> Array[Json]? {
  match json {
    Array(items) => Some(items)
    _ => None
  }
}

///|
fn is_null(json : Json) -> Bool {
  match json {
    Null => true
    _ => false
  }
}

///|
fn text_of(json : Json, name : String) -> String? {
  match field(json, name) {
    Some(value) => as_text(value)
    None => None
  }
}

///|
fn flag_of(json : Json, name : String, fallback : Bool) -> Bool {
  match field(json, name) {
    Some(value) =>
      match as_bool(value) {
        Some(flag) => flag
        None => fallback
      }
    None => fallback
  }
}

///|
fn count_of(json : Json, name : String, fallback : Int32) -> Int32 {
  match field(json, name) {
    Some(value) =>
      match as_number(value) {
        Some(number) => number.to_int()
        None => fallback
      }
    None => fallback
  }
}

///|
fn array_of(json : Json, name : String) -> Array[Json] {
  match field(json, name) {
    Some(value) =>
      match as_array(value) {
        Some(items) => items
        None => []
      }
    None => []
  }
}

///|
/// The pre-tokenizer, as the cut itself and the steps in front of it.
fn read_pre_tokenizer(
  json : Json?,
  stages : Array[@normalizer.Stage],
) -> @split.Split raise @refused.Refused {
  let spec = match json {
    Some(spec) => spec
    None => return @split.Whole
  }
  if is_null(spec) {
    return @split.Whole
  }
  let kind = match text_of(spec, "type") {
    Some(kind) => kind
    None => raise @refused.Malformed("a pre-tokenizer has no type", 0)
  }
  match kind {
    "ByteLevel" => {
      if flag_of(spec, "add_prefix_space", false) {
        stages.push(@normalizer.Pad(" "))
      }
      if flag_of(spec, "use_regex", true) {
        @split.Gpt2
      } else {
        @split.Whole
      }
    }
    "Metaspace" => {
      let replacement = match text_of(spec, "replacement") {
        Some(text) => text
        None => "\u{2581}"
      }
      if replacement != "\u{2581}" {
        raise @refused.Unsupported("a word-break marker other than U+2581")
      }
      let prepend = match text_of(spec, "prepend_scheme") {
        Some(scheme) => scheme != "never"
        None => flag_of(spec, "add_prefix_space", true)
      }
      stages.push(@normalizer.Replace(" ", replacement))
      if prepend {
        stages.push(@normalizer.Pad(replacement))
      }
      @split.Metaspace
    }
    "Whitespace" => @split.Whitespace
    "Digits" =>
      @split.Digits({ individual: flag_of(spec, "individual_digits", false), })
    "Sequence" => {
      let parts : Array[@split.Split] = []
      for item in array_of(spec, "pretokenizers") {
        parts.push(read_pre_tokenizer(Some(item), stages))
      }
      @split.Sequence(parts)
    }
    other => raise @refused.Unsupported("the pre-tokenizer \{other}")
  }
}

///|
/// One step of a normalisation, from the shape a `tokenizer.json` writes it.
fn read_normalizer(
  json : Json,
  stages : Array[@normalizer.Stage],
) -> Unit raise @refused.Refused {
  if is_null(json) {
    return
  }
  let kind = match text_of(json, "type") {
    Some(kind) => kind
    None => raise @refused.Malformed("a normaliser has no type", 0)
  }
  match kind {
    "NFC" => stages.push(@normalizer.Nfc)
    "NFD" => stages.push(@normalizer.Nfd)
    "NFKC" => stages.push(@normalizer.Nfkc)
    "NFKD" => stages.push(@normalizer.Nfkd)
    "Lowercase" => stages.push(@normalizer.Lowercase)
    "Strip" => stages.push(@normalizer.Trim)
    "Prepend" =>
      stages.push(
        @normalizer.Prepend(
          match text_of(json, "prepend") {
            Some(text) => text
            None => raise @refused.Absent("a prepend step with no text")
          },
        ),
      )
    "Replace" => {
      let pattern = match field(json, "pattern") {
        Some(pattern) => pattern
        None => raise @refused.Absent("a replace step with no pattern")
      }
      let from = match text_of(pattern, "String") {
        Some(text) => text
        None =>
          raise @refused.Unsupported("a replace step that matches a pattern")
      }
      let to = match text_of(json, "content") {
        Some(text) => text
        None => ""
      }
      stages.push(@normalizer.Replace(from, to))
    }
    "Sequence" =>
      for item in array_of(json, "normalizers") {
        read_normalizer(item, stages)
      }
    other => raise @refused.Unsupported("the normaliser \{other}")
  }
}

///|
/// A tokenizer from the `tokenizer.json` a model distribution ships.
///
/// The file describes a vocabulary, the merges over it, the normalisation, the
/// cut, and the tokens the model reserves. Everything in it that this reader
/// does not implement is refused by name rather than approximated.
pub fn Tokenizer::of(json : Json) -> Tokenizer raise @refused.Refused {
  let model = match field(json, "model") {
    Some(model) => model
    None => raise @refused.Absent("a tokenizer file with no model")
  }
  let stages : Array[@normalizer.Stage] = []
  let normalizer = match field(json, "normalizer") {
    Some(spec) => {
      read_normalizer(spec, stages)
      ()
    }
    None => ()
  }
  ignore(normalizer)
  let cut = read_pre_tokenizer(field(json, "pre_tokenizer"), stages)
  let specials = @special.Table::empty()
  for entry in array_of(json, "added_tokens") {
    let content = match text_of(entry, "content") {
      Some(text) => text
      None => continue
    }
    specials.add(content, count_of(entry, "id", -1))
  }
  let kind = match text_of(model, "type") {
    Some(kind) => kind
    None => raise @refused.Absent("a model with no type")
  }
  match kind {
    "BPE" => {
      let vocab : Array[(String, Int32)] = []
      match field(model, "vocab") {
        Some(table) =>
          match object_of(table) {
            Some(entries) =>
              for entry in entries {
                let (text, id) = entry
                match as_number(id) {
                  Some(number) => vocab.push((text, number.to_int()))
                  None =>
                    raise @refused.Malformed("a token id is not a number", 0)
                }
              }
            None =>
              raise @refused.Malformed("a vocabulary that is not an object", 0)
          }
        None => raise @refused.Absent("a model with no vocabulary")
      }
      let merges : Array[(String, String)] = []
      for item in array_of(model, "merges") {
        match as_text(item) {
          Some(text) => {
            let parts = text.split(" ")
            let left = parts.next()
            let right = parts.next()
            match (left, right) {
              (Some(left), Some(right)) =>
                merges.push((left.to_owned(), right.to_owned()))
              _ => raise @refused.Malformed("a merge that is not two tokens", 0)
            }
          }
          None =>
            match as_array(item) {
              Some(parts) =>
                if parts.length() == 2 {
                  match (as_text(parts[0]), as_text(parts[1])) {
                    (Some(left), Some(right)) => merges.push((left, right))
                    _ =>
                      raise @refused.Malformed(
                        "a merge that is not two tokens", 0,
                      )
                  }
                } else {
                  raise @refused.Malformed("a merge that is not two tokens", 0)
                }
              None =>
                raise @refused.Malformed("a merge that is not two tokens", 0)
            }
        }
      }
      let unk_id = match text_of(model, "unk_token") {
        Some(unk) => {
          let mut found = -1
          for entry in vocab {
            if entry.0 == unk {
              found = entry.1
            }
          }
          found
        }
        None => -1
      }
      let decoding = if stages_has_marker(stages) {
        @bpe.Marker
      } else {
        @bpe.Alphabet
      }
      let decoder = match field(json, "decoder") {
        Some(spec) =>
          match text_of(spec, "type") {
            Some("ByteLevel") => @bpe.Alphabet
            Some("Metaspace") => @bpe.Marker
            Some("Sequence") => decoding
            Some("Fuse") => decoding
            Some(other) => raise @refused.Unsupported("the decoder \{other}")
            None => decoding
          }
        None => decoding
      }
      let normalizer = if stages.is_empty() {
        @normalizer.Normalizer::identity()
      } else {
        @normalizer.Normalizer::chain(stages)
      }
      let encoder = @bpe.WordBpe::new(
        vocab~,
        merges~,
        options={
          unk_id,
          byte_fallback: flag_of(model, "byte_fallback", false),
          ignore_merges: flag_of(model, "ignore_merges", false),
        },
        decoding=decoder,
        normalizer~,
        split=cut,
      )
      Tokenizer::new(model=encoder, specials~, policy=Allow)
    }
    "Unigram" => {
      let byte_fallback = flag_of(model, "byte_fallback", false)
      let items : Array[@piece.Piece] = []
      let raw = array_of(model, "vocab")
      for i = 0; i < raw.length(); i = i + 1 {
        let entry = raw[i]
        match as_array(entry) {
          Some(pair) =>
            if pair.length() == 2 {
              let text = match as_text(pair[0]) {
                Some(text) => text
                None => raise @refused.Malformed("a piece is not text", i)
              }
              let score = match as_number(pair[1]) {
                Some(number) => number
                None => 0.0
              }
              let bytes = @utf8.encode(text)
              // A `<0xNN>` spelling is how the file holds one byte of a
              // character the vocabulary has no piece for. It is a byte, not
              // text: it never takes part in segmentation, and it is only
              // reachable through the fallback.
              let kind = if byte_fallback &&
                @piece.byte_of_piece(bytes) is Some(_) {
                @piece.RawByte
              } else {
                @piece.Normal
              }
              items.push({
                text: bytes,
                score: Float::from_double(score),
                kind,
              })
            } else {
              raise @refused.Malformed("a piece is not text and a score", i)
            }
          None => raise @refused.Malformed("a piece is not an array", i)
        }
      }
      let unk_id = count_of(model, "unk_id", -1)
      if unk_id >= 0 && unk_id < items.length() {
        items[unk_id] = { ..items[unk_id], kind: @piece.Unknown, }
      }
      let pieces = @piece.Pieces::new(items~, unk_id~, byte_fallback~)
      let normalizer = if stages.is_empty() {
        @normalizer.Normalizer::identity()
      } else {
        @normalizer.Normalizer::chain(stages)
      }
      Tokenizer::new(
        model=@piece.Unigram::new(pieces~, normalizer~),
        specials~,
        policy=Allow,
      )
    }
    other => raise @refused.Unsupported("the model \{other}")
  }
}

///|
/// Whether the steps in front of the cut rewrite a space as the marker
/// pieces use.
fn stages_has_marker(stages : Array[@normalizer.Stage]) -> Bool {
  let mut found = false
  for stage in stages {
    match stage {
      @normalizer.Replace(from, to) =>
        if from == " " && to == "\u{2581}" {
          found = true
        }
      _ => ()
    }
  }
  found
}

///|
/// A tokenizer from the text of a `tokenizer.json` file.
///
/// The text is read as strict RFC 8259: a trailing comma, a comment or a
/// control character inside a string is refused where it is, rather than being
/// quietly accepted and changing what the vocabulary ends up holding.
pub fn Tokenizer::parse(text : StringView) -> Tokenizer raise @refused.Refused {
  let json = @moonjson.loads(text) catch {
    _ => raise @refused.Malformed("the file is not JSON", 0)
  }
  Tokenizer::of(json)
}
