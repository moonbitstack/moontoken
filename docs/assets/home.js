import { face, ink, open, slug, spaced } from "./engine.js";

const note = document.querySelector("[data-engine-note]");
const manuscript = document.getElementById("manuscript");
const stick = document.getElementById("stick");
const caseBox = document.getElementById("case");
const mergeBox = document.getElementById("merges");
const peel = document.getElementById("peel");

let engine = null;
let timer = 0;

function say(text, warn = false) {
  if (!note) return;
  note.textContent = text;
  note.classList.toggle("warn", warn);
}

function compose() {
  if (!engine || !manuscript) return;
  const result = engine.compose(manuscript.value);
  if (result.refused) {
    say(result.refused, true);
    return;
  }
  stick.replaceChildren(...result.tokens.map(slug));
  document.getElementById("count").textContent = String(result.count);
  document.getElementById("bytes").textContent = String(result.bytes);
  document.getElementById("ratio").textContent =
    result.count === 0 ? "—" : (result.bytes / result.count).toFixed(2);
  document.getElementById("decoded").textContent = result.decoded;
  say("the library, compiled to JavaScript, running in this page");
  if (peel) {
    peel.querySelector(".who").textContent = "every id, from the table";
    peel.querySelector(".what").textContent =
      result.ids.join(" ") || "nothing to encode";
  }
}

function caseCell(entry) {
  const shown = face(entry.hex);
  const cell = document.createElement("button");
  cell.type = "button";
  cell.className = "cell " + ink(entry.id);
  cell.dataset.id = String(entry.id);
  cell.dataset.hex = entry.hex;
  cell.title = `${entry.id} · ${spaced(entry.hex)}`;
  if (shown.hex) {
    const hex = document.createElement("span");
    hex.className = "hex";
    hex.textContent = shown.text;
    cell.append(hex);
  } else {
    cell.textContent = shown.text;
  }
  cell.addEventListener("click", () => {
    if (!peel) return;
    peel.querySelector(".who").textContent = `id ${entry.id}`;
    peel.querySelector(".what").textContent = `${spaced(entry.hex)} · ${
      entry.hex.length / 2
    } byte${entry.hex.length === 2 ? "" : "s"}`;
  });
  return cell;
}

function fillCase(table) {
  if (!caseBox) return;
  const bytes = table.entries.filter((entry) => entry.id < 256);
  const merges = table.entries.filter((entry) => entry.id >= 256);
  caseBox.replaceChildren(...bytes.map(caseCell));
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
}

open()
  .then((ready) => {
    engine = ready;
    compose();
    const table = engine.table();
    fillCase(table);
    const spec = engine.spec();
    document.getElementById("merges")?.replaceChildren(
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
