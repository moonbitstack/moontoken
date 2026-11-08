// The page's half of the engine: it asks the library for tokens and then only
// spells them out. Nothing here cuts text — every id, byte count and decoded
// string comes back from docs/engine/moontoken.js, which the Docs workflow
// builds from src/examples/browser.

const decoder = new TextDecoder("utf-8", { fatal: true });

// A vocabulary entry is bytes, and some of them are not text on their own: a
// three-byte character in a table that never merged it stays three entries.
// Those are printed as hex, which is what they are.
//
// A space inside a token is printed as a quad, the blank slug a compositor sets
// between words. It is drawn rather than written because no character stands for
// a space honestly: a space disappears, and the symbols that try (SP, U+2423)
// read as letters in a monospaced face.
export function face(hex) {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i += 1) {
    bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  let text = null;
  try {
    text = decoder.decode(bytes);
  } catch (error) {
    text = null;
  }
  if (text !== null && !/[\u0000-\u001f\u007f-\u009f]/.test(text)) {
    const parts = [];
    let run = "";
    for (const ch of text) {
      if (ch === " " || ch === "\u00a0" || ch === "\t" || ch === "\n") {
        if (run) {
          parts.push({ kind: "text", text: run });
          run = "";
        }
        parts.push({ kind: "quad" });
      } else {
        run += ch;
      }
    }
    if (run) parts.push({ kind: "text", text: run });
    return { parts, hex: false };
  }
  return { parts: [{ kind: "hex", text: hex.toUpperCase() }], hex: true };
}

// The same token, said out loud, for a reader who cannot see the quad.
export function spoken(hex) {
  const shown = face(hex);
  if (shown.hex) return "bytes " + shown.parts.map((part) => part.text).join(" ");
  return shown.parts
    .map((part) => (part.kind === "quad" ? "space" : part.text))
    .join(" ");
}

export function paint(node, hex) {
  for (const part of face(hex).parts) {
    if (part.kind === "quad") {
      const quad = document.createElement("i");
      quad.className = "quad";
      quad.setAttribute("aria-hidden", "true");
      node.append(quad);
    } else {
      const span = document.createElement("span");
      if (part.kind === "hex") span.className = "hex";
      span.textContent = part.text;
      node.append(span);
    }
  }
  return node;
}

// Which ink a piece is set in. Bytes 0-31 and 32-255 are the alphabet every
// byte-level table has to carry; from 256 on, the merges, each with an ink of
// its own so a reader can follow one across the page.
export function ink(id) {
  if (id < 32) return "k-ctrl";
  if (id < 256) return "k-raw";
  return "k-m" + ((id - 256) % 8);
}

// The same choice as a custom property, for the places that print a single
// piece of text rather than a slug.
export function inkVar(id) {
  if (id < 32) return "--k-ctrl";
  if (id < 256) return "--k-raw";
  return "--k" + ((id - 256) % 8);
}

export function spaced(hex) {
  return hex.toUpperCase().replace(/(..)(?=.)/g, "$1 ");
}

export function slug(token) {
  const node = document.createElement("button");
  node.type = "button";
  node.className = "slug " + ink(token.id);
  node.dataset.id = String(token.id);
  node.dataset.hex = token.hex;
  node.dataset.bytes = String(token.bytes);
  node.setAttribute("aria-pressed", "false");
  const body = document.createElement("span");
  body.className = "face";
  paint(body, token.hex);
  const id = document.createElement("span");
  id.className = "id";
  id.textContent = String(token.id);
  node.append(body, id);
  node.setAttribute("aria-label", `token ${token.id}: ${spoken(token.hex)}`);
  node.title = `${token.id} · ${token.bytes} byte${token.bytes === 1 ? "" : "s"} · ${spaced(
    token.hex,
  )}`;
  return node;
}

export async function open() {
  const module = await import("../engine/moontoken.js");
  return {
    compose: (text) => JSON.parse(module.compose(text)),
    table: () => JSON.parse(module.table()),
    spec: () => JSON.parse(module.spec()),
  };
}
