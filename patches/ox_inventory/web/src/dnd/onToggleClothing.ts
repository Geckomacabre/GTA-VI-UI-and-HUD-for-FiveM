import { fetchNui } from '../utils/fetchNui';

/** The three clothing wheel cells that are actually wired up — see ItemWheel.tsx. */
export type ClothingRole = 'mask' | 'hat' | 'eyewear';

/**
 * Mirrors dpclothing's live ped state (GetClothingWheelState export), not
 * anything ox_inventory itself tracks — a clothing item is a worn ped prop/
 * component there, never an inventory item, so there is no slot/metadata to
 * read this from on this side.
 */
export type ClothingState = Partial<Record<ClothingRole, boolean>>;

export const fetchClothingState = () => fetchNui<ClothingState>('getClothingState');

/** Clicking a mask/hat/eyewear wheel cell toggles it via dpclothing and re-reads the new state. */
export const onToggleClothing = (role: ClothingRole) => fetchNui<ClothingState>('toggleClothing', role);
