const COUNTER_API_URL =
  "https://zm3abbwbwt5mnbowbqbymxrcx40fisvc.lambda-url.us-east-1.on.aws/";

async function updateVisitCount() {
  const el = document.getElementById("visitCount");
  if (!el) return;

  // Count only once per tab/session (prevents reload spam)
  const sessionKey = "cv_counted_this_session_v1";
  const alreadyCounted = sessionStorage.getItem(sessionKey) === "1";

  try {
    const res = await fetch(COUNTER_API_URL, {
      method: alreadyCounted ? "GET" : "POST"
    });

    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();

    el.textContent = String(data.count);

    if (!alreadyCounted) sessionStorage.setItem(sessionKey, "1");
  } catch (err) {
    console.error("Counter error:", err);
    el.textContent = "—";
  }
}

document.addEventListener("DOMContentLoaded", () => {
  const yearEl = document.getElementById("year");
  if (yearEl) yearEl.textContent = new Date().getFullYear();

  updateVisitCount();
});
