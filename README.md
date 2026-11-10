# moontoken

<p>
  <b><a href="https://moonbitstack.github.io/moontoken/">Home</a></b> ·
  <a href="https://moonbitstack.github.io/moontoken/guide.html">Guide</a> ·
  <a href="https://moonbitstack.github.io/moontoken/api.html">API</a> ·
  <a href="https://mooncakes.io/docs/moonbitstack/moontoken">mooncakes</a>
</p>

Text into tokens and back, over a vocabulary you supply.

A tokenizer is three things: a way to cut text into the words a model was
trained on, a vocabulary that says what each of those words costs, and a rule
for the tokens a model reserves. This library implements all three for the two
families in use today, and takes the vocabulary as an argument. It never opens
a file of its own accord, because where a vocabulary comes from is the format's
business: a GGUF file is
[`moongguf`](https://github.com/moonbitstack/moongguf)'s, a `tokenizer.json` and
a SentencePiece model are read here, and a published rank table is a string.

```moonbit
/// `table` is the text of a published `cl100k_base.tiktoken` file.
fn ids_of(table : String, text : String) -> Array[Int] raise {
  let ranks = @vocab.Ranks::from_tiktoken(table)
  let tokenizer = @moontoken.Tokenizer::cl100k(ranks~)
  tokenizer.encode(text)
}
```

<!-- nocheck -->
```
text       the world and the thing
tokens     8
ids        258 262 261 32 258 32 256 260
bytes      23
decoded    the world and the thing
count      8
vocabulary 263
```

Encoding and decoding round-trip: text that goes in comes back out, including
the bytes that are not valid text on their own, because a byte-level encoding
spells those out rather than dropping them.

## The interface

One type carries the vocabulary and the rules; everything else is an argument
to it.

| Call | What it does |
|:--|:--|
| `Tokenizer::cl100k(ranks~)` | `cl100k_base`: its split, its reserved tokens, over the table you supply. `::o200k`, `::r50k` and `::p50k_edit` are the same call for the other published encodings. |
| `Tokenizer::byte_bpe(ranks~, split~)` | A table with a split of your own: any rule in `split`, or a sequence of them. |
| `Tokenizer::of_proto(bytes)` | A SentencePiece `.model` file, unigram or BPE, read whole. |
| `Tokenizer::parse(text)` | A `tokenizer.json` document. `::of` takes the same thing as a `Json` you already parsed. |
| `encode(text)` | The ids. `special=` overrides the policy for this one call. |
| `encode_ordinary(text)` | The ids of text that holds no reserved token, whatever the policy says. |
| `count(text)` | How many ids the text costs when every reserved token is recognised — the number to budget a context window with. |
| `decode(ids)` | The text, with U+FFFD standing in for the byte sequences that are not text. |
| `decode_bytes(ids)` | The bytes, exact. `reserved=false` drops the reserved tokens instead of spelling them. |
| `token_bytes(id)` | The bytes one id stands for, reserved ids included. |
| `length()` | How many entries the vocabulary has, reserved ones not counted. |

Every fallible call raises the one error the library has, `Refused`, which is
`moonbitstack/moontoken/refused` re-exported. Match on it rather than printing
it: `Malformed(what, at)` is a format that does not parse, `Absent(name)`
something a file should have carried and did not, `Unsupported(what)` a format
this reader does not implement, `Missing(id)` an id the vocabulary does not
have, and `Disallowed(what, at)` a reserved spelling a policy refused.

## What it covers

| Package | What it is |
|:--|:--|
| `moontoken` | The tokenizer: `encode`, `encode_ordinary`, `decode`, `count`, and the ways to build one |
| `split` | The pre-tokenizers of the published encodings, written as scanners |
| `vocab` | A rank table, from the base64 file OpenAI publishes or from pairs |
| `bpe` | Byte-pair merging: the byte-level model, and the word-level one a `tokenizer.json` names |
| `piece` | The SentencePiece model file: both trainer types, and the trie it compiles |
| `normalizer` | The rule table a model file carries, and the operations a `tokenizer.json` lists |
| `special` | The tokens a model reserves, and what may happen to them |
| `refused` | The one error shape the whole library raises |

Three families of vocabulary, each with its own entry point:

- **Byte-level BPE.** `Tokenizer::cl100k`, `::o200k`, `::r50k`, `::p50k_edit`
  for the published encodings, or `::byte_bpe` with a `split` and a policy you
  choose.
- **SentencePiece.** `Tokenizer::of_proto` reads a `.model` file, unigram or
  BPE. The trie, the normalisation rules, the byte fallback and the
  user-defined symbols all come from the file; nothing is assumed.
- **`tokenizer.json`.** `Tokenizer::parse` reads a BPE or unigram vocabulary
  with its merges, normaliser, pre-tokenizer and added tokens. Anything the file
  asks for that this reader does not implement is refused by name rather than
  approximated.

## Reserved tokens

A model reserves a handful of spellings that stand for structure rather than
text. Whether text that happens to contain `<|endoftext|>` is taken as the
token, taken as text, or refused is the caller's decision, never the library's:

```moonbit
fn four_ways(tokenizer : @moontoken.Tokenizer, text : String) -> Array[Array[Int]] raise {
  [
    tokenizer.encode(text, special=@special.Refuse), // refuse it
    tokenizer.encode(text, special=@special.Allow), // take it as the token
    tokenizer.encode(text, special=@special.Ignore), // encode it as text
    tokenizer.encode(text, special=@special.Only(["<|endoftext|>"])),
  ]
}
```

When one spelling is a prefix of another, the longest one wins. The reference
implementation takes whichever a hash map happens to yield first, which is not
a definition a tokenizer can have; the test that pins the difference is
`the longest reserved token wins`.

## Conformance

Two layers, both in CI.

**Vectors.** Generated from the references by `scripts/gen_vectors.py`, with the
versions pinned: `tiktoken` 0.14.0 and `sentencepiece` 0.2.3.

| What | Rows | Passing |
|:--|--:|--:|
| `cl100k_base` and `o200k_base`, over a 600-entry slice of each published table | 84 | 84 |
| The reserved tokens, under each policy | 6 | 6 |
| SentencePiece unigram, BPE, and unigram without the dummy prefix | 258 | 258 |
| **Total** | **348** | **348** |

The models are trained from a corpus the script writes and the trainer is pinned
to one thread, so a run is reproducible byte for byte; CI re-runs the generator
and requires the working tree to stay clean. A vector that no longer matches its
reference is worse than no vector at all.

**Live differential.** `scripts/diff_reference.py` asks the references again,
now, for 242 records: the texts the vectors use plus 200 random strings over the
characters the patterns treat specially, astral planes included. Every record is
compared in both directions through `src/examples/03-conformance`.

| Reference | Encoders | Comparisons | Agreeing |
|:--|--:|--:|--:|
| `tiktoken` 0.14.0 | 4 | 1936 | 1936 |
| `sentencepiece` 0.2.3 | 3 | 1452 | 1452 |
| `tokenizers` 0.23.1 | 2 | 968 | 968 |
| **Total** | **9** | **4356** | **4356** |

Three references rather than one, because none of them covers all three
formats, and a format read by one implementation only is a format that drifts.

<!-- nocheck -->
```bash
moon build --target native
pip install tiktoken==0.14.0 sentencepiece==0.2.3 tokenizers==0.23.1
python scripts/diff_reference.py --prepare
```

**Mutation.** Two deliberate breaks, to check that the tests are load-bearing.
Taking the highest rank instead of the lowest in the merge loop fails three
tests: `cl100k_base agrees with the reference vectors`, `o200k_base agrees with
the reference vectors`, and `reserved tokens follow the policy`. Taking the
first reserved spelling that matches instead of the longest fails two:
`the longest reserved token wins` and `the longest spelling at a position is
found`. Both were reverted.

No test is skipped, so there is nothing to report as not passing.

## Deliberately elsewhere

- **Where a vocabulary comes from.** A GGUF file, a Hugging Face download, an
  OpenAI table on disk. This library parses the formats and takes the bytes;
  fetching them is the caller's.
- **Training.** `sentencepiece` and `tokenizers` train vocabularies; this reads
  them. The scripts under `scripts/` train small ones, and they are test
  fixtures, not an API.

## Install

<!-- nocheck -->
```bash
moon add moonbitstack/moontoken
```

## Licence

Apache-2.0. See [LICENSE](LICENSE).
