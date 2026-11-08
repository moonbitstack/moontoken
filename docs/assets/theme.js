// The press a page is printed on. A page opens on the press the reader's own
// system asks for; choosing one by hand carries across the pages of this visit
// and is forgotten on a reload, so a fresh look always starts from the system.

const KEY = "moontoken.press";
const root = document.documentElement;
const button = document.getElementById("theme");

function press() {
  return root.dataset.theme === "night" ? "night" : "day";
}

function label() {
  if (!button) return;
  const now = press();
  button.setAttribute("aria-pressed", now === "night" ? "true" : "false");
  button.title =
    now === "night"
      ? "Night press — switch to the composing room"
      : "Composing room — switch to the night press";
  const text = button.querySelector(".name");
  if (text) text.textContent = now === "night" ? "Night" : "Day";
}

button?.addEventListener("click", () => {
  const next = press() === "night" ? "day" : "night";
  root.dataset.theme = next;
  try {
    sessionStorage.setItem(KEY, next);
  } catch (e) {
    /* a reader who forbids storage still gets the switch for this page */
  }
  label();
});

// With no choice of the reader's own on record, follow the system as it changes.
const system = matchMedia("(prefers-color-scheme: dark)");
system.addEventListener("change", (event) => {
  let chosen = null;
  try {
    chosen = sessionStorage.getItem(KEY);
  } catch (e) {
    chosen = null;
  }
  if (chosen) return;
  root.dataset.theme = event.matches ? "night" : "day";
  label();
});

label();
