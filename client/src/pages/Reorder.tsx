import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api, describe, isLow, shopUrl, type Item } from '../api';
import { Icon, money, PageHeader, Thumb, toast } from '../components/ui';

/** How many to buy to get back above the reorder point, with a little headroom. */
const suggested = (it: Item) => Math.max(1, it.min_quantity * 2 - it.quantity);

export default function Reorder() {
  const [items, setItems] = useState<Item[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = () => api.items({ low: true }).then(setItems).catch((e) => setError(e.message));
  useEffect(() => { load(); }, []);

  async function received(it: Item) {
    const answer = prompt(`How many ${it.unit}s of ${it.name}${it.color ? ` (${it.color})` : ''} came in?`, String(suggested(it)));
    if (answer == null) return;
    const n = parseInt(answer, 10);
    if (!(n > 0)) return;
    await api.adjust(it.id, n);
    await api.update(it.id, { on_list: false });
    toast(`Added ${n} — now ${it.quantity + n}`);
    load();
  }

  async function removeFromList(it: Item) {
    await api.update(it.id, { on_list: false });
    load();
  }

  async function copyList() {
    const text = items!.map((it) => `${suggested(it)}× ${it.name}${it.color ? ` — ${it.color}` : ''}${it.size ? ` (${it.size})` : ''}`).join('\n');
    try {
      await navigator.clipboard.writeText(text);
      toast('List copied');
    } catch {
      alert(text);
    }
  }

  const total = items?.reduce((sum, it) => sum + (it.price ?? 0) * suggested(it), 0) ?? 0;

  return (
    <div className="page">
      <PageHeader title="Reorder">
        {!!items?.length && <button className="btn ghost small" onClick={copyList}>Copy list</button>}
      </PageHeader>
      {error && <p className="error">{error}</p>}
      {items === null && !error && <p className="muted center">Loading…</p>}
      {items?.length === 0 && (
        <div className="empty">
          <h2>Nothing to reorder</h2>
          <p>Items show up here when they drop to their reorder level, or when you add them to the list yourself.</p>
        </div>
      )}
      {!!items?.length && total > 0 && <p className="muted small hint">About {money(total)} to restock everything at last known prices.</p>}
      <ul className="item-list">
        {items?.map((it) => (
          <li key={it.id} className="reorder-row">
            <Link to={`/items/${it.id}`} className="item-row">
              <Thumb item={it} />
              <div className="item-text">
                <strong>{it.name}</strong>
                <span className="muted">{describe(it)}</span>
                <span className="tags">
                  <span className={`tag ${isLow(it) ? 'warn' : ''}`}>Have {it.quantity}{it.min_quantity ? ` / min ${it.min_quantity}` : ''}</span>
                  <span className="tag info">Buy ~{suggested(it)}</span>
                  {it.price != null && <span className="tag">{money(it.price)} ea</span>}
                </span>
              </div>
            </Link>
            <div className="row-actions">
              <a className="btn small" href={shopUrl(it)} target="_blank" rel="noreferrer">Shop <Icon name="external" size={14} /></a>
              <button className="btn secondary small" onClick={() => received(it)}>Got it</button>
              {it.on_list && !isLow(it) && <button className="btn ghost small" onClick={() => removeFromList(it)}>Remove</button>}
            </div>
          </li>
        ))}
      </ul>
    </div>
  );
}
