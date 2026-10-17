// Departments the AI triage can route to. Keep in sync with VALID_DEPARTMENTS in
// app/services/extraction_service.py — a hospital only receives cases for departments
// whose names match these exactly.
export const KNOWN_DEPARTMENTS = [
  { name: "Trauma", hint: "Accidents, fractures, severe injuries" },
  { name: "Cardiology", hint: "Heart attacks, chest pain" },
  { name: "General Medicine", hint: "Fever, infections, general illness" },
  { name: "Pediatrics", hint: "Infants and children" },
  { name: "Neurology", hint: "Stroke, seizures, head injury" },
  { name: "Pulmonology", hint: "Breathing difficulty, asthma" },
  { name: "Orthopedics", hint: "Bones, joints, spine" },
  { name: "Burn Care", hint: "Burns and scalds" },
];

/** Case-insensitive match to a known department name, or null. */
export function matchKnown(text) {
  const t = text.trim().toLowerCase();
  return KNOWN_DEPARTMENTS.find((d) => d.name.toLowerCase() === t)?.name ?? null;
}
