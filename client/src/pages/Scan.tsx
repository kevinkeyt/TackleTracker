import { useRef, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { api, describe, isLow, type Item, type ScanResult } from '../api';
import Scanner from '../components/LazyScanner';
import { Icon, PageHeader, Stepper, Thumb, toast } from '../components/ui';

type Mode = 'lookup' | 'add' | 'remove';

const MODES: { id: Mode; label: string; hint: string }[] = [
  { id: 'lookup', label: 'Look up', hint: 'Scan a package to see if you already own it — in the tackle room or in the store.' },
  { id: 'add', label: 'Add +1', hint: 'Each scan of something you own adds 1. New items stop so you can add them.' },
  { id: 'remove', label: 'Take out −1', hint: "Each scan takes 1 out of inventory — for loading the boat or using one up." },
];

interface LogEntry {
  key: number;
  item: Item;
  delta: number;
}

function loadMode(): Mode {
  try {
    const m = localStorage.getItem('scanMode');
    return m === 'add' || m === 'remove' ? m : 'lookup';
  } catch {
    return 'lookup';
  }
}

const label = (it: Item) => `${it.name}${it.color ? ` (${it.color})` : ''}`;

export default function Scan() {
  const navigate = useNavigate();
  const [result, setResult] = useState<ScanResult | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [mode, setModeState] = useState<Mode>(loadMode);
  const [log, setLog] = useState<LogEntry[]>([]);
  const last = useRef({ code: '', at: 0 });

  function setMode(m: Mode) {
    setModeState(m);
    try { localStorage.setItem('scanMode', m); } catch { /* private mode */ }
  }

  async function apply(item: Item, delta: number) {
    const updated = await api.adjust(item.id, delta);
    setLog((l) => [{ key: Date.now(), item: updated, delta }, ...l]);
    if (delta < 0) {
      toast(`Took out ${label(updated)} — ${updated.quantity} left${isLow(updated) ? ', now low' : ''}`);
    } else {
      toast(`+1 ${label(updated)} → ${updated.quantity}`);
    }
    return updated;
  }

  async function handle(code: string, source: 'camera' | 'manual') {
    // The camera reports the same barcode many times a second; act once per package.
    const now = Date.now();
    if (source === 'camera' && code === last.current.code && now - last.current.at < 2500) return;
    last.current = { code, at: now };
    if (loading) return;
    setLoading(true);
    setError(null);
    try {
      const res = await api.scan(code);
      const only = res.owned.length === 1 ? res.owned[0] : null;
      if (mode === 'add' && only) {
        await apply(only, 1);
      } else if (mode === 'remove' && only && only.quantity > 0) {
        await apply(only, -1);
      } else {
        if (mode === 'remove' && only) toast(`No ${label(only)} left on hand`);
        setResult(res);
      }
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setLoading(false);
    }
  }

  async function adjust(item: Item, delta: number) {
    const updated = await apply(item, delta);
    setResult((r) => r && { ...r, owned: r.owned.map((it) => (it.id === item.id ? updated : it)) });
  }

  async function undo(entry: LogEntry) {
    const updated = await api.adjust(entry.item.id, -entry.delta);
    setLog((l) => l.filter((e) => e.key !== entry.key));
    toast(`Undone — ${label(updated)} back to ${updated.quantity}`);
  }

  function addNew() {
    navigate('/add', { state: { upc: result!.upc, suggestion: result!.suggestion } });
  }

  const s = result?.suggestion;
  const removed = log.filter((e) => e.delta < 0).length;
  const added = log.filter((e) => e.delta > 0).length;

  return (
    <div className="page scan-page">
      <PageHeader title="Scan" />
      <div className="segmented" role="radiogroup" aria-label="Scan mode">
        {MODES.map((m) => (
          <button key={m.id} role="radio" aria-checked={mode === m.id}
            className={mode === m.id ? `on ${m.id}` : ''} onClick={() => setMode(m.id)}>
            {m.label}
          </button>
        ))}
      </div>
      <p className="muted small hint">{MODES.find((m) => m.id === mode)!.hint}</p>

      <Scanner onDetected={handle} paused={!!result} />
      {loading && <p className="muted center">Looking up…</p>}
      {error && <p className="error">{error}</p>}

      {log.length > 0 && (
        <section className="scan-log">
          <div className="scan-log-head">
            <h2>This session</h2>
            <span className="muted small">
              {[removed && `${removed} taken out`, added && `${added} added`].filter(Boolean).join(' · ')}
            </span>
          </div>
          <ul>
            {log.map((e) => (
              <li key={e.key}>
                <Thumb item={e.item} />
                <div className="item-text">
                  <strong>{e.item.name}</strong>
                  <span className="muted">
                    <span className={e.delta < 0 ? 'delta out' : 'delta in'}>{e.delta < 0 ? '−1' : '+1'}</span>
                    {e.item.color ? ` ${e.item.color} · ` : ' '}{e.item.quantity} left
                  </span>
                </div>
                <button className="btn ghost small" onClick={() => undo(e)}>Undo</button>
              </li>
            ))}
          </ul>
        </section>
      )}

      {result && (
        <div className="sheet" role="dialog" aria-label="Scan result">
          {result.owned.length > 0 ? (
            <>
              {result.owned.some((it) => it.quantity > 0) ? (
                <div className="verdict have">
                  <Icon name="check" />
                  <div>
                    <strong>You have this</strong>
                    <span>{result.owned.reduce((n, it) => n + it.quantity, 0)} on hand</span>
                  </div>
                </div>
              ) : (
                <div className="verdict none">
                  <Icon name="minus" />
                  <div>
                    <strong>None on hand</strong>
                    <span>You've had this before, but they're all used or out</span>
                  </div>
                </div>
              )}
              {result.owned.map((it) => (
                <div key={it.id} className="item-row">
                  <Thumb item={it} />
                  <Link to={`/items/${it.id}`} className="item-text">
                    <strong>{it.name}</strong>
                    <span className="muted">{describe(it)}</span>
                    <span className="tags">
                      {it.location && <span className="tag">{it.location}</span>}
                      {isLow(it) && <span className="tag warn">Low</span>}
                    </span>
                  </Link>
                  <Stepper value={it.quantity} onChange={(d) => adjust(it, d)} />
                </div>
              ))}
              {result.owned.length === 1 && result.owned[0].quantity > 0 && mode !== 'remove' && (
                <button className="btn secondary wide take-out" onClick={() => adjust(result.owned[0], -1)}>
                  Take one out of inventory
                </button>
              )}
            </>
          ) : (
            <>
              <div className="verdict new">
                <Icon name="plus" />
                <div>
                  <strong>Not in your tackle</strong>
                  <span>UPC {result.upc}</span>
                </div>
              </div>
              {s && (
                <div className="item-row">
                  <Thumb item={{ image_url: s.image, category: s.category, name: s.name || '' }} />
                  <div className="item-text">
                    <strong>{s.name}</strong>
                    <span className="muted">{[s.brand, s.color, s.size].filter(Boolean).join(' · ')}</span>
                  </div>
                </div>
              )}
              {!s && <p className="muted small">No product info found for this barcode. You can still add it and fill in the details.</p>}
            </>
          )}
          <div className="sheet-actions">
            {result.owned.length === 0 && <button className="btn" onClick={addNew}>Add to my tackle</button>}
            {result.owned.length > 0 && <button className="btn secondary" onClick={addNew}>Add as separate item</button>}
            <a className="btn secondary" href={result.search_url} target="_blank" rel="noreferrer">
              Tackle Warehouse <Icon name="external" size={16} />
            </a>
            <button className="btn ghost" onClick={() => setResult(null)}>Scan another</button>
          </div>
        </div>
      )}
    </div>
  );
}
