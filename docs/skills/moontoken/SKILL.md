---
name: moontoken
description: "Tokenize text for a language model in MoonBit: byte-level BPE over a published rank table, SentencePiece .model files, and tokenizer.json. Use it to encode prompts, count tokens against a context budget, decode ids back to text, or bring your own vocabulary."
---

# moontoken

Text into tokens and back, over a vocabulary you supply. The library parses the
three formats a model ships and takes the bytes; fetching a table, unpacking a
GGUF file or caching a download stays with your code. It never opens a file.

```bash
moon add moonbitstack/moontoken
```

## Encode a prompt with a published table

`Ranks::from_tiktoken` reads the base64 text of a `.tiktoken` file; each
published encoding has its own constructor because each has its own split.

```moonbit
fn encode(table : String, text : String) -> Array[Int32] raise {
  let tokenizer = @moontoken.Tokenizer::cl100k(ranks=@vocab.Ranks::from_tiktoken(table))
  tokenizer.encode(text)
}
```

`Tokenizer::o200k`, `::o200k_harmony`, `::r50k` and `::p50k_edit` are the other
published encodings; `gpt2` and `p50k_base` are `r50k`'s rules over their own
tables. For a table of your own, build an `@vocab.Ranks` from pairs — it must
carry every one of the 256 byte values, and `from_pairs` refuses a table that
does not.

## Count before you send

`count` runs the same split and the same merges without keeping the ids.

```moonbit
fn fits(tokenizer : @moontoken.Tokenizer, text : String, budget : Int32) -> Bool raise {
  tokenizer.count(text) <= budget
}
```

Pass `special=@special.Refuse` when a context window must not be spent by a
reserved spelling: the default takes `<|endoftext|>` and the like as text.

## Read a model's own files

```moonbit
fn from_model(bytes : Bytes) -> @moontoken.Tokenizer raise {
  @moontoken.Tokenizer::of_proto(bytes)
}

fn from_document(text : String) -> @moontoken.Tokenizer raise {
  @moontoken.Tokenizer::parse(text)
}
```

`of_proto` reads a SentencePiece `.model` (unigram or BPE, with its normaliser,
byte fallback and user-defined symbols). `parse` reads a `tokenizer.json` with
its merges, normaliser, pre-tokenizer and added tokens. Anything either file
asks for that this reader does not implement is refused by name — check the
error rather than assuming the vocabulary was read.

## Rules worth knowing

- **Reserved tokens are a policy, not a default.** `Refuse`, `Allow`, `Ignore`
  or `Only(names)`, passed per call or set on the tokenizer. The longest
  spelling wins at every position.
- **`decode` returns text; `decode_bytes` returns bytes.** A byte-level table
  holds entries that are not valid UTF-8 on their own, and text output drops
  them. Stream through `decode_bytes` when the input was not text.
- **Ids from another table are not yours.** `Refused::Missing` carries the first
  id the table does not have.
- **One error type.** Every call raises `@moontoken.Refused`:
  `Malformed(what, at)` for a format that does not parse, `Absent(name)` for
  something a file should have carried, `Unsupported(what)` for a format this
  reader does not implement, `Missing(id)` for an id the vocabulary does not
  have, and `Disallowed(what, at)` for a reserved spelling a policy refused.
