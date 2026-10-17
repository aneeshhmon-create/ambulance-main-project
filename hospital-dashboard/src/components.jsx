import { useState } from "react";
import { formatDistance, label, timeSince } from "./format.js";
import { LocationPicker } from "./LocationPicker.jsx";
import { DepartmentPicker } from "./DepartmentPicker.jsx";

export function BrandMark() {
  return (
    <span className="brand-mark" aria-hidden="true">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.6" strokeLinecap="round">
        <path d="M12 5v14M5 12h14" />
      </svg>
    </span>
  );
}

export function SeverityBadge({ severity }) {
  const s = (severity || "unknown").toLowerCase();
  return <span className={`badge badge-${s}`}>{s}</span>;
}

export function IncidentCard({ item, now, isNew, busy, onAccept, onReject }) {
  const [showTranscript, setShowTranscript] = useState(true);
  const [confirming, setConfirming] = useState(null); // null | "accept" | "reject"
  const [lastAction, setLastAction] = useState(null);

  function confirm() {
    const action = confirming;
    setLastAction(action);
    setConfirming(null);
    (action === "accept" ? onAccept : onReject)(item);
  }

  const sev = (item.severity || "unknown").toLowerCase();
  return (
    <article className={`card sev-${sev} ${isNew ? "is-new" : ""}`}>
      <header className="card-head">
        <SeverityBadge severity={item.severity} />
        <h3>{label(item.emergency_type)}</h3>
        {isNew && <span className="new-tag">NEW</span>}
        <span className="since">{timeSince(item.created_at, now)}</span>
      </header>

      <dl className="facts">
        <div><dt>Department</dt><dd>{item.department_needed || "—"}</dd></div>
        <div><dt>Victims</dt><dd>{item.victims}</dd></div>
        <div><dt>Distance</dt><dd>{formatDistance(item.distance_km)}</dd></div>
        <div><dt>Incident</dt><dd>#{item.incident_id}</dd></div>
      </dl>

      {item.symptoms?.length > 0 && (
        <ul className="chips">
          {item.symptoms.map((s) => <li key={s}>{s}</li>)}
        </ul>
      )}

      {item.transcript && (
        <div className="transcript">
          <button className="link" onClick={() => setShowTranscript((v) => !v)}>
            {showTranscript ? "Hide" : "Show"} transcript
          </button>
          {showTranscript && <blockquote>{item.transcript}</blockquote>}
        </div>
      )}

      <footer>
        {confirming ? (
          <div className={`confirm confirm-${confirming}`} role="alertdialog" aria-label="Confirm your choice">
            <p>
              {confirming === "accept"
                ? <>Accept case <strong>#{item.incident_id}</strong>? Your hospital will be assigned this patient and other hospitals will no longer see it.</>
                : <>Reject case <strong>#{item.incident_id}</strong>? It will be removed from your list. Other hospitals can still accept it.</>}
            </p>
            <div className="row">
              <button type="button" className={confirming === "accept" ? "accept" : "reject-solid"} onClick={confirm}>
                {confirming === "accept" ? "Yes, accept case" : "Yes, reject case"}
              </button>
              <button type="button" className="tabs-btn" onClick={() => setConfirming(null)}>Go back</button>
            </div>
          </div>
        ) : (
          <div className="row actions">
            <button className="accept" disabled={busy} onClick={() => setConfirming("accept")}>
              {busy && lastAction === "accept" ? "Accepting…" : "Accept case"}
            </button>
            <button className="reject" disabled={busy} onClick={() => setConfirming("reject")}>
              {busy && lastAction === "reject" ? "Rejecting…" : "Reject"}
            </button>
          </div>
        )}
      </footer>
    </article>
  );
}

export function AcceptedCase({ item, now }) {
  const amb = item.assigned_ambulance;
  return (
    <article className={`card accepted sev-${(item.severity || "unknown").toLowerCase()}`}>
      <header className="card-head">
        <SeverityBadge severity={item.severity} />
        <h3>{label(item.emergency_type)} <small>#{item.incident_id}</small></h3>
        <span className="since">{timeSince(item.responded_at || item.created_at, now)}</span>
      </header>
      <dl className="facts">
        <div><dt>Status</dt><dd>{label(item.incident_status)}</dd></div>
        <div><dt>Victims</dt><dd>{item.victims}</dd></div>
        <div><dt>Distance</dt><dd>{formatDistance(item.distance_km)}</dd></div>
        <div>
          <dt>Ambulance</dt>
          <dd>
            {amb ? (
              <>
                {amb.driver_name || amb.registration_number}
                {amb.driver_phone && <> · <a href={`tel:${amb.driver_phone}`}>{amb.driver_phone}</a></>}
              </>
            ) : (
              "Not assigned yet"
            )}
          </dd>
        </div>
      </dl>
    </article>
  );
}

export function Banner({ kind = "error", children, onClose }) {
  return (
    <div className={`banner banner-${kind}`} role="alert">
      <span>{children}</span>
      {onClose && <button className="link" onClick={onClose}>Dismiss</button>}
    </div>
  );
}

export function HospitalProfile({ hospital, onSave }) {
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState(hospital.name);
  const [point, setPoint] = useState(hospital.location);
  const [departments, setDepartments] = useState(hospital.departments);
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState(null);

  function startEdit() {
    setName(hospital.name);
    setPoint(hospital.location);
    setDepartments(hospital.departments);
    setSaveError(null);
    setEditing(true);
  }

  async function save(e) {
    e.preventDefault();
    setSaving(true);
    setSaveError(null);
    try {
      await onSave({ name: name.trim(), location: point, departments });
      setEditing(false);
    } catch (err) {
      setSaveError(err.message);
    } finally {
      setSaving(false);
    }
  }

  if (editing) {
    return (
      <form className="panel profile register" onSubmit={save}>
        <h2>Edit hospital profile</h2>
        <label>Name<input required value={name} onChange={(e) => setName(e.target.value)} /></label>
        <LocationPicker value={point} onChange={setPoint} />
        <small className="muted">Location: {point.lat.toFixed(5)}, {point.lng.toFixed(5)}</small>
        <DepartmentPicker value={departments} onChange={setDepartments} />
        {saveError && <Banner>{saveError}</Banner>}
        <div className="row">
          <button className="accept" disabled={saving || !name.trim()}>{saving ? "Saving…" : "Save changes"}</button>
          <button type="button" className="tabs-btn" disabled={saving} onClick={() => setEditing(false)}>Cancel</button>
        </div>
      </form>
    );
  }

  return (
    <section className="panel profile">
      <header className="card-head">
        <h2>Hospital profile</h2>
        <button className="tabs-btn" onClick={startEdit}>Edit profile</button>
      </header>
      <p className="profile-name">{hospital.name}</p>
      <dl className="facts">
        <div>
          <dt>Departments</dt>
          <dd>
            <ul className="chips">
              {hospital.departments.length
                ? hospital.departments.map((d) => <li key={d}>{d}</li>)
                : <li>None</li>}
            </ul>
          </dd>
        </div>
        <div>
          <dt>Location</dt>
          <dd>{hospital.location.lat.toFixed(4)}, {hospital.location.lng.toFixed(4)}</dd>
        </div>
      </dl>
    </section>
  );
}

export function RegisterHospital({ googleProfile, onCreate, onCancel }) {
  const [name, setName] = useState("");
  const [lat, setLat] = useState("");
  const [lng, setLng] = useState("");
  const [departments, setDepartments] = useState([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  async function submit(e) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await onCreate({
        name: name.trim(),
        location: { lat: Number(lat), lng: Number(lng) },
        departments,
      });
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  }

  return (
    <form className="panel profile register" onSubmit={submit}>
      <h2>Register your hospital</h2>
      {googleProfile && (
        <p className="muted">
          Signed in as {googleProfile.name} ({googleProfile.email}). Tell us about the hospital you manage to finish setting up your account.
        </p>
      )}
      <label>Name<input required value={name} onChange={(e) => setName(e.target.value)} /></label>
      <LocationPicker
        value={lat !== "" && lng !== "" && !Number.isNaN(Number(lat)) && !Number.isNaN(Number(lng)) ? { lat: Number(lat), lng: Number(lng) } : null}
        onChange={(p) => { setLat(p.lat.toFixed(6)); setLng(p.lng.toFixed(6)); }}
      />
      <div className="row">
        <label>Latitude<input required type="number" step="any" min="-90" max="90" value={lat} onChange={(e) => setLat(e.target.value)} placeholder="9.9390" /></label>
        <label>Longitude<input required type="number" step="any" min="-180" max="180" value={lng} onChange={(e) => setLng(e.target.value)} placeholder="76.2700" /></label>
      </div>
      <DepartmentPicker value={departments} onChange={setDepartments} />
      {error && <Banner>{error}</Banner>}
      <div className="row">
        <button className="accept" disabled={busy}>{busy ? "Saving…" : "Register hospital"}</button>
        {onCancel && <button type="button" className="tabs-btn" disabled={busy} onClick={onCancel}>Use a different account</button>}
      </div>
    </form>
  );
}
