import { useEffect, useMemo, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { api, CATEGORIES, categoryLabel, describe, isLow, type Item } from '../api';
import { Icon, Stepper, Thumb } from '../components/ui';

export default function Inventory() {
  const [params, setParams] = useSearchParams();
  const category = params.get('c') || '';
  const lowOnly = params.get('low') === '1';
  const [q, setQ] = useState(params.get('q') || '');
  const [items, setItems] = useState<Item[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  function setParam(key: string, value: string) {
    const next = new URLSearchParams(params);
    if (value) next.set(key, value);
    else next.delete(key);
    setParams(next, { replace: true });
  }

  // Load everything once and filter on the phone: instant search, and counts per category stay accurate.
  useEffect(() => {
    api.items().then(setItems).catch((e) => setError(e.message));
  }, []);

  useEffect(() => {
    const t = setTimeout(() => setParam('q', q.trim()), 250);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [q]);

  const words = q.trim().toLowerCase().split(/\s+/).filter(Boolean);
  const matching = useMemo(() => (items ?? []).filter((it) => {
    if (lowOnly && !(isLow(it) || it.on_list)) return false;
    if (!words.length) return true;
    const hay = [it.name, it.brand, it.type, it.color, it.size, it.location, it.upc, it.sku].join(' ').toLowerCase();
    return words.every((w) => hay.includes(w));
  }), [items, lowOnly, words.join(' ')]);

  const shown = category ? matching.filter((it) => it.category === category) : matching;
  const counts = useMemo(() => {
    const c: Record<string, number> = {};
    for (const it of matching) c[it.category] = (c[it.category] || 0) + 1;
    return c;
  }, [matching]);
  const lowCount = (items ?? []).filter((it) => isLow(it) || it.on_list).length;

  async function adjust(item: Item, delta: number) {
    setItems((list) => list!.map((it) => (it.id === item.id ? { ...it, quantity: Math.max(0, it.quantity + delta) } : it)));
    try {
      const updated = await api.adjust(item.id, delta);
      setItems((list) => list!.map((it) => (it.id === item.id ? updated : it)));
    } catch (e) {
      setError((e as Error).message);
    }
  }

  return (
    <div className="page">
      <header className="page-header">
        <h1>My Tackle</h1>
        <div className="header-actions">
          <Link to="/add" className="btn small"><Icon name="plus" size={18} />Add</Link>
        </div>
      </header>

      <div className="searchbar">
        <Icon name="search" size={18} />
        <input type="search" placeholder="Search name, color, brand, bin…" value={q} onChange={(e) => setQ(e.target.value)}
          aria-label="Search tackle" />
      </div>

      <div className="chips" role="tablist">
        <button className={`chip ${!category ? 'on' : ''}`} onClick={() => setParam('c', '')}>All <span>{matching.length}</span></button>
        {CATEGORIES.filter((c) => counts[c.id] || c.id === category).map((c) => (
          <button key={c.id} className={`chip ${category === c.id ? 'on' : ''}`} onClick={() => setParam('c', c.id)}>
            {c.label} <span>{counts[c.id] || 0}</span>
          </button>
        ))}
        {lowCount > 0 && (
          <button className={`chip warn ${lowOnly ? 'on' : ''}`} onClick={() => setParam('low', lowOnly ? '' : '1')}>
            Need more <span>{lowCount}</span>
          </button>
        )}
      </div>

      {error && <p className="error">{error}</p>}
      {items === null && !error && <p className="muted center">Loading…</p>}

      {items?.length === 0 && (
        <div className="empty">
          <h2>No tackle yet</h2>
          <p>Scan a package's barcode, or paste a Tackle Warehouse link to add your first item.</p>
          <div className="row">
            <Link to="/scan" className="btn"><Icon name="scan" size={18} />Scan a barcode</Link>
            <Link to="/add" className="btn secondary">Add by hand</Link>
          </div>
        </div>
      )}

      {items && items.length > 0 && shown.length === 0 && <p className="muted center">Nothing matches.</p>}

      <ul className="item-list">
        {shown.map((it, i) => (
          <li key={it.id}>
            {!category && (i === 0 || shown[i - 1].category !== it.category) && (
              <h2 className="group-heading">{categoryLabel(it.category)}</h2>
            )}
            <Link to={`/items/${it.id}`} className="item-row">
              <Thumb item={it} />
              <div className="item-text">
                <strong>{it.name}</strong>
                <span className="muted">{describe(it)}</span>
                <span className="tags">
                  {it.location && <span className="tag">{it.location}</span>}
                  {isLow(it) && <span className="tag warn">Low</span>}
                  {it.on_list && !isLow(it) && <span className="tag info">On list</span>}
                </span>
              </div>
              <Stepper value={it.quantity} onChange={(d) => adjust(it, d)} />
            </Link>
          </li>
        ))}
      </ul>
    </div>
  );
}
