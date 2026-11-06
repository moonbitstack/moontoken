"""Generate the vectors the MoonBit tests replay.

Every expected value here comes from the reference implementation of the
format, not from this library:

- byte-level BPE and the special tokens: `tiktoken`, running the published
  pattern over a small vocabulary carved out of the published table;
- sentence-piece: `sentencepiece`, over three small models trained here.

The models are trained from a corpus this script writes, so the run is
reproducible. The generated files are committed; CI re-runs this script and
requires the working tree to stay clean.

    python scripts/gen_vectors.py
"""

import base64
import os
import urllib.request
import hashlib

import sentencepiece as spm
import tiktoken

ENCODINGS = {
    "cl100k": (
        "https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken",
        "223921b76ee99bde995b7ff738513eef100fb51d18c93597a113bcffe865b2a7",
        r"'(?i:[sdmt]|ll|ve|re)|[^\r\n\p{L}\p{N}]?+\p{L}++|\p{N}{1,3}+| ?[^\s\p{L}\p{N}]++[\r\n]*+|\s++$|\s*[\r\n]|\s+(?!\S)|\s",
    ),
    "o200k": (
        "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
        "446a9538cb6c348e3516120d7c08b09f57c36495e2acfffe59a5bf8b0cfb1a2d",
        r"[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]*[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?|[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]+[\p{Ll}\p{Lm}\p{Lo}\p{M}]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?|\p{N}{1,3}| ?[^\s\p{L}\p{N}]+[\r\n/]*|\s*[\r\n]+|\s+(?!\S)|\s+",
    ),
}

# Texts the vectors cover: ordinary prose, the spaces and line breaks the
# patterns treat specially, scripts that are not Latin, and the marks that
# attach to a character instead of standing on their own.
TEXTS = [
    "hello world",
    "Hello World and HELLO",
    "The quick brown fox jumps over the lazy dog.",
    "camelCaseIdentifier and snake_case_name",
    "don't can't it's we'll they've I'm he'd",
    "DON'T CAN'T I'LL",
    "x'y z'W 's 't",
    "  leading and trailing   ",
    "word    word",
    "line one\nline two\r\nline three",
    "\n\n\n",
    "a\n\nb",
    "tab\tseparated\tvalues",
    " \n ",
    "123 4567 89012 0",
    "3.14159 and 1234567890",
    "!!!???...,,, ----====",
    "http://example.com/path?query=1&x=2",
    "path/to/file.txt",
    "中文分词测试，这是一个句子。",
    "混合 mixed 中文 and English text",
    "😀👍🏽👨‍👩‍👧‍👦🇨🇳",
    "café naïve résumé",
    "e\u0301 a\u0301b\u0301c",
    "Ａｒｇｅｒ ｆｕｌｌｗｉｄｔｈ",
    "Привет, мир! Γειά σου Κόσμε",
    "مرحبا بالعالم שלום עולם",
    "สวัสดีชาวโลก नमस्ते दुनिया",
    "  \u00a0nbsp\u00a0 ",
    "\u3000ideographic space\u3000",
    "zero\u200bwidth",
    "€100 $200 £300 ¥400",
    "½ ¼ ¾ ⅓ Ⅻ",
    "UPPER lower UPPER lower",
    "XMLHttpRequest iPhone15Pro",
    "a",
    "",
    " ",
    "   ",
    "\r",
    "\n",
    "<|endoftext|> in text",
]

# Models for the sentence-piece vectors. The rule table is small enough to
# commit, and it still exercises the compiled trie rather than a table of
# one-character replacements.
RULES = [
    ("00E9", "0065"),
    ("FF21", "0041"),
    ("FF22", "0042"),
    ("00C4", "0041"),
    ("3000", "0020"),
    ("2018", "0027"),
]

WORDS_EN = (
    "the quick brown fox jumps over lazy dog hello world token tokenizer moon "
    "bit encoding decode text model vocabulary piece merge rank byte"
).split()
WORDS_ZH = "中文 分词 测试 这是一个 句子 月亮 令牌 编码 解码 词表 模型".split()
SPICES = ["😀", "👍🏽", "1", "23", "456", "!", "?", "...", "<SPECIAL>", "café", "Ärger", "ｆｕｌｌ"]


def corpus_sentences():
    import random

    rng = random.Random(7)
    out = []
    for _ in range(3000):
        parts = []
        for _ in range(rng.randrange(3, 12)):
            r = rng.random()
            if r < 0.5:
                parts.append(rng.choice(WORDS_EN))
            elif r < 0.8:
                parts.append(rng.choice(WORDS_ZH))
            else:
                parts.append(rng.choice(SPICES))
        out.append(" ".join(parts))
    return out


def fetch(url, digest):
    cache = os.path.join(".cache", os.path.basename(url))
    if not os.path.exists(cache):
        os.makedirs(".cache", exist_ok=True)
        with urllib.request.urlopen(url) as response:
            body = response.read()
        with open(cache, "wb") as f:
            f.write(body)
    with open(cache, "rb") as f:
        body = f.read()
    got = hashlib.sha256(body).hexdigest()
    if got != digest:
        raise SystemExit(f"{url} hashes to {got}, expected {digest}")
    return body


def toy_vocabulary(table, limit=600):
    """All 256 single bytes plus the lowest-ranked tokens of printable ASCII."""
    ranks = {}
    for line in table.decode().splitlines():
        if not line.strip():
            continue
        token, rank = line.rsplit(" ", 1)
        ranks[base64.b64decode(token)] = int(rank)
    picked = {}
    for b in range(256):
        picked[bytes([b])] = ranks[bytes([b])]
    for token, rank in sorted(ranks.items(), key=lambda item: item[1]):
        if len(picked) >= limit:
            break
        if len(token) > 1 and all(0x20 <= b < 0x7F for b in token):
            picked[token] = rank
    return picked


def write_table(name, picked):
    lines = []
    for token, rank in sorted(picked.items(), key=lambda item: item[1]):
        lines.append(f"{base64.b64encode(token).decode()} {rank}")
    return "\n".join(f"    #|{line}" for line in lines) + "\n"


def escape(text):
    out = []
    for ch in text:
        code = ord(ch)
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif 0x20 <= code < 0x7F:
            out.append(ch)
        else:
            out.append("\\u{%X}" % code)
    return '"' + "".join(out) + '"'


def byte_bpe_vectors():
    out = []
    for name, (url, digest, pattern) in ENCODINGS.items():
        table = fetch(url, digest)
        picked = toy_vocabulary(table)
        encoder = tiktoken.Encoding(
            name=f"moontoken-toy-{name}",
            pat_str=pattern,
            mergeable_ranks=picked,
            special_tokens={"<|endoftext|>": 500000, "<|endoftext|>|fim|": 500001},
        )
        rows = []
        for text in TEXTS:
            ids = encoder.encode_ordinary(text)
            rows.append((text, ids))
        out.append((name, write_table(name, picked), rows, encoder))
    return out


def piece_vectors():
    os.makedirs(".cache/sp", exist_ok=True)
    with open(".cache/sp/corpus.txt", "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(corpus_sentences()))
    with open(".cache/sp/rules.tsv", "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(f"{a}\t{b}" for a, b in RULES))
    common = dict(
        input=".cache/sp/corpus.txt",
        vocab_size=400,
        character_coverage=1.0,
        hard_vocab_limit=False,
        user_defined_symbols=["<SPECIAL>", "中文"],
        normalization_rule_name="user_defined",
        normalization_rule_tsv=".cache/sp/rules.tsv",
        minloglevel=2,
    )
    specs = [
        ("unigram", dict(model_type="unigram", byte_fallback=True)),
        ("merges", dict(model_type="bpe", byte_fallback=True)),
        (
            "spaces",
            dict(
                model_type="unigram",
                byte_fallback=True,
                add_dummy_prefix=False,
                remove_extra_whitespaces=False,
            ),
        ),
    ]
    out = []
    for name, extra in specs:
        prefix = f".cache/sp/{name}"
        spm.SentencePieceTrainer.train(model_prefix=prefix, **common, **extra)
        model = open(prefix + ".model", "rb").read()
        proc = spm.SentencePieceProcessor(model_file=prefix + ".model")
        encoded = [(text, proc.encode(text)) for text in TEXTS]
        decoded = [(ids, proc.decode(ids)) for _, ids in encoded]
        decoded.append(([proc.bos_id(), proc.eos_id()], proc.decode([proc.bos_id(), proc.eos_id()])))
        decoded.append(([proc.unk_id()], proc.decode([proc.unk_id()])))
        out.append((name, model, encoded, decoded))
    return out


def write_byte_bpe(vectors):
    lines = [
        "// Generated by scripts/gen_vectors.py from tiktoken. Do not edit.",
        "",
    ]
    for name, table, rows, encoder in vectors:
        lines.append("///|")
        lines.append(f"/// The table of `{name}` reduced to the bytes and the {len(encoder._mergeable_ranks) - 256} lowest")
        lines.append("/// merges, in the layout the published files use.")
        lines.append(f"fn {name}_table() -> String {{")
        lines.append("  let text =")
        lines.append(table + "  text\n}")
        lines.append("")
        count = len(rows)
        half = (count + 1) // 2
        for part, chunk in enumerate([rows[:half], rows[half:]]):
            lines.append("///|")
            lines.append(f"fn {name}_vectors_{part}() -> Array[(String, Array[Int])] {{")
            lines.append("  [")
            for text, ids in chunk:
                body = ", ".join(str(i) for i in ids)
                lines.append(f"    ({escape(text)}, [{body}]),")
            lines.append("  ]")
            lines.append("}")
            lines.append("")
        lines.append("///|")
        lines.append(f"fn {name}_vectors() -> Array[(String, Array[Int])] {{")
        lines.append(f"  {name}_vectors_0() + {name}_vectors_1()")
        lines.append("}")
        lines.append("")
    with open("src/vectors_byte_bpe_test.mbt", "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


def write_piece(vectors):
    lines = ["// Generated by scripts/gen_vectors.py from sentencepiece. Do not edit.", ""]
    for name, model, encoded, decoded in vectors:
        encoded_model = base64.b64encode(model).decode()
        chunks = [encoded_model[i : i + 120] for i in range(0, len(encoded_model), 120)]
        lines.append("///|")
        lines.append(f"/// The `{name}` model file, base64.")
        lines.append(f"fn {name}_model() -> String {{")
        lines.append("  let text =")
        lines.append("\n".join(f"    #|{chunk}" for chunk in chunks))
        lines.append("  text\n}")
        lines.append("")
        lines.append("///|")
        lines.append(f"fn {name}_encoded() -> Array[(String, Array[Int])] {{")
        lines.append("  [")
        for text, ids in encoded:
            body = ", ".join(str(i) for i in ids)
            lines.append(f"    ({escape(text)}, [{body}]),")
        lines.append("  ]")
        lines.append("}")
        lines.append("")
        lines.append("///|")
        lines.append(f"fn {name}_decoded() -> Array[(Array[Int], String)] {{")
        lines.append("  [")
        for ids, text in decoded:
            body = ", ".join(str(i) for i in ids)
            lines.append(f"    ([{body}], {escape(text)}),")
        lines.append("  ]")
        lines.append("}")
        lines.append("")
    with open("src/vectors_piece_test.mbt", "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


def write_special(vectors):
    name, table, rows, encoder = vectors[0]
    out = ["// Generated by scripts/gen_vectors.py from tiktoken. Do not edit.", ""]
    out.append("///|")
    out.append("/// The special tokens of the toy table, and what each policy makes of")
    out.append("/// the texts below.")
    out.append("fn special_cases() -> Array[(String, Array[Int], Array[Int])] {")
    out.append("  [")
    for text in [
        "before <|endoftext|> after",
        "<|endoftext|>",
        "no token here",
        "<|endoftext|",
        "<|endoftext|>>",
        "<|endoftext|><|endoftext|>",
    ]:
        ordinary = encoder.encode_ordinary(text)
        allowed = encoder.encode(text, allowed_special=encoder.special_tokens_set)
        out.append(
            f"    ({escape(text)}, [{', '.join(str(i) for i in ordinary)}], "
            f"[{', '.join(str(i) for i in allowed)}]),"
        )
    out.append("  ]")
    out.append("}")
    with open("src/vectors_special_test.mbt", "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out))


def main():
    vectors = byte_bpe_vectors()
    write_byte_bpe(vectors)
    write_special(vectors)
    write_piece(piece_vectors())
    print("wrote src/vectors_byte_bpe_test.mbt")
    print("wrote src/vectors_special_test.mbt")
    print("wrote src/vectors_piece_test.mbt")


if __name__ == "__main__":
    main()
