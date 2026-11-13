import { useEffect, useState } from 'react';
import { api, categoryLabel, type CategoryStats } from '../api';
import { backUpNow, daysSinceBackup, exportCsv } from '../backup';
import { getUpcRelay, setUpcRelay } from '../lookup';
import { money, PageHeader, toast } from '../components/ui';

const isStandalone = () =>
  window.matchMedia?.('(display-mode: standalone)').matches || (navigator as { standalone?: boolean }).standalone === true;

function formatBytes(n: number) {
  return n > 1e6 ? `${(n / 1e6).toFixed(1)} MB` : `${Math.max(1, Math.round(n / 1e3))} KB`;
}

export default function More() {
  const [stats, setStats] = useState<CategoryStats[]>([]);
  const [usage, setUsage] = useState<number | null>(null);
  const [persisted, setPersisted] = useState<boolean | null>(null);
  const [days, setDays] = useState(daysSinceBackup);
  const [relay, setRelay] = useState(getUpcRelay);
  const [busy, setBusy] = useState(false);

  const refresh = () => {
    api.stats().then(setStats).catch(() => {});
    navigator.storage?.estimate?.().then((e) => setUsage(e.usage ?? null)).catch(() => {});
    navigator.storage?.persisted?.().then(setPersisted).catch(() => {});
  };
  useEffect(refresh, []);

  const totals = stats.reduce((t, s) => ({ items: t.items + s.items, units: t.units + s.units, value: t.value + s.value }),
    { items: 0, units: 0, value: 0 });

  async function backup() {
    setBusy(true);
    try {
      if (await backUpNow()) {
        setDays(daysSinceBackup());
        toast('Backup saved');
      }
    } catch (e) {
      alert(`Backup failed: ${(e as Error).message}`);
    } finally {
      setBusy(false);
    }
  }

  async function restore(file: File | undefined) {
    if (!file) return;
    try {
      const data = JSON.parse(await file.text());
      const replace = confirm('Replace everything on this phone with this backup?\n\nOK = replace, Cancel = add to what you have');
      const n = await api.importBackup(data, replace);
      toast(`Restored ${n} items`);
      refresh();
    } catch (e) {
      alert(`Restore failed: ${(e as Error).message}`);
    }
  }

  function saveRelay(e: React.FormEvent) {
    e.preventDefault();
    if (relay && !/^https:\/\//.test(relay)) return alert('The relay address should start with https://');
    setUpcRelay(relay);
    toast(relay ? 'Barcode lookup turned on' : 'Barcode lookup turned off');
  }

  return (
    <div className="page">
      <PageHeader title="More" />

      <section className="card">
        <h2>Your tackle</h2>
        <div className="stat-row">
          <div><strong>{totals.items}</strong><span>items</span></div>
          <div><strong>{totals.units}</strong><span>packs &amp; pieces</span></div>
          <div><strong>{money(totals.value).replace(/\.\d\d$/, '')}</strong><span>est. value</span></div>
        </div>
        <table className="stats">
          <tbody>
            {stats.map((s) => (
              <tr key={s.category}>
                <td>{categoryLabel(s.category)}</td>
                <td>{s.items} items</td>
                <td>{s.units} on hand</td>
                <td className={s.low ? 'warn-text' : 'muted'}>{s.low ? `${s.low} low` : ''}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>

      <section className="card">
        <h2>Backup</h2>
        <p className="muted small">
          Your tackle is stored only on this phone. Save a backup to Files (iCloud Drive) now and then so a lost
          or reset phone doesn't take it with it.
        </p>
        <p className={`small ${days == null || days >= 14 ? 'warn-text' : 'muted'}`}>
          {days == null ? 'Never backed up.' : days === 0 ? 'Last backup: today.' : `Last backup: ${days} day${days === 1 ? '' : 's'} ago.`}
        </p>
        <div className="row wrap">
          <button className="btn" onClick={backup} disabled={busy}>{busy ? 'Preparing…' : 'Back up now'}</button>
          <button className="btn secondary" onClick={() => exportCsv()}>Spreadsheet (CSV)</button>
          <label className="btn ghost">
            Restore…
            <input type="file" accept="application/json,.json" hidden onChange={(e) => restore(e.target.files?.[0])} />
          </label>
        </div>
        {usage != null && (
          <p className="muted small">
            Using {formatBytes(usage)} on this phone{persisted ? ' · protected from automatic cleanup' : ''}.
          </p>
        )}
      </section>

      <section className="card">
        <h2>Barcode lookup</h2>
        <p className="muted small">
          Fills in the name of packages you haven't added yet. It needs a free relay (see <code>worker/README.md</code>).
          Without it, scanning still finds everything you own.
        </p>
        <form className="row" onSubmit={saveRelay}>
          <input type="url" placeholder="https://upc-relay.you.workers.dev" value={relay} onChange={(e) => setRelay(e.target.value)}
            aria-label="Barcode lookup relay address" />
          <button className="btn secondary">Save</button>
        </form>
      </section>

      <section className="card">
        <h2>On your phone</h2>
        <ul className="tips">
          {!isStandalone() && (
            <li><strong>Install it:</strong> in Safari tap Share → <strong>Add to Home Screen</strong>. It then opens like an app,
              works without signal, and iPhone keeps its data safer.</li>
          )}
          <li>On the Scan tab, <strong>Add +1</strong> tallies packages as you shelve them and <strong>Take out −1</strong> pulls
            them from inventory as they go in the boat. Undo fixes a mis-scan.</li>
          <li>Tackle Warehouse import and the Shop buttons need internet. Everything else works offline.</li>
        </ul>
      </section>
    </div>
  );
}
