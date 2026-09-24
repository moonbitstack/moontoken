# moontoken

Text into tokens and back, over a vocabulary you supply.

> **Status: planned.** The repository is set up; nothing is
> implemented yet.

| Package | What it covers |
|:--|:--|
| `vocab` | A vocabulary and its scores, however it arrived |
| `bpe` | Byte-level byte-pair encoding, and the merges that drive it |
| `piece` | The SentencePiece shape: unigram scoring and the longest match |
| `special` | The tokens a model reserves, and where they may appear |

Encoding and decoding round-trip: text that goes in comes back out, including
the bytes that are not valid text on their own.

## What is deliberately elsewhere

Where a vocabulary comes from. A GGUF file carries one, and reading it is
[`moongguf`](https://github.com/moonbitstack/moongguf)'s; this library takes the
vocabulary as an argument and never opens a file.

## Install

```bash
moon add moonbitstack/moontoken
```

## Licence

Apache-2.0. See [LICENSE](LICENSE).
