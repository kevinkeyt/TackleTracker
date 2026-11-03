import { useEffect, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { api, categoryLabel, isLow, shopUrl, type Item } from '../api';
import { Icon, money, PageHeader, Stepper, Thumb, toast } from '../components/ui';

export default function ItemDetail() {
  const { id } = useParams();
  const navigate = useNavigate();
  const [item, setItem] = useState<Item | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.item(id!).then(setItem).catch((e) => setError(e.message));
  }, [id]);

  if (!item) return <div className="page"><PageHeader title="" back />{error ? <p className="error">{error}</p> : <p className="muted center">Loading…</p>}</div>;

  async function adjust(delta: number) {
    setItem((it) => it && { ...it, quantity: Math.max(0, it.quantity + delta) });
    setItem(await api.adjust(item!.id, delta));
  }

  async function toggleList() {
    const updated = await api.update(item!.id, { on_list: !item!.on_list });
    setItem(updated);
    toast(updated.on_list ? 'Added to reorder list' : 'Removed from reorder list');
  }

  async function remove() {
    if (!confirm(`Delete ${item!.name}${item!.color ? ` (${item!.color})` : ''}?`)) return;
    await api.remove(item!.id);
    toast('Deleted');
    navigate('/', { replace: true });
  }

  const rows: [string, React.ReactNode][] = [
    ['Category', categoryLabel(item.category)],
    ['Type', item.type],
    ['Brand', item.brand],
    ['Color', item.color],
    ['Size', item.size],
    ['Kept in', item.location],
    ...Object.entries(item.specs).filter(([, v]) => v).map(([k, v]) => [k, v] as [string, string]),
    ['Price', money(item.price)],
    ['UPC', item.upc],
    ['SKU', item.sku],
    ['Notes', item.notes],
  ];

  return (
    <div className="page">
      <PageHeader title="" back>
        <Link to={`/items/${item.id}/edit`} className="btn ghost small">Edit</Link>
      </PageHeader>

      <div className="detail-hero">
        <Thumb item={item} size="lg" />
        <h1>{item.name}</h1>
        {item.color && <p className="muted">{item.color}</p>}
      </div>

      <div className="card qty-card">
        <div>
          <span className="muted small">On hand</span>
          <div className="qty-line">
            <Stepper value={item.quantity} onChange={adjust} big />
            <span className="muted">{item.unit}{item.quantity === 1 ? '' : 's'}</span>
          </div>
          {item.min_quantity > 0 && (
            <span className={`small ${isLow(item) ? 'warn-text' : 'muted'}`}>
              {isLow(item) ? 'Running low — ' : ''}reorder at {item.min_quantity}
            </span>
          )}
        </div>
      </div>

      <div className="action-grid">
        <a className="btn" href={shopUrl(item)} target="_blank" rel="noreferrer">
          {item.product_url ? 'Buy more' : 'Find on TW'} <Icon name="external" size={16} />
        </a>
        <button className={`btn ${item.on_list ? 'secondary' : 'secondary'}`} onClick={toggleList}>
          {item.on_list ? <><Icon name="check" size={18} />On reorder list</> : <><Icon name="cart" size={18} />Add to list</>}
        </button>
        <Link className="btn secondary" to="/add" state={{ copyFrom: item }}>Add another color</Link>
      </div>

      <dl className="card details">
        {rows.filter(([, v]) => v).map(([k, v]) => (
          <div key={k}><dt>{k}</dt><dd>{v}</dd></div>
        ))}
      </dl>

      <button className="btn danger ghost wide" onClick={remove}>Delete item</button>
    </div>
  );
}
