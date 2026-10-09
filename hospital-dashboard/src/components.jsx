import { useState } from "react";
import { formatDistance, label, timeSince } from "./format.js";

export function SeverityBadge({ severity }) {
  const s = (severity || "unknown").toLowerCase();
  return <span className={`badge badge-${s}`}>{s}</span>;
}

export function IncidentCard({ item, now, isNew, busy, onAccept }) {
  const [showTranscript, setShowTranscript] = useState(true);
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
        <button className="accept" disabled={busy} onClick={() => onAccept(item)}>
          {busy ? "Accepting…" : "Accept case"}
        </button>
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
              <>{amb.driver_name} · <a href={`tel:${amb.driver_phone}`}>{amb.driver_phone}</a></>
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

export function HospitalProfile({ hospital, busy, error, onToggle }) {
  return (
    <section className="panel profile">
      <h2>Hospital profile</h2>
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
        <div>
          <dt>Status</dt>
          <dd>
            <label className="switch">
              <input
                type="checkbox"
                checked={hospital.is_active}
                disabled={busy}
                onChange={(e) => onToggle(e.target.checked)}
              />
              <span>{hospital.is_active ? "Active — receiving emergencies" : "Inactive — not receiving new emergencies"}</span>
            </label>
          </dd>
        </div>
      </dl>
      {error && <Banner>{error}</Banner>}
    </section>
  );
}
