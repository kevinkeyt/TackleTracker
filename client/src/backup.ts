import { api, type Item } from './api';

const LAST_KEY = 'lastBackupAt';
export const BACKUP_REMIND_DAYS = 14;

export function lastBackupAt(): Date | null {
  try {
    const v = localStorage.getItem(LAST_KEY);
    return v ? new Date(v) : null;
  } catch {
    return null;
  }
}

export function daysSinceBackup() {
  const last = lastBackupAt();
  return last ? Math.floor((Date.now() - last.getTime()) / 86_400_000) : null;
}

const stamp = () => new Date().toISOString().slice(0, 10);

/**
 * Hands the file to the phone's share sheet (Save to Files → iCloud Drive, AirDrop, email),
 * or downloads it where sharing files isn't supported.
 */
async function shareOrDownload(file: File) {
  if (navigator.canShare?.({ files: [file] })) {
    try {
      await navigator.share({ files: [file], title: file.name });
      return true;
    } catch (e) {
      if ((e as Error).name === 'AbortError') return false;
    }
  }
  const url = URL.createObjectURL(file);
  const a = Object.assign(document.createElement('a'), { href: url, download: file.name });
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
  return true;
}

export async function backUpNow() {
  const backup = await api.exportBackup();
  const file = new File([JSON.stringify(backup)], `tackle-backup-${stamp()}.json`, { type: 'application/json' });
  const done = await shareOrDownload(file);
  if (done) {
    try { localStorage.setItem(LAST_KEY, new Date().toISOString()); } catch { /* storage blocked */ }
  }
  return done;
}

export async function exportCsv() {
  const cols: (keyof Item)[] = ['name', 'brand', 'category', 'type', 'color', 'size', 'quantity', 'unit', 'min_quantity',
    'location', 'upc', 'sku', 'price', 'product_url', 'notes'];
  const esc = (v: unknown) => (v == null ? '' : /[",\n]/.test(String(v)) ? `"${String(v).replace(/"/g, '""')}"` : String(v));
  const rows = (await api.items()).map((it) => cols.map((c) => esc(it[c])).join(','));
  const file = new File([[cols.join(','), ...rows].join('\n')], `tackle-${stamp()}.csv`, { type: 'text/csv' });
  return shareOrDownload(file);
}
