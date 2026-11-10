import { ink, inkVar, lockup, open, paint, slug, spaced, spoken } from "./engine.js";

const note = document.querySelector("[data-engine-note]");
const box = document.getElementById("manuscript");
const stick = document.getElementById("stick");
const list = document.getElementById("list");
const peek = document.getElementById("peek");
const ids = document.getElementById("ids");

let engine = null;
let timer = 0;
let settingTimer = 0;

function say(text, warn = false) {
  if (!note) return;
  note.textContent = text;
  note.classList.toggle("warn", warn);
}

// A line set on the stick is animated once; typing is not.
function settle(count) {
  if (!stick) return;
  clearTimeout(settingTimer);
  stick.classList.add("setting");
  settingTimer = setTimeout(() => {
    stick.classList.remove("setting");
  }, 460 + Math.min(count, 24) * 22);
}

function row(token, index) {
  const line = document.createElement("div");
  line.className = "row " + ink(token.id);
  line.dataset.i = String(index);
  const id = document.createElement("span");
  id.className = "i";
  id.textContent = String(token.id);
  line.setAttribute("aria-label", `token ${token.id}, ${spoken(token.hex)}`);
  const text = document.createElement("span");
  text.className = "t";
  const span = document.createElement("span");
  span.className = "face";
  span.style.setProperty("--slug", `var(${inkVar(token.id)})`);
  paint(span, token.hex);
  text.append(span);
  const bytes = document.createElement("span");
  bytes.className = "b";
  bytes.textContent = spaced(token.hex);
  line.append(id, text, bytes);
  return line;
}

// One token, three views of it: the sort on the stick, the tag in the strip of
// ids, and the line in the list. Pointing at any of them lights the other two.
function light(index, on) {
  for (const node of document.querySelectorAll(`[data-i="${index}"]`)) {
    if (node.classList.contains("slug")) continue;
    node.classList.toggle("hot", on);
  }
  stick?.querySelectorAll(`.slug[data-i="${index}"]`).forEach((piece) => {
    piece.classList.toggle("hot", on);
  });
}

function watch(container) {
  container?.addEventListener("pointerover", (event) => {
    const node = event.target.closest("[data-i]");
    if (node) light(Number(node.dataset.i), true);
  });
  container?.addEventListener("pointerout", (event) => {
    const node = event.target.closest("[data-i]");
    if (!node || node.contains(event.relatedTarget)) return;
    light(Number(node.dataset.i), false);
  });
}

function compose(animate = false) {
  if (!engine || !box) return;
  const result = engine.compose(box.value);
  if (result.refused) {
    say(result.refused, true);
    return;
  }
  say("the library, compiled to JavaScript, in this page");
  stick.replaceChildren(...result.tokens.map((token, i) => slug(token, i)));
  lockup(stick);
  list.replaceChildren(...result.tokens.map((token, i) => row(token, i)));
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
    ...result.ids.map((id, index) => {
      const one = document.createElement("span");
      one.textContent = String(id);
      one.dataset.i = String(index);
      one.style.setProperty("--slug", `var(${inkVar(id)})`);
      return one;
    }),
  );
  if (peek) peek.textContent = "click a slug to read its bytes";
  if (animate) settle(result.count);
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

watch(stick);
watch(list);
watch(ids);

document.querySelectorAll("[data-sample]").forEach((button) => {
  button.addEventListener("click", () => {
    if (!box) return;
    box.value = button.dataset.sample;
    compose(true);
  });
});

open()
  .then((ready) => {
    engine = ready;
    const spec = engine.spec();
    document.getElementById("spec-size").textContent = String(spec.vocabulary);
    compose(true);
  })
  .catch(() => {
    say("the engine is not built yet: moon build --target js src/examples/browser", true);
  });

box?.addEventListener("input", () => {
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
