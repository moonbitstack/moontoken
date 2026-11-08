// The page's half of the engine: it asks the library for tokens and then only
// spells them out. Nothing here cuts text — every id, byte count and decoded
// string comes back from docs/engine/moontoken.js, which the Docs workflow
// builds from src/examples/browser.

const decoder = new TextDecoder("utf-8", { fatal: true });

// A vocabulary entry is bytes, and some of them are not text on their own: a
// three-byte character in a table that never merged it stays three entries.
// Those are printed as hex, which is what they are.
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
  if (text !== null && text.trim() === "" && text.length <= 2) {
    return { text: text.replaceAll(" ", "\u2420").replaceAll("\n", "\u21b5"), hex: false };
  }
  if (text !== null && !/[\u0000-\u001f\u007f]/.test(text)) {
    return { text, hex: false };
  }
  return { text: hex.toUpperCase(), hex: true };
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
  const shown = face(token.hex);
  const node = document.createElement("button");
  node.type = "button";
  node.className = "slug " + ink(token.id);
  node.dataset.id = String(token.id);
  node.dataset.hex = token.hex;
  node.dataset.bytes = String(token.bytes);
  node.setAttribute("aria-pressed", "false");
  const cover = document.createElement("span");
  cover.className = "face";
  if (shown.hex) {
    const small = document.createElement("span");
    small.className = "hex";
    small.textContent = shown.text;
    cover.append(small);
  } else if (shown.text.startsWith("\u2420") || shown.text.startsWith("\u21b5")) {
    const blank = document.createElement("span");
    blank.className = "blank";
    blank.textContent = shown.text;
    cover.append(blank);
  } else {
    cover.textContent = shown.text;
  }
  const id = document.createElement("span");
  id.className = "id";
  id.textContent = String(token.id);
  node.append(cover, id);
  node.title = `${token.id} · ${token.bytes} byte${token.bytes === 1 ? "" : "s"} · ${spaced(token.hex)}`;
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
