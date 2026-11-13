import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { HashRouter } from 'react-router-dom';
import App from './App';
import { requestPersistence } from './db';
import './styles.css';

// Hash URLs (#/items/3) let the app run from any static host or subfolder with no server rules.
createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <HashRouter>
      <App />
    </HashRouter>
  </StrictMode>,
);

requestPersistence();

if ('serviceWorker' in navigator && import.meta.env.PROD) {
  navigator.serviceWorker.register('./sw.js').catch(() => {});
  // Fetch the scanner up front so it's cached for scanning with no signal.
  const warm = () => import('./components/Scanner');
  'requestIdleCallback' in window ? requestIdleCallback(warm) : setTimeout(warm, 2000);
}
