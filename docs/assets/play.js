import { face, ink, inkVar, open, slug, spaced } from "./engine.js";

const note = document.querySelector("[data-engine-note]");
const box = document.getElementById("manuscript");
const stick = document.getElementById("stick");
const list = document.getElementById("list");
const peek = document.getElementById("peek");
const ids = document.getElementById("ids");

let engine = null;
let timer = 0;

function say(text, warn = false) {
  if (!note) return;
  note.textContent = text;
  note.classList.toggle("warn", warn);
}

function row(token) {
  const line = document.createElement("div");
  line.className = "row " + ink(token.id);
  const id = document.createElement("span");
  id.className = "i";
  id.textContent = String(token.id);
  const text = document.createElement("span");
  text.className = "t";
  const shown = face(token.hex);
  const span = document.createElement("span");
  span.className = "face";
  span.textContent = shown.hex ? shown.text + " " : shown.text;
  span.style.setProperty("--slug", `var(${inkVar(token.id)})`);
  text.append(span);
  const bytes = document.createElement("span");
  bytes.className = "b";
  bytes.textContent = spaced(token.hex);
  line.append(id, text, bytes);
  return line;
}

function compose() {
  if (!engine || !box) return;
  const result = engine.compose(box.value);
  if (result.refused) {
    say(result.refused, true);
    return;
  }
  say("the library, compiled to JavaScript, in this page");
  stick.replaceChildren(...result.tokens.map(slug));
  list.replaceChildren(...result.tokens.map(row));
  document.getElementById("count").textContent = String(result.count);
  document.getElementById("count-sub").textContent =
    result.count === 1 ? "token" : "tokens";

  const merges = result.tokens.filter((t) => t.id >= 256).length;
  const printable = result.tokens.filter((t) => t.id >= 32 && t.id < 127).length;
  const other = result.count - merges - printable;
  document.getElementById("mix").textContent =
    result.count === 0
      ? "nothing to cut"
      : `${merges} merges · ${printable} printable bytes · ${other} other bytes`;

  document.getElementById("decoded").textContent = result.decoded || "—";
  document.getElementById("cost").textContent =
    result.count === 0
      ? "—"
      : `${result.bytes} bytes · ${(result.bytes / result.count).toFixed(2)} bytes per token`;
  ids.replaceChildren(
    ...result.ids.map((id) => {
      const one = document.createElement("span");
      one.textContent = String(id);
      one.style.setProperty("--slug", `var(${inkVar(id)})`);
      return one;
    }),
  );
  if (peek) peek.textContent = "click a slug to read its bytes";
}

stick?.addEventListener("click", (event) => {
  const piece = event.target.closest(".slug");
  if (!piece || !peek) return;
  stick
    .querySelectorAll('.slug[aria-pressed="true"]')
    .forEach((other) => other !== piece && other.setAttribute("aria-pressed", "false"));
  const on = piece.getAttribute("aria-pressed") !== "true";
  piece.setAttribute("aria-pressed", on ? "true" : "false");
  const count = Number(piece.dataset.bytes);
  peek.textContent = `id ${piece.dataset.id} · ${count} byte${count === 1 ? "" : "s"} · ${spaced(
    piece.dataset.hex,
  )}`;
});

document.querySelectorAll("[data-sample]").forEach((button) => {
  button.addEventListener("click", () => {
    if (!box) return;
    box.value = button.dataset.sample;
    compose();
  });
});

open()
  .then((ready) => {
    engine = ready;
    const spec = engine.spec();
    document.getElementById("spec-size").textContent = String(spec.vocabulary);
    compose();
  })
  .catch(() => {
    say("the engine is not built yet: moon build --target js src/examples/browser", true);
  });

box?.addEventListener("input", () => {
  clearTimeout(timer);
  timer = setTimeout(compose, 60);
});
