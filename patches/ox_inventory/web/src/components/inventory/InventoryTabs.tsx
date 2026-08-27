import React from 'react';
import { Locale } from '../../store/locale';

// Re-exported for convenience; the type itself lives with the store that owns
// the value, so the two can never drift apart.
export type { InventoryTab } from '../../store/activeTab';
import type { InventoryTab } from '../../store/activeTab';

interface Props {
  active: InventoryTab;
  onChange: (tab: InventoryTab) => void;
}

// Purely a visual/UI-state toggle — the actual weapons/items split is done by
// LeftInventory.tsx, which partitions real inventory slots using the item's
// static definition. This component only renders the segmented pill switcher
// (two pills flush against each other plus the thin white end bar from the
// reference art) and reports which side is selected.
const InventoryTabs: React.FC<Props> = ({ active, onChange }) => (
  <div className="gta6-tabs">
    <button
      type="button"
      className={`gta6-tab gta6-tab-weapons ${active === 'weapons' ? 'gta6-tab-active' : ''}`}
      onClick={() => onChange('weapons')}
    >
      {Locale.ui_weapons || 'WEAPONS'}
    </button>
    <button
      type="button"
      className={`gta6-tab gta6-tab-items ${active === 'items' ? 'gta6-tab-active' : ''}`}
      onClick={() => onChange('items')}
    >
      {Locale.ui_items || 'ITEMS'}
    </button>
    <span className="gta6-tab-bar" />
  </div>
);

export default InventoryTabs;
