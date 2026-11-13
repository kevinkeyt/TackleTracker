import { useEffect, useState } from 'react';
import { categoryLabel, type Item } from '../api';
import { imageSrc } from '../db';

const ICONS: Record<string, string> = {
  box: 'M3 7l9-4 9 4v10l-9 4-9-4V7zm0 0l9 4 9-4M12 11v10',
  scan: 'M4 8V5a1 1 0 011-1h3M16 4h3a1 1 0 011 1v3M20 16v3a1 1 0 01-1 1h-3M8 20H5a1 1 0 01-1-1v-3M7 9v6M10 9v6M13 9v6M17 9v6',
  cart: 'M3 4h2l2.4 11.2a1 1 0 001 .8h9.2a1 1 0 001-.8L20 8H6.2M9 20.5h.01M17 20.5h.01',
  more: 'M5 12h.01M12 12h.01M19 12h.01',
  plus: 'M12 5v14M5 12h14',
  minus: 'M5 12h14',
  search: 'M11 18a7 7 0 110-14 7 7 0 010 14zm9 2l-4.5-4.5',
  back: 'M15 18l-6-6 6-6',
  external: 'M14 4h6v6M20 4l-9 9M18 14v5a1 1 0 01-1 1H5a1 1 0 01-1-1V7a1 1 0 011-1h5',
  camera: 'M4 8a1 1 0 011-1h3l2-2h4l2 2h3a1 1 0 011 1v10a1 1 0 01-1 1H5a1 1 0 01-1-1V8zm8 8a3 3 0 100-6 3 3 0 000 6z',
  check: 'M5 12l5 5 9-10',
};

export function Icon({ name, size = 22 }: { name: keyof typeof ICONS | string; size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={name === 'more' ? 3.5 : 1.9}
      strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d={ICONS[name]} />
    </svg>
  );
}

const CATEGORY_TINT: Record<string, string> = {
  soft_plastic: 'tint-green', hard_bait: 'tint-amber', terminal: 'tint-slate', line: 'tint-blue', rod: 'tint-brown', reel: 'tint-red', other: 'tint-slate',
};

/** Resolves "img:<id>" photos stored on the device to a displayable URL; remote URLs pass through. */
function useImageSrc(ref: string | null) {
  const [src, setSrc] = useState<string | null>(() => {
    const r = imageSrc(ref);
    return typeof r === 'string' ? r : null;
  });
  useEffect(() => {
    let live = true;
    Promise.resolve(imageSrc(ref)).then((s) => live && setSrc(s));
    return () => { live = false; };
  }, [ref]);
  return src;
}

export function Thumb({ item, size = 'sm' }: { item: Pick<Item, 'image_url' | 'category' | 'name'>; size?: 'sm' | 'lg' }) {
  const [failed, setFailed] = useState(false);
  const src = useImageSrc(item.image_url);
  useEffect(() => setFailed(false), [src]);
  if (src && !failed) {
    return <img className={`thumb ${size}`} src={src} alt="" loading="lazy" onError={() => setFailed(true)} />;
  }
  return (
    <div className={`thumb ${size} placeholder ${CATEGORY_TINT[item.category] ?? ''}`} aria-hidden>
      {categoryLabel(item.category).slice(0, 1)}
    </div>
  );
}

export function Stepper({ value, onChange, big = false }: { value: number; onChange: (delta: number) => void; big?: boolean }) {
  return (
    <div className={`stepper ${big ? 'big' : ''}`} onClick={(e) => e.preventDefault()}>
      <button type="button" aria-label="One less" disabled={value <= 0} onClick={(e) => { e.preventDefault(); e.stopPropagation(); onChange(-1); }}>
        <Icon name="minus" size={big ? 24 : 18} />
      </button>
      <span className="stepper-value" aria-live="polite">{value}</span>
      <button type="button" aria-label="One more" onClick={(e) => { e.preventDefault(); e.stopPropagation(); onChange(1); }}>
        <Icon name="plus" size={big ? 24 : 18} />
      </button>
    </div>
  );
}

export function PageHeader({ title, back, children }: { title: string; back?: boolean; children?: React.ReactNode }) {
  return (
    <header className="page-header">
      {back && (
        <button className="icon-btn" onClick={() => history.back()} aria-label="Back">
          <Icon name="back" />
        </button>
      )}
      <h1>{title}</h1>
      <div className="header-actions">{children}</div>
    </header>
  );
}

let toastTimer: number | undefined;
export function toast(message: string) {
  let el = document.getElementById('toast');
  if (!el) {
    el = document.createElement('div');
    el.id = 'toast';
    el.setAttribute('role', 'status');
    document.body.appendChild(el);
  }
  el.textContent = message;
  el.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => el!.classList.remove('show'), 2200);
}

export function money(n: number | null | undefined) {
  return n == null ? '' : n.toLocaleString(undefined, { style: 'currency', currency: 'USD' });
}
