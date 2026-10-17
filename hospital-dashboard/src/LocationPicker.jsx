import { useEffect, useRef, useState } from "react";
import L from "leaflet";
import "leaflet/dist/leaflet.css";
import markerIcon from "leaflet/dist/images/marker-icon.png";
import markerIcon2x from "leaflet/dist/images/marker-icon-2x.png";
import markerShadow from "leaflet/dist/images/marker-shadow.png";

// Vite doesn't resolve Leaflet's default icon URLs, so point them at the bundled assets.
L.Icon.Default.mergeOptions({ iconUrl: markerIcon, iconRetinaUrl: markerIcon2x, shadowUrl: markerShadow });

const DEFAULT_CENTER = [10.8505, 76.2711]; // Kerala
const NOMINATIM = "https://nominatim.openstreetmap.org/search";

/**
 * Map + place search that reports a {lat, lng} point.
 * `value` is `null` or {lat, lng}; `onChange({lat, lng})` fires on click, drag,
 * search result or "use my location". Search runs on submit (Enter / button), not
 * per keystroke, to respect Nominatim's usage policy.
 */
export function LocationPicker({ value, onChange }) {
  const mapEl = useRef(null);
  const map = useRef(null);
  const marker = useRef(null);
  const onChangeRef = useRef(onChange);
  onChangeRef.current = onChange;

  const [query, setQuery] = useState("");
  const [results, setResults] = useState([]);
  const [status, setStatus] = useState(null);
  const [busy, setBusy] = useState(false);

  function place(lat, lng, zoom) {
    if (!map.current) return;
    if (marker.current) marker.current.setLatLng([lat, lng]);
    else {
      marker.current = L.marker([lat, lng], { draggable: true }).addTo(map.current);
      marker.current.on("dragend", () => {
        const p = marker.current.getLatLng();
        onChangeRef.current({ lat: p.lat, lng: p.lng });
      });
    }
    if (zoom) map.current.setView([lat, lng], zoom);
  }

  useEffect(() => {
    const start = value ? [value.lat, value.lng] : DEFAULT_CENTER;
    const m = L.map(mapEl.current).setView(start, value ? 16 : 7);
    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19,
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
    }).addTo(m);
    map.current = m;
    if (value) place(value.lat, value.lng);
    m.on("click", (e) => {
      place(e.latlng.lat, e.latlng.lng);
      onChangeRef.current({ lat: e.latlng.lat, lng: e.latlng.lng });
    });
    return () => { m.remove(); map.current = null; marker.current = null; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Keep the pin in sync when lat/lng are typed into the manual fields.
  useEffect(() => {
    if (value && map.current) {
      place(value.lat, value.lng);
      if (!map.current.getBounds().contains([value.lat, value.lng])) map.current.setView([value.lat, value.lng]);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value?.lat, value?.lng]);

  async function search(e) {
    e.preventDefault();
    e.stopPropagation();
    const q = query.trim();
    if (!q) return;
    setBusy(true);
    setStatus(null);
    try {
      const res = await fetch(`${NOMINATIM}?format=jsonv2&limit=5&q=${encodeURIComponent(q)}`);
      if (!res.ok) throw new Error(`Search failed (${res.status})`);
      const found = await res.json();
      setResults(found);
      if (!found.length) setStatus("No places found. Try a more general name or click the map.");
    } catch (err) {
      setStatus(err.message || "Search failed. You can still click the map.");
    } finally {
      setBusy(false);
    }
  }

  function pick(r) {
    const lat = Number(r.lat);
    const lng = Number(r.lon);
    place(lat, lng, 17);
    onChangeRef.current({ lat, lng });
    setResults([]);
  }

  function useMyLocation() {
    if (!navigator.geolocation) return setStatus("Your browser doesn't support geolocation.");
    setStatus("Getting your location…");
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        place(pos.coords.latitude, pos.coords.longitude, 17);
        onChangeRef.current({ lat: pos.coords.latitude, lng: pos.coords.longitude });
        setStatus(null);
      },
      () => setStatus("Couldn't get your location. Search or click the map instead."),
      { enableHighAccuracy: true, timeout: 10000 },
    );
  }

  return (
    <div className="picker">
      <div className="picker-search">
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && search(e)}
          placeholder="Search for your hospital or address"
          aria-label="Search for a place"
        />
        <button type="button" className="tabs-btn" disabled={busy} onClick={search}>{busy ? "Searching…" : "Search"}</button>
        <button type="button" className="tabs-btn" onClick={useMyLocation}>Use my location</button>
      </div>
      {results.length > 0 && (
        <ul className="picker-results">
          {results.map((r) => (
            <li key={r.place_id}><button type="button" onClick={() => pick(r)}>{r.display_name}</button></li>
          ))}
        </ul>
      )}
      {status && <small className="muted">{status}</small>}
      <div ref={mapEl} className="picker-map" />
      <small className="muted">Search, click the map, or drag the pin to set the exact entrance.</small>
    </div>
  );
}
