import { useEffect, useState } from 'react';
import { api, categoryLabel, type CategoryStats } from '../api';
import { money, PageHeader, toast } from '../components/ui';

export default function More() {
  const [stats, setStats] = useState<CategoryStats[]>([]);
  useEffect(() => { api.stats().then(setStats).catch(() => {}); }, []);

  const totals = stats.reduce((t, s) => ({ items: t.items + s.items, units: t.units + (s.units || 0), value: t.value + (s.value || 0) }),
    { items: 0, units: 0, value: 0 });

  async function importFile(file: File | undefined) {
    if (!file) return;
    try {
      const items = JSON.parse(await file.text());
      const replace = confirm('Replace everything currently in the app with this backup?\n\nOK = replace, Cancel = add to what you have');
      const { imported } = await api.importItems(items, replace);
      toast(`Imported ${imported} items`);
      api.stats().then(setStats);
    } catch (e) {
      alert(`Import failed: ${(e as Error).message}`);
    }
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
        <p className="muted small">Your data lives on the computer running TackleTracker. Download a copy now and then.</p>
        <div className="row wrap">
          <a className="btn secondary" href="/api/export.json" download>Download backup</a>
          <a className="btn secondary" href="/api/export.csv" download>Spreadsheet (CSV)</a>
          <label className="btn ghost">
            Restore backup…
            <input type="file" accept="application/json,.json" hidden onChange={(e) => importFile(e.target.files?.[0])} />
          </label>
        </div>
      </section>

      <section className="card">
        <h2>On your phone</h2>
        <ul className="tips">
          <li>Open the <strong>https://</strong> address shown when the server starts. Your phone will warn that the certificate isn't trusted — that's expected for a home server; continue to the site.</li>
          <li>Safari: tap Share → <strong>Add to Home Screen</strong> so it opens like an app.</li>
          <li>Use <strong>Count mode</strong> on the Scan tab to tally packages quickly: each scan adds one.</li>
        </ul>
      </section>
    </div>
  );
}
