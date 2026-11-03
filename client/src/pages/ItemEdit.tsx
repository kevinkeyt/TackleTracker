import { useEffect, useMemo, useState } from 'react';
import { Link, useLocation, useNavigate, useParams } from 'react-router-dom';
import {
  api, CATEGORIES, describe, SPEC_FIELDS, twSearchUrl, UNITS,
  type Category, type Item, type ItemInput, type TwProduct, type TwVariant, type UpcSuggestion,
} from '../api';
import Scanner from '../components/LazyScanner';
import { Icon, money, PageHeader, Stepper, Thumb, toast } from '../components/ui';

const EMPTY: ItemInput = {
  name: '', brand: null, category: 'soft_plastic', type: null, color: null, size: null, quantity: 1, unit: 'pack',
  min_quantity: 0, location: null, upc: null, sku: null, price: null, image_url: null, product_url: null,
  specs: {}, notes: null, on_list: false,
};

interface PrefillState {
  upc?: string;
  suggestion?: UpcSuggestion | null;
  copyFrom?: Item;
}

export default function ItemEdit() {
  const { id } = useParams();
  const navigate = useNavigate();
  const prefill = (useLocation().state || {}) as PrefillState;
  const [form, setForm] = useState<ItemInput>(() => initialForm(prefill));
  const [loaded, setLoaded] = useState(!id);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [scanning, setScanning] = useState(false);
  const [all, setAll] = useState<Item[]>([]);

  const [twUrl, setTwUrl] = useState(prefill.copyFrom?.product_url || '');
  const [tw, setTw] = useState<TwProduct | null>(null);
  const [twLoading, setTwLoading] = useState(false);
  const [variantFilter, setVariantFilter] = useState('');
  const [imageBusy, setImageBusy] = useState(false);

  useEffect(() => {
    api.items().then(setAll).catch(() => {});
    if (id) api.item(id).then((it) => { setForm(it); setTwUrl(it.product_url || ''); setLoaded(true); }).catch((e) => setError(e.message));
  }, [id]);

  // Same product family: jump straight to its color list so adding another color is two taps.
  useEffect(() => {
    if (prefill.copyFrom?.product_url && /tacklewarehouse\.com/.test(prefill.copyFrom.product_url)) loadTw(prefill.copyFrom.product_url);
    else if (prefill.suggestion?.image) saveRemoteImage(prefill.suggestion.image);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const set = <K extends keyof ItemInput>(key: K, value: ItemInput[K]) => setForm((f) => ({ ...f, [key]: value }));
  const text = (key: keyof ItemInput) => ({
    value: (form[key] as string | null) ?? '',
    onChange: (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>) => set(key, e.target.value as never),
  });

  const sameUpc = useMemo(() => {
    const upc = form.upc?.replace(/\D/g, '').replace(/^0+/, '');
    return upc ? all.filter((it) => it.upc === upc && String(it.id) !== id) : [];
  }, [all, form.upc, id]);

  const similar = useMemo(() => {
    if (sameUpc.length || form.name.trim().length < 3) return [];
    const words = form.name.toLowerCase().split(/\s+/).filter((w) => w.length > 2);
    const color = form.color?.toLowerCase();
    return all.filter((it) => String(it.id) !== id && words.every((w) => it.name.toLowerCase().includes(w)) &&
      (!color || it.color?.toLowerCase() === color)).slice(0, 4);
  }, [all, form.name, form.color, sameUpc.length, id]);

  const locations = useMemo(() => [...new Set(all.map((it) => it.location).filter(Boolean))].sort() as string[], [all]);
  const brands = useMemo(() => [...new Set(all.map((it) => it.brand).filter(Boolean))].sort() as string[], [all]);
  const types = CATEGORIES.find((c) => c.id === form.category)?.types ?? [];

  async function loadTw(url = twUrl) {
    if (!url.trim()) return;
    setTwLoading(true);
    setError(null);
    try {
      const product = await api.twProduct(url.trim());
      setTw(product);
      setVariantFilter('');
      const upc = form.upc?.replace(/^0+/, '');
      const match = upc && product.variants.find((v) => v.upc === upc);
      if (match) await applyVariant(product, match);
      else if (product.variants.length === 1) await applyVariant(product, product.variants[0]);
      else if (!id && !form.name) setForm((f) => ({ ...f, name: product.name, brand: product.brand, category: product.category, product_url: product.url }));
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setTwLoading(false);
    }
  }

  async function pasteTw() {
    try {
      const clip = await navigator.clipboard.readText();
      setTwUrl(clip);
      if (/descpage-/i.test(clip)) loadTw(clip);
    } catch {
      toast('Long-press the box and choose Paste');
    }
  }

  async function applyVariant(product: TwProduct, v: TwVariant) {
    setForm((f) => ({
      ...f,
      name: product.name,
      brand: product.brand ?? f.brand,
      category: f.name && id ? f.category : product.category,
      color: v.color ?? f.color,
      size: v.size ?? f.size,
      sku: v.sku,
      price: v.price,
      upc: v.upc ?? f.upc,
      product_url: product.url,
      specs: { ...f.specs, ...Object.fromEntries(Object.entries(v.styles).filter(([k]) => k !== 'Color')) },
    }));
    const img = v.image || product.image;
    if (img) await saveRemoteImage(img);
    setTw(null);
    toast(`Filled in ${v.color || v.name}`);
  }

  async function saveRemoteImage(url: string) {
    setImageBusy(true);
    try {
      const { url: local } = await api.cacheImage(url);
      set('image_url', local);
    } catch {
      set('image_url', url);
    } finally {
      setImageBusy(false);
    }
  }

  async function uploadPhoto(file: File | undefined) {
    if (!file) return;
    setImageBusy(true);
    try {
      const { url } = await api.uploadImage(file);
      set('image_url', url);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setImageBusy(false);
    }
  }

  async function save(e: React.FormEvent) {
    e.preventDefault();
    if (!form.name.trim()) return setError('Give it a name');
    setSaving(true);
    setError(null);
    try {
      const saved = id ? await api.update(Number(id), form) : await api.create(form);
      toast(id ? 'Saved' : 'Added to your tackle');
      navigate(`/items/${saved.id}`, { replace: true });
    } catch (e) {
      setError((e as Error).message);
      setSaving(false);
    }
  }

  if (!loaded) return <div className="page"><PageHeader title="Edit" back />{error ? <p className="error">{error}</p> : <p className="muted center">Loading…</p>}</div>;

  const variants = tw?.variants.filter((v) => !variantFilter || v.name.toLowerCase().includes(variantFilter.toLowerCase())) ?? [];
  const specFields = SPEC_FIELDS[form.category] ?? [];

  return (
    <div className="page">
      <PageHeader title={id ? 'Edit item' : 'Add tackle'} back />

      <section className="card tw-import">
        <h2>Fill in from Tackle Warehouse</h2>
        <p className="muted small">
          Open the product on Tackle Warehouse, copy its link, then paste it here. You'll pick the color and we'll grab the photo, price and UPC.
        </p>
        <div className="row">
          <input type="url" placeholder="https://www.tacklewarehouse.com/…/descpage-…" value={twUrl}
            onChange={(e) => setTwUrl(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && (e.preventDefault(), loadTw())} aria-label="Tackle Warehouse link" />
          {twUrl ? (
            <button type="button" className="btn" onClick={() => loadTw()} disabled={twLoading}>{twLoading ? '…' : 'Load'}</button>
          ) : (
            <button type="button" className="btn secondary" onClick={pasteTw}>Paste</button>
          )}
        </div>
        <a className="link small" target="_blank" rel="noreferrer"
          href={twSearchUrl([form.brand, form.name].filter(Boolean).join(' ') || form.upc || '')}>
          Find it on Tackle Warehouse <Icon name="external" size={14} />
        </a>

        {tw && (
          <div className="variants">
            <div className="variants-head">
              <strong>{tw.name}</strong>
              <span className="muted small">{tw.variants.length} options — tap yours</span>
            </div>
            {tw.variants.length > 8 && (
              <input type="search" placeholder="Filter colors…" value={variantFilter} onChange={(e) => setVariantFilter(e.target.value)} />
            )}
            <div className="variant-grid">
              {variants.map((v) => (
                <button type="button" key={v.sku ?? v.name} className="variant" onClick={() => applyVariant(tw, v)}>
                  {v.image ? <img src={v.image} alt="" loading="lazy" /> : <div className="variant-noimg" />}
                  <span>{v.color || Object.values(v.styles).join(' / ') || v.name}</span>
                  <span className="muted small">{money(v.price)}</span>
                </button>
              ))}
            </div>
          </div>
        )}
      </section>

      <form onSubmit={save} className="item-form">
        {sameUpc.length > 0 && (
          <div className="notice warn">
            <strong>You already have this barcode:</strong>
            {sameUpc.map((it) => (
              <Link key={it.id} to={`/items/${it.id}`}>{it.name}{it.color ? ` — ${it.color}` : ''} ({it.quantity} {it.unit})</Link>
            ))}
          </div>
        )}
        {similar.length > 0 && (
          <div className="notice">
            <strong>Similar items you have:</strong>
            {similar.map((it) => (
              <Link key={it.id} to={`/items/${it.id}`}>{it.name} — {describe(it)} ({it.quantity})</Link>
            ))}
          </div>
        )}

        <div className="photo-row">
          <Thumb item={form} size="lg" />
          <div className="photo-actions">
            <label className="btn secondary small">
              <Icon name="camera" size={18} />{imageBusy ? 'Saving…' : form.image_url ? 'Retake photo' : 'Take photo'}
              <input type="file" accept="image/*" capture="environment" hidden onChange={(e) => uploadPhoto(e.target.files?.[0])} />
            </label>
            {form.image_url && <button type="button" className="btn ghost small" onClick={() => set('image_url', null)}>Remove photo</button>}
          </div>
        </div>

        <label className="field">
          <span>Name *</span>
          <input {...text('name')} required placeholder="e.g. Zoom Trick Worm" />
        </label>

        <div className="grid2">
          <label className="field">
            <span>Category</span>
            <select value={form.category} onChange={(e) => set('category', e.target.value as Category)}>
              {CATEGORIES.map((c) => <option key={c.id} value={c.id}>{c.label}</option>)}
            </select>
          </label>
          <label className="field">
            <span>Type</span>
            <input {...text('type')} list="types" placeholder={types[0] || ''} />
            <datalist id="types">{types.map((t) => <option key={t} value={t} />)}</datalist>
          </label>
          <label className="field">
            <span>Brand</span>
            <input {...text('brand')} list="brands" />
            <datalist id="brands">{brands.map((b) => <option key={b} value={b} />)}</datalist>
          </label>
          <label className="field">
            <span>Color</span>
            <input {...text('color')} placeholder="Green Pumpkin" />
          </label>
          <label className="field">
            <span>Size / weight</span>
            <input {...text('size')} placeholder='6.5" or 3/8 oz' />
          </label>
          <label className="field">
            <span>Where it's kept</span>
            <input {...text('location')} list="locations" placeholder="Bin 3, Boat box…" />
            <datalist id="locations">{locations.map((l) => <option key={l} value={l} />)}</datalist>
          </label>
        </div>

        <div className="grid2 qty">
          <div className="field">
            <span>On hand</span>
            <div className="row">
              <Stepper value={form.quantity} onChange={(d) => set('quantity', Math.max(0, form.quantity + d))} />
              <select value={form.unit} onChange={(e) => set('unit', e.target.value)} aria-label="Unit">
                {UNITS.map((u) => <option key={u} value={u}>{u}{form.quantity === 1 ? '' : u.endsWith('x') ? 'es' : 's'}</option>)}
              </select>
            </div>
          </div>
          <div className="field">
            <span>Reorder at or below</span>
            <Stepper value={form.min_quantity} onChange={(d) => set('min_quantity', Math.max(0, form.min_quantity + d))} />
            <small className="muted">{form.min_quantity ? `Flagged when you're down to ${form.min_quantity}` : '0 = never flag'}</small>
          </div>
        </div>

        {specFields.length > 0 && (
          <div className="grid2">
            {specFields.map((k) => (
              <label key={k} className="field">
                <span>{k}</span>
                <input value={form.specs[k] ?? ''} onChange={(e) => set('specs', { ...form.specs, [k]: e.target.value })} />
              </label>
            ))}
          </div>
        )}

        <div className="grid2">
          <label className="field">
            <span>UPC</span>
            <div className="row">
              <input {...text('upc')} inputMode="numeric" />
              <button type="button" className="icon-btn" onClick={() => setScanning(true)} aria-label="Scan UPC"><Icon name="scan" /></button>
            </div>
          </label>
          <label className="field">
            <span>Price</span>
            <input type="number" inputMode="decimal" step="0.01" min="0" value={form.price ?? ''}
              onChange={(e) => set('price', e.target.value === '' ? null : Number(e.target.value))} />
          </label>
        </div>

        <label className="field">
          <span>Product link</span>
          <input type="url" {...text('product_url')} placeholder="Where to reorder" />
        </label>

        <label className="field">
          <span>Notes</span>
          <textarea {...text('notes')} rows={3} placeholder="Rigging, what it works on, etc." />
        </label>

        <label className="check">
          <input type="checkbox" checked={form.on_list} onChange={(e) => set('on_list', e.target.checked)} />
          Put on my reorder list
        </label>

        {error && <p className="error">{error}</p>}
        <div className="form-actions">
          <button className="btn wide" disabled={saving || imageBusy}>{saving ? 'Saving…' : id ? 'Save changes' : 'Add to my tackle'}</button>
        </div>
      </form>

      {scanning && (
        <div className="sheet">
          <Scanner onDetected={(code) => { set('upc', code); setScanning(false); }} />
          <button className="btn ghost wide" onClick={() => setScanning(false)}>Cancel</button>
        </div>
      )}
    </div>
  );
}

function initialForm({ upc, suggestion: s, copyFrom: c }: PrefillState): ItemInput {
  if (c) {
    // "Add another color": keep the product, drop what's specific to the old color.
    const { id: _id, created_at: _c, updated_at: _u, ...rest } = c;
    return { ...rest, color: null, upc: null, sku: null, image_url: null, quantity: 1, on_list: false };
  }
  return {
    ...EMPTY,
    upc: upc ?? null,
    name: s?.name ?? '',
    brand: s?.brand ?? null,
    color: s?.color ?? null,
    size: s?.size ?? null,
    category: s?.category && s.category !== 'other' ? s.category : EMPTY.category,
  };
}
