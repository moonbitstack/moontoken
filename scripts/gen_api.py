"""Write docs/api.html from each package's interface file and the `///` comments
in its sources, so the reference follows the code.

Usage: python scripts/gen_api.py, from the repository root. The Docs workflow
runs it and fails when the working tree changes, so the page is never stale.

Every public item in a package's `pkg.generated.mbti` has to end up on the page;
the script counts them at the end and refuses to write a page that lost one.
"""

import html
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# The tokenizer first, because it is what a reader arrives for; the rest by
# alphabet within their role.
PACKAGES = [
    (
        "moonbitstack/moontoken",
        "src",
        "The tokenizer: one struct, its methods, and the ways to build one from a table, a SentencePiece model file or a tokenizer.json.",
    ),
    (
        "moonbitstack/moontoken/bpe",
        "src/bpe",
        "Byte-pair merging: the byte-level model over a rank table, and the word-level one a tokenizer.json names.",
    ),
    (
        "moonbitstack/moontoken/normalizer",
        "src/normalizer",
        "The rule table a SentencePiece model carries, and the operations a tokenizer.json lists.",
    ),
    (
        "moonbitstack/moontoken/piece",
        "src/piece",
        "The SentencePiece model file: its pieces, both trainer types, and the trie it compiles to.",
    ),
    (
        "moonbitstack/moontoken/refused",
        "src/refused",
        "The one error shape the library raises, with the offset, the name or the id that went wrong.",
    ),
    (
        "moonbitstack/moontoken/special",
        "src/special",
        "The tokens a model reserves, the table that holds them, and the policy for text that contains one.",
    ),
    (
        "moonbitstack/moontoken/split",
        "src/split",
        "The pre-tokenizers of the published encodings, written as scanners, and the split a caller can compose.",
    ),
    (
        "moonbitstack/moontoken/vocab",
        "src/vocab",
        "A rank table: from the base64 text a model publishes, from pairs, or empty and filled by hand.",
    ),
]

DECL = re.compile(
    r"^pub(?:\((?:all|open)\))?\s+(fn(?:\[[^\]]*\])?|let|struct|enum|suberror|trait|typealias|type)\s+([A-Za-z_][\w]*(?:::[A-Za-z_][\w]*)?)"
)

# Methods every public type gets from a derive; they are noise in a reference.
DERIVED = re.compile(
    r"::(equal|not_equal|output|to_string|to_repr|hash|hash_combine|compare|op_\w+)\("
)


def docs_of(folder):
    """Doc comments by declared name, and by `Type.field` for fields and variants."""
    out = {}
    for path in sorted((ROOT / folder).glob("*.mbt")):
        if path.name.endswith("_test.mbt"):
            continue
        pending, owner = [], None
        for line in path.read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if stripped == "///|":
                pending = []
                continue
            if stripped.startswith("///"):
                pending.append(stripped[3:].strip())
                continue
            # An attribute between the comment and the declaration belongs to
            # the declaration; skipping it keeps the comment attached.
            if stripped.startswith("#"):
                continue
            match = DECL.match(line)
            if match:
                name = match.group(2)
                if pending:
                    out[name] = " ".join(pending)
                owner = (
                    name
                    if match.group(1) in ("struct", "enum", "suberror", "trait")
                    and line.rstrip().endswith("{")
                    else None
                )
                pending = []
                continue
            if owner and line.startswith("}"):
                owner = None
            elif owner and pending:
                field = re.match(r"\s+(?:fn\s+)?(?:mut\s+)?([A-Za-z_]\w*)", line)
                if field:
                    out[owner + "." + field.group(1)] = " ".join(pending)
            pending = []
    return out


def items_of(folder):
    """Declarations from the interface file: (kind, name, text, owner)."""
    lines = (ROOT / folder / "pkg.generated.mbti").read_text(encoding="utf-8").splitlines()
    items, block = [], None
    for line in lines:
        if block is not None:
            block[2].append(line)
            if line.startswith("}"):
                items.append((block[0], block[1], "\n".join(block[2]), None))
                block = None
            continue
        if not line.startswith("pub"):
            continue
        match = re.match(r"pub(?:\((?:all|open)\))?\s+(struct|enum|suberror|trait)\s+(\w+)", line)
        if match and line.rstrip().endswith("{"):
            block = [match.group(1), match.group(2), [line]]
            continue
        if match:
            items.append((match.group(1), match.group(2), line, None))
            continue
        match = re.match(r"pub fn(?:\[[^\]]*\])?\s+(\w+)::(\w+)", line)
        if match:
            items.append(("method", match.group(1) + "::" + match.group(2), line, match.group(1)))
            continue
        match = re.match(r"pub fn(?:\[[^\]]*\])?\s+(\w+)", line)
        if match:
            items.append(("fn", match.group(1), line, None))
            continue
        match = re.match(r"pub let (\w+)", line)
        if match:
            items.append(("let", match.group(1), line, None))
            continue
        match = re.match(r"pub type (\w+)", line)
        if match:
            items.append(("type", match.group(1), line, None))
            continue
        match = re.match(r"pub using @(\w+) \{(.*)\}", line)
        if match:
            items.append(("using", match.group(1), line, None))
    return items


def code(text):
    return '<pre class="sig"><code>%s</code></pre>' % html.escape(text.strip())


def prose(text):
    if not text:
        return ""
    escaped = html.escape(text)
    escaped = re.sub(r"`([^`]+)`", r"<code>\1</code>", escaped)
    return "<p>%s</p>" % escaped


def anchor(pkg, name):
    return (pkg.split("/")[-1] + "-" + name).replace("::", "-").replace("_", "-").lower()


def render():
    nav, body, expected, shown = [], [], 0, 0
    for pkg, folder, intro in PACKAGES:
        docs = docs_of(folder)
        items = items_of(folder)
        # A derive writes out equal, not_equal and the rest of a trait the type
        # already says it implements; a reference listing them is noise.
        items = [i for i in items if not (i[0] == "method" and DERIVED.search(i[2]))]
        expected += len(items)
        short = pkg.split("/", 1)[1]
        nav.append('<div class="group"><b>%s</b>' % html.escape(short))
        body.append(
            '<section id="%s"><h2>%s</h2>%s'
            % (anchor(pkg, "top"), html.escape(short), prose(intro))
        )
        types = [i for i in items if i[0] in ("struct", "enum", "suberror", "trait", "type")]
        methods = {}
        for kind, name, text, owner in items:
            if kind == "method":
                methods.setdefault(owner, []).append((name, text))
        values = [i for i in items if i[0] == "let"]
        fns = [i for i in items if i[0] == "fn"]
        usings = [i for i in items if i[0] == "using"]

        if usings:
            nav.append('<a href="#%s">Re-exported</a>' % anchor(pkg, "re-exported"))
            body.append('<h3 id="%s">Re-exported</h3>' % anchor(pkg, "re-exported"))
            body.append(
                prose(
                    "Reachable from this package as well; each type is documented in the package it comes from."
                )
            )
            body.append(code("\n".join(text for _, _, text, _ in usings)))
            shown += len(usings)

        for kind, name, text, _ in types:
            nav.append('<a href="#%s">%s</a>' % (anchor(pkg, name), html.escape(name)))
            body.append(
                '<article id="%s"><h3><span class="kind">%s</span> %s</h3>'
                % (anchor(pkg, name), kind, html.escape(name))
            )
            body.append(prose(docs.get(name, "")))
            body.append(code(text))
            shown += 1
            fields = [(k.split(".", 1)[1], v) for k, v in docs.items() if k.startswith(name + ".")]
            if fields:
                body.append(
                    '<dl class="fields">%s</dl>'
                    % "".join(
                        "<dt><code>%s</code></dt><dd>%s</dd>" % (html.escape(f), prose(d))
                        for f, d in sorted(fields)
                    )
                )
            for mname, mtext in sorted(methods.get(name, [])):
                if DERIVED.search(mtext):
                    continue
                body.append(
                    '<div class="member" id="%s">%s%s</div>'
                    % (anchor(pkg, mname), code(mtext), prose(docs.get(mname, "")))
                )
                shown += 1
            body.append("</article>")

        for title, group in (("Functions", fns), ("Values", values)):
            if not group:
                continue
            nav.append('<a href="#%s">%s</a>' % (anchor(pkg, title), title))
            body.append('<h3 id="%s">%s</h3>' % (anchor(pkg, title), title))
            for _, name, text, _ in sorted(group, key=lambda item: item[1]):
                body.append(
                    '<div class="member" id="%s">%s%s</div>'
                    % (anchor(pkg, name), code(text), prose(docs.get(name, "")))
                )
                shown += 1

        nav.append("</div>")
        body.append("</section>")

    page = (ROOT / "docs" / "api.template.html").read_text(encoding="utf-8")
    page = page.replace("<!-- nav -->", "\n".join(nav)).replace("<!-- body -->", "\n".join(body))
    if expected != shown:
        print(f"the page lists {shown} of {expected} public items; refusing to write it")
        return 1
    (ROOT / "docs" / "api.html").write_text(page, encoding="utf-8", newline="\n")
    print(f"docs/api.html: {shown} public items")
    return 0


if __name__ == "__main__":
    sys.exit(render())
