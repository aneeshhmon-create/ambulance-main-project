import { useCallback, useEffect, useRef, useState } from "react";
import {
  ApiError, POLL_INTERVAL_MS, acceptBroadcast, devSignIn, getHospital, getMe, googleSignIn,
  listBroadcasts, registerHospital, setHospitalActive, setUnauthorizedHandler, updateHospital,
} from "./api.js";
import { clearSession, loadSession, saveSession } from "./session.js";
import { usePolling } from "./usePolling.js";
import { AcceptedCase, Banner, HospitalProfile, IncidentCard, RegisterHospital } from "./components.jsx";
import { Login } from "./Login.jsx";

const NEW_HIGHLIGHT_MS = 10000;

export default function App() {
  const [session, setSession] = useState(loadSession); // { token, account } | null
  const [checking, setChecking] = useState(() => loadSession() !== null);
  // Set when a new Google account still has to register its hospital.
  const [pending, setPending] = useState(null); // { registrationToken, profile }

  const signOut = useCallback(() => {
    clearSession();
    setSession(null);
    setPending(null);
  }, []);

  // Any 401 from the API (expired or revoked token) signs the user out.
  useEffect(() => {
    setUnauthorizedHandler(signOut);
    return () => setUnauthorizedHandler(() => {});
  }, [signOut]);

  // Validate a stored session once on startup. A network failure keeps it:
  // the dashboard shows its own connection errors and retries.
  useEffect(() => {
    if (!session) return undefined;
    let cancelled = false;
    getMe()
      .then((res) => {
        if (cancelled) return;
        const next = { token: session.token, account: res.account };
        saveSession(next);
        setSession(next);
      })
      .catch((e) => {
        if (!cancelled && e instanceof ApiError && e.status && e.status < 500) signOut();
      })
      .finally(() => !cancelled && setChecking(false));
    return () => { cancelled = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function handleAuthResponse(res) {
    if (res.registration_required) {
      setPending({ registrationToken: res.registration_token, profile: res.google_profile });
      return;
    }
    const next = { token: res.access_token, account: res.account };
    saveSession(next);
    setSession(next);
    setPending(null);
  }

  let body;
  if (checking) {
    body = <p className="muted center">Loading…</p>;
  } else if (session) {
    body = <Dashboard account={session.account} />;
  } else if (pending) {
    body = (
      <RegisterHospital
        googleProfile={pending.profile}
        onCancel={() => setPending(null)}
        onCreate={async (hospital) => handleAuthResponse(await registerHospital(pending.registrationToken, hospital))}
      />
    );
  } else {
    body = (
      <Login
        onGoogleToken={async (idToken) => handleAuthResponse(await googleSignIn(idToken))}
        onDevLogin={async (email) => handleAuthResponse(await devSignIn(email))}
      />
    );
  }

  return (
    <div className="app">
      <header className="topbar">
        <h1>🚑 Hospital Dashboard</h1>
        {session && !checking && (
          <div className="account">
            {session.account.photo_url && <img src={session.account.photo_url} alt="" referrerPolicy="no-referrer" />}
            <span>{session.account.name}</span>
            <button className="tabs-btn" onClick={signOut}>Sign out</button>
          </div>
        )}
      </header>
      {body}
    </div>
  );
}

function Dashboard({ account }) {
  const hospitalId = account.hospital_id;
  const [tab, setTab] = useState("incidents");

  return (
    <>
      <nav className="tabs">
        <button className={tab === "incidents" ? "on" : ""} onClick={() => setTab("incidents")}>Emergencies</button>
        <button className={tab === "profile" ? "on" : ""} onClick={() => setTab("profile")}>Hospital profile</button>
      </nav>
      {tab === "incidents"
        ? <Incidents key={hospitalId} hospitalId={hospitalId} />
        : <Profile key={hospitalId} hospitalId={hospitalId} />}
    </>
  );
}

function Incidents({ hospitalId }) {
  const pending = usePolling(() => listBroadcasts(hospitalId, "pending"), hospitalId, POLL_INTERVAL_MS);
  const accepted = usePolling(() => listBroadcasts(hospitalId, "accepted"), hospitalId, POLL_INTERVAL_MS);
  const [now, setNow] = useState(Date.now());
  const [busyId, setBusyId] = useState(null);
  const [notice, setNotice] = useState(null); // {kind, text}
  const [newIds, setNewIds] = useState({}); // broadcast_id -> expiry timestamp
  const seen = useRef(null); // Set of broadcast ids seen so far (null until first load)

  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, []);

  // Flag incidents that show up after the first successful load.
  useEffect(() => {
    if (!pending.data) return;
    const ids = pending.data.map((b) => b.broadcast_id);
    if (seen.current === null) {
      seen.current = new Set(ids);
      return;
    }
    const fresh = ids.filter((id) => !seen.current.has(id));
    ids.forEach((id) => seen.current.add(id));
    if (fresh.length) {
      const until = Date.now() + NEW_HIGHLIGHT_MS;
      setNewIds((cur) => ({ ...cur, ...Object.fromEntries(fresh.map((id) => [id, until])) }));
    }
  }, [pending.data]);

  const removePending = useCallback(
    (broadcastId) => pending.setData((cur) => (cur || []).filter((b) => b.broadcast_id !== broadcastId)),
    [pending.setData], // eslint-disable-line react-hooks/exhaustive-deps
  );

  async function handleAccept(item) {
    setBusyId(item.broadcast_id);
    setNotice(null);
    try {
      await acceptBroadcast(item.incident_id, item.broadcast_id);
      removePending(item.broadcast_id);
      setNotice({ kind: "success", text: `Case #${item.incident_id} accepted. It is now in your accepted cases.` });
      accepted.reload();
    } catch (e) {
      if (e instanceof ApiError && e.status === 409) {
        removePending(item.broadcast_id);
        setNotice({ kind: "warn", text: "Another hospital already accepted this case." });
      } else {
        setNotice({ kind: "error", text: `Could not accept case #${item.incident_id}: ${e.message}` });
      }
    } finally {
      setBusyId(null);
    }
  }

  const list = pending.data;
  return (
    <main className="columns">
      <section className="panel">
        <h2>Incoming emergencies {list && <span className="count">{list.length}</span>}</h2>
        {notice && <Banner kind={notice.kind} onClose={() => setNotice(null)}>{notice.text}</Banner>}
        {pending.error && (
          <Banner>
            {pending.error.message}. {list ? "Showing last known data; retrying…" : "Retrying…"}
          </Banner>
        )}
        {pending.loading && !list && <p className="muted center">Loading incidents…</p>}
        {list && list.length === 0 && !pending.error && <p className="empty">No incoming emergencies</p>}
        {list?.map((item) => (
          <IncidentCard
            key={item.broadcast_id}
            item={item}
            now={now}
            isNew={(newIds[item.broadcast_id] || 0) > now}
            busy={busyId === item.broadcast_id}
            onAccept={handleAccept}
          />
        ))}
      </section>

      <section className="panel">
        <h2>Accepted cases {accepted.data && <span className="count">{accepted.data.length}</span>}</h2>
        {accepted.error && <Banner>Could not refresh accepted cases: {accepted.error.message}</Banner>}
        {accepted.loading && !accepted.data && <p className="muted center">Loading…</p>}
        {accepted.data?.length === 0 && !accepted.error && <p className="empty">No accepted cases yet</p>}
        {accepted.data?.map((item) => <AcceptedCase key={item.broadcast_id} item={item} now={now} />)}
      </section>
    </main>
  );
}

function Profile({ hospitalId }) {
  const [hospital, setHospital] = useState(null);
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let cancelled = false;
    getHospital(hospitalId)
      .then((h) => !cancelled && setHospital(h))
      .catch((e) => !cancelled && setError(e.message));
    return () => { cancelled = true; };
  }, [hospitalId]);

  async function toggle(next) {
    setBusy(true);
    setError(null);
    try {
      const updated = await setHospitalActive(hospitalId, next);
      setHospital(updated);
    } catch (e) {
      setError(`Could not update status: ${e.message}`);
    } finally {
      setBusy(false);
    }
  }

  if (!hospital) {
    return error ? <Banner>{error}</Banner> : <p className="muted center">Loading profile…</p>;
  }
  async function save(fields) {
    setHospital(await updateHospital(hospitalId, fields));
  }

  return <HospitalProfile hospital={hospital} busy={busy} error={error} onToggle={toggle} onSave={save} />;
}
