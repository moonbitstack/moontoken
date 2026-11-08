// The rail in the margin keeps its place whether or not its slug is printed:
// the sheet shows no edge until it is lifted.
const root = document.documentElement;
const mark = () => root.classList.toggle("at-top", scrollY === 0);
addEventListener("scroll", mark, { passive: true });
mark();
