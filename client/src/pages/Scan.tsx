import { useRef, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { api, describe, isLow, type ScanResult } from '../api';
import Scanner from '../components/LazyScanner';
import { Icon, PageHeader, Stepper, Thumb, toast } from '../components/ui';

export default function Scan() {
  const navigate = useNavigate();
  const [result, setResult] = useState<ScanResult | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [countMode, setCountMode] = useState(false);
  const last = useRef({ code: '', at: 0 });

  async function handle(code: string) {
    // The camera reports the same barcode many times a second; act once per package.
    const now = Date.now();
    if (code === last.current.code && now - last.current.at < 2500) return;
    last.current = { code, at: now };
    if (loading) return;
    setLoading(true);
    setError(null);
    try {
      const res = await api.scan(code);
      if (countMode && res.owned.length === 1) {
        const item = await api.adjust(res.owned[0].id, 1);
        toast(`+1 ${item.name}${item.color ? ` (${item.color})` : ''} → ${item.quantity}`);
      } else {
        setResult(res);
      }
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setLoading(false);
    }
  }

  async function adjust(id: number, delta: number) {
    const updated = await api.adjust(id, delta);
    setResult((r) => r && { ...r, owned: r.owned.map((it) => (it.id === id ? updated : it)) });
  }

  function addNew() {
    navigate('/add', { state: { upc: result!.upc, suggestion: result!.suggestion } });
  }

  const s = result?.suggestion;

  return (
    <div className="page scan-page">
      <PageHeader title="Scan">
        <label className="switch">
          <input type="checkbox" checked={countMode} onChange={(e) => setCountMode(e.target.checked)} />
          <span>Count mode</span>
        </label>
      </PageHeader>
      <p className="muted small hint">
        {countMode
          ? 'Each scan of something you own adds 1. New items stop so you can add them.'
          : 'Scan a package to see if you already own it — in the tackle room or in the store.'}
      </p>

      <Scanner onDetected={handle} paused={!!result} />
      {loading && <p className="muted center">Looking up…</p>}
      {error && <p className="error">{error}</p>}

      {result && (
        <div className="sheet" role="dialog" aria-label="Scan result">
          {result.owned.length > 0 ? (
            <>
              <div className="verdict have">
                <Icon name="check" />
                <div>
                  <strong>You have this</strong>
                  <span>{result.owned.reduce((n, it) => n + it.quantity, 0)} on hand</span>
                </div>
              </div>
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
                  <Stepper value={it.quantity} onChange={(d) => adjust(it.id, d)} />
                </div>
              ))}
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
