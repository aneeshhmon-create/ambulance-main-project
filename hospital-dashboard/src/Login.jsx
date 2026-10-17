import { useEffect, useRef, useState } from "react";
import { Banner } from "./components.jsx";

const CLIENT_ID = import.meta.env.VITE_GOOGLE_CLIENT_ID || "";
const ALLOW_DEV_LOGIN = import.meta.env.VITE_ALLOW_DEV_LOGIN === "true";
const GSI_SRC = "https://accounts.google.com/gsi/client";

let gsiPromise;
function loadGoogleIdentity() {
  gsiPromise ??= new Promise((resolve, reject) => {
    if (window.google?.accounts?.id) return resolve(window.google);
    const script = document.createElement("script");
    script.src = GSI_SRC;
    script.async = true;
    script.onload = () => resolve(window.google);
    script.onerror = () => {
      gsiPromise = undefined; // allow a retry
      reject(new Error("Could not load Google sign-in. Check your connection."));
    };
    document.head.appendChild(script);
  });
  return gsiPromise;
}

/**
 * Sign-in screen. `onGoogleToken(idToken)` / `onDevLogin(email)` perform the
 * server call and may throw; their message is shown here.
 */
export function Login({ onGoogleToken, onDevLogin }) {
  const buttonRef = useRef(null);
  const handlerRef = useRef(onGoogleToken);
  handlerRef.current = onGoogleToken;
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [email, setEmail] = useState("");

  useEffect(() => {
    if (!CLIENT_ID) return undefined;
    let cancelled = false;
    loadGoogleIdentity()
      .then((google) => {
        if (cancelled || !buttonRef.current) return;
        google.accounts.id.initialize({
          client_id: CLIENT_ID,
          callback: async ({ credential }) => {
            setBusy(true);
            setError(null);
            try {
              await handlerRef.current(credential);
            } catch (e) {
              setError(e.message);
              setBusy(false);
            }
          },
        });
        google.accounts.id.renderButton(buttonRef.current, {
          theme: "outline", size: "large", text: "signin_with", width: 280,
        });
      })
      .catch((e) => !cancelled && setError(e.message));
    return () => { cancelled = true; };
  }, []);

  async function devSubmit(e) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await onDevLogin(email.trim());
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  }

  return (
    <main className="login panel">
      <h2>Sign in</h2>
      <p className="muted">Use your hospital's Google account to manage incoming emergencies.</p>
      {error && <Banner>{error}</Banner>}
      {CLIENT_ID ? (
        <div className="google-btn" ref={buttonRef} aria-busy={busy} style={busy ? { opacity: 0.5, pointerEvents: "none" } : undefined} />
      ) : (
        <Banner kind="warn">
          Google sign-in is not configured: set VITE_GOOGLE_CLIENT_ID in hospital-dashboard/.env.
        </Banner>
      )}
      {ALLOW_DEV_LOGIN && (
        <form className="dev-login register" onSubmit={devSubmit}>
          <small className="muted">DEV ONLY — the backend needs ALLOW_DEV_LOGIN=true</small>
          <label>
            Email
            <input required type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="hospital@example.com" />
          </label>
          <button className="tabs-btn" disabled={busy}>Dev login</button>
        </form>
      )}
    </main>
  );
}
