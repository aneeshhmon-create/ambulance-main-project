import { loadSession } from "./session.js";

const BASE = (import.meta.env.VITE_API_BASE_URL || "http://localhost:8000").replace(/\/$/, "");

export const POLL_INTERVAL_MS = Number(import.meta.env.VITE_POLL_INTERVAL_MS) || 4000;

export class ApiError extends Error {
  constructor(message, status) {
    super(message);
    this.status = status; // undefined => network failure
  }
}

// Called when the server rejects our token, so the app can sign out.
let onUnauthorized = () => {};
export function setUnauthorizedHandler(fn) {
  onUnauthorized = fn;
}

async function request(path, options = {}) {
  const token = loadSession()?.token;
  let res;
  try {
    res = await fetch(`${BASE}${path}`, {
      ...options,
      headers: {
        "Content-Type": "application/json",
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
    });
  } catch {
    throw new ApiError(`Cannot reach the server at ${BASE}`, undefined);
  }
  if (res.status === 401 && token) onUnauthorized();
  if (!res.ok) {
    let detail = res.statusText;
    try {
      const body = await res.json();
      if (typeof body.detail === "string") detail = body.detail;
    } catch {
      /* non-JSON error body */
    }
    throw new ApiError(detail, res.status);
  }
  return res.json();
}

export const listHospitals = () => request("/hospitals?limit=500");
export const getHospital = (id) => request(`/hospitals/${id}`);
export const setHospitalActive = (id, isActive) =>
  request(`/hospitals/${id}`, {
    method: "PATCH",
    body: JSON.stringify({ is_active: isActive }),
  });
export const updateHospital = (id, fields) =>
  request(`/hospitals/${id}`, { method: "PATCH", body: JSON.stringify(fields) });
export const listBroadcasts = (id, status) =>
  request(`/hospitals/${id}/broadcasts?status=${status}`);
export const acceptBroadcast = (incidentId, broadcastId) =>
  request(`/incidents/${incidentId}/broadcasts/${broadcastId}/accept`, { method: "POST" });

// ── Authentication ──────────────────────────────────────────────────────────
// Responses are { registration_required, role, access_token, account,
// registration_token, google_profile }; a new Google account gets
// registration_required=true and must call registerHospital.
export const googleSignIn = (idToken) =>
  request("/auth/google", { method: "POST", body: JSON.stringify({ id_token: idToken, role: "hospital" }) });
export const devSignIn = (email) =>
  request("/auth/dev-login", { method: "POST", body: JSON.stringify({ email, role: "hospital" }) });
export const registerHospital = (registrationToken, hospital) =>
  request("/auth/register/hospital", {
    method: "POST",
    body: JSON.stringify({ registration_token: registrationToken, hospital }),
  });
export const getMe = () => request("/auth/me");
