import { NavLink, Route, Routes } from 'react-router-dom';
import Inventory from './pages/Inventory';
import ItemDetail from './pages/ItemDetail';
import ItemEdit from './pages/ItemEdit';
import Scan from './pages/Scan';
import Reorder from './pages/Reorder';
import More from './pages/More';
import { Icon } from './components/ui';

export default function App() {
  return (
    <div className="app">
      <main className="content">
        <Routes>
          <Route path="/" element={<Inventory />} />
          <Route path="/scan" element={<Scan />} />
          <Route path="/reorder" element={<Reorder />} />
          <Route path="/more" element={<More />} />
          <Route path="/add" element={<ItemEdit />} />
          <Route path="/items/:id" element={<ItemDetail />} />
          <Route path="/items/:id/edit" element={<ItemEdit />} />
        </Routes>
      </main>
      <nav className="tabbar">
        <NavLink to="/" end><Icon name="box" />Tackle</NavLink>
        <NavLink to="/scan"><Icon name="scan" />Scan</NavLink>
        <NavLink to="/reorder"><Icon name="cart" />Reorder</NavLink>
        <NavLink to="/more"><Icon name="more" />More</NavLink>
      </nav>
    </div>
  );
}
