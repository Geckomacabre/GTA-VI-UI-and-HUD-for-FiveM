import InventoryGrid from './InventoryGrid';
import { useAppSelector } from '../../store';
import { selectRightInventory } from '../../store/inventory';

const RightInventory: React.FC = () => {
  const rightInventory = useAppSelector(selectRightInventory);

  // Only render when a secondary inventory is genuinely open (a stash, shop,
  // trunk, another player...). The store's initial state uses an empty `id`, so
  // that is the reliable signal — checking for items instead would wrongly hide
  // a stash that happens to be empty.
  if (!rightInventory.id) return null;

  return <InventoryGrid inventory={rightInventory} />;
};

export default RightInventory;
