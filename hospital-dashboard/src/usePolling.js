import { useEffect, useRef, useState } from "react";

/**
 * Calls `fetcher` immediately and then every `intervalMs`.
 * Restarts when `key` changes. Keeps the last good data on errors.
 * Returns { data, error, loading, reload, setData }.
 */
export function usePolling(fetcher, key, intervalMs) {
  const [data, setData] = useState(null);
  const [error, setError] = useState(null);
  const [loading, setLoading] = useState(true);
  const fetcherRef = useRef(fetcher);
  fetcherRef.current = fetcher;
  const reloadRef = useRef(() => {});

  useEffect(() => {
    let cancelled = false;
    let timer;
    setData(null);
    setError(null);
    setLoading(true);

    const run = async () => {
      try {
        const result = await fetcherRef.current();
        if (cancelled) return;
        setData(result);
        setError(null);
      } catch (e) {
        if (!cancelled) setError(e);
      } finally {
        if (!cancelled) setLoading(false);
      }
    };

    reloadRef.current = run;
    run();
    timer = setInterval(run, intervalMs);
    return () => {
      cancelled = true;
      clearInterval(timer);
    };
  }, [key, intervalMs]);

  return { data, error, loading, setData, reload: () => reloadRef.current() };
}
