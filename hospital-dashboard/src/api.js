const BASE = (import.meta.env.VITE_API_BASE_URL || "http://localhost:8000").replace(/\/$/, "");

export const POLL_INTERVAL_MS = Number(import.meta.env.VITE_POLL_INTERVAL_MS) || 4000;

export class ApiError extends Error {
  constructor(message, status) {
    super(message);
    this.status = status; // undefined => network failure
  }
}

async function request(path, options = {}) {
  let res;
  try {
    res = await fetch(`${BASE}${path}`, {
      headers: { "Content-Type": "application/json" },
      ...options,
    });
  } catch {
    throw new ApiError(`Cannot reach the server at ${BASE}`, undefined);
  }
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
export const listBroadcasts = (id, status) =>
  request(`/hospitals/${id}/broadcasts?status=${status}`);
export const acceptBroadcast = (incidentId, broadcastId) =>
  request(`/incidents/${incidentId}/broadcasts/${broadcastId}/accept`, { method: "POST" });
