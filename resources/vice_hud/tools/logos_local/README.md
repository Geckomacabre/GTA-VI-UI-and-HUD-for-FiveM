# Hand-supplied manufacturer marks

Drop `<KEY>.png` in here and `tools/fetch_logos.py` uses it INSTEAD of anything
it can find on the wiki, for that manufacturer only. `<KEY>` is the normalised
name, the same key `html/makes.js` uses and the same name the shipped file in
`html/logos/` gets.

The file still goes through the whole normalisation in `fetch_logos.py`
(greyscale ink, alpha recovered where the source is on a flat card, evened out
in weight, trimmed and resized), so a local mark lands in the same visual set as
the rest of the roster. Put in the best source you have and let the script do
the flattening; do not pre-flatten it by hand.

PNG only. A `.source.svg` alongside is kept purely as provenance: nothing in the
build reads it, because rasterising SVG needs a renderer this project does not
depend on. To refresh one from vector, rasterise it yourself at roughly 512px on
the long edge and overwrite the PNG.

## What is in here

- `WESTERNMOTORCYCLECOMPANY.png`: the bar-and-shield with the lettering taken
  out. Every mark the wiki hosts for this marque has WESTERN MOTORCYCLE COMPANY
  set across the shield, so it shipped no badge at all until this arrived.
  Supplied by the server owner. Note the source already carries an alpha
  channel with an opaque WHITE fill inside the shield, so it comes through as a
  filled mark with the detail knocked through rather than as line art, which
  is what reads on a dark plate.
- `TRUFFADE.png`: the bare TT monogram. Every Truffade asset on the wiki either
  spells TRUFFADE across the badge or is a 59x38 icon, and the panel already
  prints the name directly above the mark. Rasterised from
  `TRUFFADE.source.svg`, supplied by the server owner.
