#!/usr/bin/env python3
"""Diff this library against the reference implementations, live.

The vectors in `src/vectors_*_test.mbt` pin a reference at a version: they say
what the reference said on the day they were generated. This script keeps the
comparison honest by asking the reference again, now, for the same records. It
is the half of the conformance story that a committed file cannot tell.

Three references, because no single one covers the formats this library reads:

- `tiktoken` is the byte-level BPE of the OpenAI encodings. Vectors alone are
  not enough here because the pattern and the rank table have to agree with a
  particular release, and a mistyped rank is invisible until it is not.
- `sentencepiece` is the `.model` file, and the only thing that knows what its
  compiled trie means.
- `tokenizers` is where `tokenizer.json` comes from, for both of the model
  types the format names.

Records cross the boundary as text: the bench in `integration/` reads a file of records
separated by U+001E and prints one line of ids (or hex of the decoded text)
per record.

    python scripts/diff_reference.py --prepare   # fetch tables, train models
    python scripts/diff_reference.py             # compare
"""

import argparse
import base64
import json
import os
import random
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The program the comparisons drive, as `moon build --target native` leaves it.
# Windows appends an extension and the other platforms do not.
_BUILT = os.path.join(
    ROOT, "_build", "native", "debug", "build", "moonbitstack", "moontoken-conformance"
)
BINARY = next(
    (
        path
        for path in (
            os.path.join(_BUILT, "moontoken-conformance.exe"),
            os.path.join(_BUILT, "moontoken-conformance"),
        )
        if os.path.exists(path)
    ),
    os.path.join(_BUILT, "moontoken-conformance.exe"),
)
WORK = os.path.join(ROOT, ".cache", "diff")

# The name the reference gives each published table, against the name this
# library gives it.
TIKTOKEN = {
    "cl100k": "cl100k_base",
    "o200k": "o200k_base",
    "r50k": "r50k_base",
    "p50k": "p50k_base",
    "p50k_edit": "p50k_edit",
    "harmony": "o200k_harmony",
}

sys.path.insert(0, os.path.join(ROOT, "scripts"))

# The units the fuzz records are built from: the characters the patterns treat
# specially, the marks that attach to another character, and scripts that are
# not Latin.
ALPHABET = (
    list("abAB09 '\t\n\r.,-/:;!?()[]{}\"_")
    + [
        "\u00a0", "\u2009", "\u3000", "\u2581", "\u0301", "\u4e2d", "\u65e5",
        "\uac00", "\u0400", "\u0370", "\u05d0", "\u0627", "\u0e01", "\u0905",
        "\U0001f600", "\U0001f1e6", "\u01c5", "\u2160", "\uff21", "\u2153",
        "<|endoftext|>",
    ]
)


# The control words a chat format writes and the placeholders the vocabulary
# reserves beside them. They are here rather than in the vectors because they
# exercise a table of a thousand reserved spellings, which only the published
# encoding has.
CONTROL_WORDS = [
    "<|start|>assistant<|channel|>final<|message|>Hi<|end|>",
    "<|start|>user<|message|>a<|endoftext|><|end|>",
    "<|startoftext|>hello<|endofprompt|>",
    "<|return|><|constrain|><|call|>",
    "<|reserved_200004|>",
    "<|reserved_201087|>",
    # The id the vocabulary spells twice: named first, placeholder over it.
    "<|reserved_200018|>",
]


def records():
    """The texts both sides are asked about."""
    from gen_vectors import TEXTS

    out = list(TEXTS) + CONTROL_WORDS
    rng = random.Random(20261106)
    for _ in range(200):
        n = rng.randrange(0, 24)
        out.append("".join(rng.choice(ALPHABET) for _ in range(n)))
    return out


def run(mode, source, payload):
    """One line per record, from the binary."""
    os.makedirs(WORK, exist_ok=True)
    path = os.path.join(WORK, "records.txt")
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write("\x1e".join(
            text if isinstance(text, str) else " ".join(str(i) for i in text)
            for text in payload
        ))
    done = subprocess.run(
        [BINARY, mode, source, path], capture_output=True, check=False
    )
    if done.returncode != 0:
        raise SystemExit(
            f"{mode} {source} exited {done.returncode}\n"
            + done.stderr.decode("utf-8", "replace")
        )
    return done.stdout.decode("utf-8").splitlines()


def hex_of(text):
    return text.encode("utf-8").hex()


def compare(label, texts, expected_ids, expected_text):
    """Diff both directions and report the records that disagree."""
    got_ids = run(label["encode"], label["source"], texts)
    got_text = run(label["decode"], label["source"], expected_ids)
    bad = 0
    for text, want, line in zip(texts, expected_ids, got_ids):
        if line == "!":
            bad += 1
            print(f"  {label['encode']} refused {text!r}, reference gave {want}")
            continue
        if [int(x) for x in line.split()] != want:
            bad += 1
            print(f"  {label['encode']} {text!r}: {line} != {' '.join(map(str, want))}")
    for text, want, line in zip(texts, expected_text, got_text):
        if line == "!":
            bad += 1
            print(f"  {label['decode']} refused the tokens of {text!r}")
            continue
        if line != hex_of(want):
            bad += 1
            print(f"  {label['decode']} {text!r}: {line} != {hex_of(want)}")
    total = len(texts) * 2
    print(f"{label['name']}: {total - bad}/{total}")
    return bad


def prepare_tiktoken():
    """Write out the rank tables tiktoken itself holds, so both sides agree."""
    import tiktoken

    os.makedirs(WORK, exist_ok=True)
    written = {}
    for name in TIKTOKEN:
        enc = tiktoken.get_encoding(TIKTOKEN[name])
        lines = []
        for token, rank in sorted(enc._mergeable_ranks.items(), key=lambda kv: kv[1]):
            lines.append(f"{base64.b64encode(token).decode()} {rank}")
        path = os.path.join(WORK, f"{name}.tiktoken")
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(lines))
        written[name] = path
        print(f"{name}: {len(lines)} ranks -> {os.path.relpath(path, ROOT)}")
    return written


def prepare_piece():
    """Train the three sentence-piece models the vectors also replay."""
    from gen_vectors import piece_vectors

    piece_vectors()
    return {
        name: os.path.join(ROOT, ".cache", "sp", name + ".model")
        for name in ["unigram", "merges", "spaces"]
    }


def prepare_json():
    """Train one BPE and one unigram tokenizer and keep their files.

    The pair of pre-tokenizer and decoder is the one each model type is
    published with: a byte-level cut and the same on the way back, and the
    word-break marker on both sides for unigram. A file with no decoder says
    nothing about how its tokens turn back into text, and there would be
    nothing to compare.
    """
    from tokenizers import (
        Tokenizer,
        decoders,
        models,
        normalizers,
        pre_tokenizers,
        trainers,
    )
    from gen_vectors import corpus_sentences

    os.makedirs(WORK, exist_ok=True)
    corpus = os.path.join(WORK, "corpus.txt")
    with open(corpus, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(corpus_sentences()))

    bpe = Tokenizer(models.BPE(unk_token="<unk>"))
    bpe.pre_tokenizer = pre_tokenizers.ByteLevel(add_prefix_space=True)
    bpe.decoder = decoders.ByteLevel()
    bpe.train(
        [corpus],
        trainers.BpeTrainer(
            vocab_size=400,
            special_tokens=["<unk>", "<|endoftext|>", "<pad>"],
            initial_alphabet=pre_tokenizers.ByteLevel.alphabet(),
            show_progress=False,
        ),
    )

    unigram = Tokenizer(models.Unigram())
    unigram.pre_tokenizer = pre_tokenizers.Metaspace(
        replacement="\u2581", prepend_scheme="always"
    )
    unigram.normalizer = normalizers.Sequence([normalizers.NFKC()])
    unigram.decoder = decoders.Sequence(
        [
            decoders.ByteFallback(),
            decoders.Metaspace(replacement="\u2581", prepend_scheme="always"),
        ]
    )
    unigram.train(
        [corpus],
        trainers.UnigramTrainer(
            vocab_size=400,
            special_tokens=["<unk>", "<pad>"],
            byte_fallback=True,
            show_progress=False,
        ),
    )

    written = {}
    for name, tokenizer in [("bpe", bpe), ("unigram", unigram)]:
        path = os.path.join(WORK, f"{name}.json")
        tokenizer.save(path)
        written[name] = path

    # `tokenizers` 0.23 no longer trains byte fallback into a unigram model, but
    # every published unigram file has it, and it is the only way a character
    # outside the vocabulary survives the round trip. The pieces are added the
    # way a training run would have left them: the 256 byte spellings, scored
    # below every piece the trainer found.
    unigram_path = written["unigram"]
    with open(unigram_path, encoding="utf-8") as f:
        spec = json.load(f)
    vocab = spec["model"]["vocab"]
    floor = min(score for _, score in vocab)
    for b in range(256):
        spelling = f"<0x{b:02X}>"
        if not any(spelling == piece for piece, _ in vocab):
            vocab.append([spelling, floor - 10.0])
    spec["model"]["byte_fallback"] = True
    spec["model"]["fuse_unk"] = True
    if spec["model"].get("unk_id") is None:
        for index, (piece, _) in enumerate(vocab):
            if piece == "<unk>":
                spec["model"]["unk_id"] = index
                break
    with open(unigram_path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(spec, f, ensure_ascii=False, indent=2)

    for name, path in written.items():
        print(
            f"{name}: {Tokenizer.from_file(path).get_vocab_size()} tokens"
            f" -> {os.path.relpath(path, ROOT)}"
        )
    return written


def main():
    parser = argparse.ArgumentParser(description="diff against the references")
    parser.add_argument(
        "--prepare", action="store_true", help="fetch tables and train models first"
    )
    parser.add_argument(
        "--family",
        choices=["tiktoken", "piece", "json"],
        action="append",
        help="only compare this family; repeatable",
    )
    args = parser.parse_args()

    if not os.path.exists(BINARY):
        raise SystemExit(f"{_BUILT} is empty: run `moon build --target native`")

    families = args.family or ["tiktoken", "piece", "json"]
    texts = records()
    bad = 0

    if "tiktoken" in families:
        import tiktoken

        tables = prepare_tiktoken() if args.prepare else {
            name: os.path.join(WORK, f"{name}.tiktoken") for name in TIKTOKEN
        }
        for name, table in tables.items():
            enc = tiktoken.get_encoding(TIKTOKEN[name])
            allowed = set(enc._special_tokens)
            ids = [enc.encode(t, allowed_special=allowed) for t in texts]
            text = [enc.decode(i) for i in ids]
            bad += compare(
                {
                    "name": f"tiktoken {name}",
                    "encode": f"encode-tiktoken-{name}",
                    "decode": f"decode-tiktoken-{name}",
                    "source": table,
                },
                texts,
                ids,
                text,
            )

    if "piece" in families:
        import sentencepiece as spm

        models = prepare_piece() if args.prepare else {
            name: os.path.join(ROOT, ".cache", "sp", name + ".model")
            for name in ["unigram", "merges", "spaces"]
        }
        for name, path in models.items():
            proc = spm.SentencePieceProcessor(model_file=path)
            ids = [proc.encode(t) for t in texts]
            text = [proc.decode(i) for i in ids]
            bad += compare(
                {
                    "name": f"sentencepiece {name}",
                    "encode": "encode-piece",
                    "decode": "decode-piece",
                    "source": path,
                },
                texts,
                ids,
                text,
            )

    if "json" in families:
        from tokenizers import Tokenizer

        paths = prepare_json() if args.prepare else {
            name: os.path.join(WORK, f"{name}.json") for name in ["bpe", "unigram"]
        }
        for name, path in paths.items():
            tok = Tokenizer.from_file(path)
            kept, ids, text = [], [], []
            for t in texts:
                try:
                    enc = tok.encode(t)
                except Exception:
                    continue
                kept.append(t)
                ids.append(enc.ids)
                text.append(tok.decode(enc.ids, skip_special_tokens=False))
            bad += compare(
                {
                    "name": f"tokenizers {name}",
                    "encode": "encode-json",
                    "decode": "decode-json",
                    "source": path,
                },
                kept,
                ids,
                text,
            )

    if bad:
        raise SystemExit(f"{bad} record(s) disagree with the reference")
    print("every record agrees with every reference")


if __name__ == "__main__":
    main()
