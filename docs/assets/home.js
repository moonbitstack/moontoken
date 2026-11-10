import { ink, lockup, open, paint, slug, spaced, spoken } from "./engine.js";

const note = document.querySelector("[data-engine-note]");
const manuscript = document.getElementById("manuscript");
const stick = document.getElementById("stick");
const caseBox = document.getElementById("case");
const mergeBox = document.getElementById("merges");
const peel = document.getElementById("peel");
const bench = document.getElementById("bench");
const ids = document.getElementById("ids");
const pull = document.getElementById("pull");

const PROMPT = ["a sort, pulled out", "click a sort to read its bytes"];

let engine = null;
let timer = 0;
let settingTimer = 0;

function say(text, warn = false) {
  if (!note) return;
  note.textContent = text;
  note.classList.toggle("warn", warn);
}

// The line is set from the top left, one sort after another, and the proof is
// pulled across the sheet behind it. Only a fresh line is animated: a reader
// typing should not watch the whole forme fall apart on every keystroke.
function settle(count) {
  if (!stick || !bench) return;
  clearTimeout(settingTimer);
  stick.classList.add("setting");
  bench.classList.add("pulling");
  settingTimer = setTimeout(() => {
    stick.classList.remove("setting");
    bench.classList.remove("pulling");
  }, 460 + Math.min(count, 24) * 22);
}

function idTag(token, index) {
  const tag = document.createElement("span");
  tag.className = "chip " + ink(token.id);
  tag.dataset.i = String(index);
  tag.textContent = String(token.id);
  return tag;
}

function compose(animate = false) {
  if (!engine || !manuscript) return;
  const result = engine.compose(manuscript.value);
  if (result.refused) {
    say(result.refused, true);
    return;
  }
  stick.replaceChildren(...result.tokens.map((token, i) => slug(token, i)));
  lockup(stick);
  ids?.replaceChildren(...result.tokens.map((token, i) => idTag(token, i)));
  document.getElementById("count").textContent = String(result.count);
  document.getElementById("bytes").textContent = String(result.bytes);
  document.getElementById("ratio").textContent =
    result.count === 0 ? "—" : (result.bytes / result.count).toFixed(2);
  document.getElementById("decoded").textContent = result.decoded;
  say("the library, compiled to JavaScript, running in this page");
  if (peel) {
    peel.querySelector(".who").textContent = PROMPT[0];
    peel.querySelector(".what").textContent = PROMPT[1];
  }
  if (animate) settle(result.count);
}

// One sort is lit in the strip of ids when its piece is pointed at: the same
// token, read two ways, on one line.
function light(index, on) {
  const tag = ids?.querySelector(`[data-i="${index}"]`);
  tag?.classList.toggle("hot", on);
}

function head(text) {
  const node = document.createElement("span");
  node.className = "head";
  node.textContent = text;
  return node;
}

function rowLabel(text) {
  const node = document.createElement("span");
  node.className = "rowlab";
  node.textContent = text;
  return node;
}

function caseCell(entry) {
  const cell = document.createElement("button");
  cell.type = "button";
  cell.className = "cell " + ink(entry.id);
  cell.dataset.id = String(entry.id);
  cell.dataset.hex = entry.hex;
  cell.title = `${entry.id} · 0x${entry.hex.toUpperCase()} · ${spoken(entry.hex)}`;
  cell.setAttribute("aria-label", `id ${entry.id}, ${spoken(entry.hex)}`);
  paint(cell, entry.hex);
  cell.addEventListener("click", () => {
    if (!peel) return;
    peel.querySelector(".who").textContent = `id ${entry.id}`;
    peel.querySelector(".what").textContent = `${spaced(entry.hex)} · ${
      entry.hex.length / 2
    } byte${entry.hex.length === 2 ? "" : "s"}`;
  });
  return cell;
}

// The 256 byte entries are laid out as the byte map they are: sixteen columns
// labelled 0 to F, and a row for each high nibble, so a reader can find id 0x4F
// without counting cells.
function fillCase(table) {
  if (!caseBox) return;
  const bytes = table.entries.filter((entry) => entry.id < 256);
  const merges = table.entries.filter((entry) => entry.id >= 256);
  const cells = [head("")];
  for (let column = 0; column < 16; column += 1) {
    cells.push(head(column.toString(16).toUpperCase()));
  }
  for (let row = 0; row < 16; row += 1) {
    cells.push(rowLabel((row * 16).toString(16).toUpperCase().padStart(2, "0")));
    for (let column = 0; column < 16; column += 1) {
      cells.push(caseCell(bytes[row * 16 + column]));
    }
  }
  caseBox.replaceChildren(...cells);
  mergeBox?.replaceChildren(...merges.map(caseCell));
  const count = document.getElementById("case-count");
  if (count) count.textContent = String(table.vocabulary);
  const mergeCount = document.getElementById("merge-count");
  if (mergeCount) mergeCount.textContent = `${merges.length} entries`;
}

if (stick && caseBox) {
  stick.addEventListener("click", (event) => {
    const piece = event.target.closest(".slug");
    if (!piece || !peel) return;
    stick
      .querySelectorAll('.slug[aria-pressed="true"]')
      .forEach((other) => other !== piece && other.setAttribute("aria-pressed", "false"));
    const on = piece.getAttribute("aria-pressed") !== "true";
    piece.setAttribute("aria-pressed", on ? "true" : "false");
    peel.querySelector(".who").textContent = `id ${piece.dataset.id}`;
    peel.querySelector(".what").textContent = `${spaced(piece.dataset.hex)} · ${
      piece.dataset.bytes
    } byte${piece.dataset.bytes === "1" ? "" : "s"}`;
  });

  stick.addEventListener("pointerover", (event) => {
    const piece = event.target.closest(".slug");
    if (piece) light(Number(piece.dataset.i), true);
  });

  stick.addEventListener("pointerout", (event) => {
    const piece = event.target.closest(".slug");
    if (!piece || piece.contains(event.relatedTarget)) return;
    light(Number(piece.dataset.i), false);
  });
}

pull?.addEventListener("click", () => compose(true));

open()
  .then((ready) => {
    engine = ready;
    compose(true);
    fillCase(engine.table());
    const spec = engine.spec();
    document.getElementById("merges-count")?.replaceChildren(
      document.createTextNode(String(spec.merges)),
    );
  })
  .catch(() => {
    say("the engine is not built yet: moon build --target js src/examples/browser", true);
  });

manuscript?.addEventListener("input", () => {
  clearTimeout(timer);
  timer = setTimeout(compose, 60);
});

// The measure changes with the window, and so does the tail of the last line.
addEventListener("resize", () => {
  clearTimeout(timer);
  timer = setTimeout(() => {
    if (stick?.querySelector(".slug")) lockup(stick);
  }, 180);
});
