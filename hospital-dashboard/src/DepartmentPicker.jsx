import { useState } from "react";
import { KNOWN_DEPARTMENTS, matchKnown } from "./departments.js";

/**
 * Selectable department cards plus a text box for anything else.
 * `value` is the list of selected department names; `onChange(list)` gets the new list.
 * Typing a known name in any case (e.g. "trauma") selects its card instead of adding a duplicate.
 */
export function DepartmentPicker({ value, onChange }) {
  const [draft, setDraft] = useState("");
  const known = new Set(KNOWN_DEPARTMENTS.map((d) => d.name));
  const custom = value.filter((d) => !known.has(d));

  function toggle(name) {
    onChange(value.includes(name) ? value.filter((d) => d !== name) : [...value, name]);
  }

  function addDraft() {
    const added = draft.split(",").map((d) => d.trim()).filter(Boolean).map((d) => matchKnown(d) ?? d);
    if (!added.length) return;
    const lower = new Set(value.map((d) => d.toLowerCase()));
    const fresh = [];
    for (const d of added) {
      if (!lower.has(d.toLowerCase())) { lower.add(d.toLowerCase()); fresh.push(d); }
    }
    onChange([...value, ...fresh]);
    setDraft("");
  }

  return (
    <div className="depts">
      <span className="depts-label">Departments</span>
      <div className="dept-cards" role="group" aria-label="Departments">
        {KNOWN_DEPARTMENTS.map(({ name, hint }) => {
          const on = value.includes(name);
          return (
            <button type="button" key={name} className={`dept-card${on ? " on" : ""}`} aria-pressed={on} onClick={() => toggle(name)}>
              <strong>{on ? "✓ " : ""}{name}</strong>
              <small>{hint}</small>
            </button>
          );
        })}
      </div>
      {custom.length > 0 && (
        <ul className="chips">
          {custom.map((d) => (
            <li key={d}>{d} <button type="button" className="chip-x" aria-label={`Remove ${d}`} onClick={() => toggle(d)}>×</button></li>
          ))}
        </ul>
      )}
      <div className="picker-search">
        <input
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); addDraft(); } }}
          placeholder="Other department (comma separated)"
          aria-label="Add another department"
        />
        <button type="button" className="tabs-btn" onClick={addDraft}>Add</button>
      </div>
      <small className="muted">
        Cases are routed by the AI to the departments above. Custom names are saved but may not receive automatic cases.
      </small>
    </div>
  );
}
