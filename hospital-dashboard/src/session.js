// Signed-in session ({ token, account }) kept in localStorage so a reload
// keeps the hospital signed in. The token is validated against the server
// on startup (see App.jsx) and dropped on any 401.
const KEY = "hospitalSession";

export function loadSession() {
  try {
    const s = JSON.parse(localStorage.getItem(KEY));
    return s?.token && s?.account ? s : null;
  } catch {
    return null;
  }
}

export function saveSession(session) {
  try { localStorage.setItem(KEY, JSON.stringify(session)); } catch { /* ignore */ }
}

export function clearSession() {
  try { localStorage.removeItem(KEY); } catch { /* ignore */ }
}
