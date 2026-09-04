# html/images/map.jpg + Map tab calibration

`map.jpg` is the actual GTA V map, stitched from
[FlyBanditMods-iOS_LS_Map-Lite](https://github.com/TheFlyBandit/FlyBanditMods-iOS_LS_Map-Lite)'s
own `stream/minimap_ROW_COL.ytd` tiles. `shared/config.lua`'s `Config.Map`
maps GetEntityCoords world units onto pixel positions in this image
(`html/app.js`'s `worldToImagePixel`) -- if a location pin or the player
marker drifts from where it should sit on screen, the fix is almost always
`Config.Map`'s `worldMinX/MaxX/MinY/MaxY`, not the pixel math itself.

## Using a different map image

The bundled `map.jpg` was extracted from this server's own copy of LS Map
Lite with an in-house CodeWalker-based tool that isn't part of this public
package. If you run a different minimap texture replacement (or none at
all, and want the stock GTA V minimap art instead), swap `map.jpg` for your
own stitched image, any tool that can flatten a set of minimap tiles into
one image works, then run the calibration procedure below against it. The
Map tab reads whatever image is at this path; nothing else in the resource
assumes it came from LS Map Lite specifically.

## Why this isn't guessed

There is no authoritative published "GTA V minimap world bounds" constant
that applies to an arbitrary custom-stitched image like this one -- forum
posts citing e.g. `-4000..6000 / -4000..8000` describe the STANDARD
per-tile grid at a DIFFERENT tile size/count than `ls_map_lite`'s, so they
don't transfer directly (confirmed by testing: plugging those numbers in
here put Humane Labs and LSIA both in open ocean). The only reliable way to
calibrate a specific stitched image is to match real landmarks against their
measured pixel position in THAT image.

## Procedure

1. Pick 2 (or more) landmarks that are:
   - **Compact** -- a single building/facility, not a sprawling zone. A
     zone's `_tools/gtav_reference zone <name>` bounding-box CENTER is only
     a good proxy for where its map icon is actually drawn when the zone is
     small. Humane Labs and Maze Bank Arena worked well; Los Santos
     International Airport did NOT (huge, multi-lobed zone -- its bbox
     center landed ~400px from the actual airport icon in `map.jpg`, even
     though its Y coordinate still matched to ~1%).
   - **Far apart** in both X and Y, so the fit isn't dominated by rounding
     error over a short baseline.
   - Marked with a distinct, small, solid-colour icon in `map.jpg` (not just
     a text label -- text labels are offset from the actual point and don't
     measure precisely).
2. Get each landmark's real world coordinate: `_tools/gtav_reference zone
   <name>` and use the center of whichever returned bbox is the small,
   single-building one (print ALL of them if the zone is compound -- pick by
   inspecting which bbox is actually building-sized).
3. Measure each landmark's icon pixel position in `map.jpg` precisely
   (visual eyeballing on a scaled-down screenshot is NOT precise enough --
   drift of a few hundred pixels on a 6144x9216 image is invisible at a
   glance but is exactly the kind of error that put LSIA in the ocean last
   time). Do it with a small color-centroid script instead:

   ```python
   from PIL import Image
   import numpy as np
   im = np.array(Image.open('map.jpg').convert('RGB')).astype(int)

   def centroid(region, target_rgb, tol):
       x0, y0, x1, y1 = region
       sub = im[y0:y1, x0:x1]
       mask = np.abs(sub - np.array(target_rgb)).sum(axis=2) < tol
       ys, xs = np.where(mask)
       return (x0 + xs.mean(), y0 + ys.mean()), len(xs)
   ```

   Crop a region around roughly where you expect the landmark (a rough
   `worldToImagePixel` guess, or just eyeball a general area), sample the
   icon's own fill colour from a zoomed crop, then run `centroid` with that
   colour and a tolerance tight enough to exclude the background (start
   around 30-60; too loose picks up unrelated similarly-coloured terrain).
   Cross-check the result by drawing a marker at the returned point and
   re-cropping around it (`ImageDraw.ellipse`) to confirm it actually landed
   on the icon and not a mismatched blob.

4. Solve the affine mapping from the (world, pixel) pairs. `worldToImagePixel`
   is:
   ```
   fracX = (wx - worldMinX) / (worldMaxX - worldMinX)
   fracY = 1 - (wy - worldMinY) / (worldMaxY - worldMinY)
   pixelX = fracX * pixelWidth
   pixelY = fracY * pixelHeight
   ```
   i.e. `pixelX` is linear in `wx` and `pixelY` is linear in `wy`. With 2
   landmarks you get 2 equations per axis (exact fit); with 3+, do a
   least-squares line fit per axis instead and check the residuals per
   point -- a landmark whose residual is way out of line with the others
   (like LSIA's X above) has a bad ground-truth coordinate, not a bad
   formula. Drop it rather than letting it drag the fit.

   From `slope`/`intercept` per axis:
   ```
   worldMaxX - worldMinX = pixelWidth  / slope_x
   worldMinX             = -intercept_x / slope_x
   worldMaxY - worldMinY = -pixelHeight / slope_y
   worldMinY             = (intercept_y - pixelHeight) / slope_y   -- wrong sign trap: see below
   ```
   Easiest to just re-derive from the two `worldToImagePixel` equations
   directly for your two chosen points rather than trust a copied formula --
   the sign on the Y intercept term is easy to get backwards (verify by
   plugging the solved bounds back through `worldToImagePixel` for BOTH
   input points and confirming they reproduce the measured pixels, not just
   solving once and assuming it's right).

5. Update `Config.Map.worldMinX/MaxX/MinY/MaxY`, then verify: re-run step 3's
   measurement for a THIRD landmark you didn't fit against, predict its pixel
   with the new bounds, and confirm it's close. Anything within ~1% of
   `pixelWidth`/`pixelHeight` is as good as this method gets; a landmark
   that's still off by a large margin is a bad ground-truth pick (see step
   1's "compact" requirement), not necessarily a bad fit.

## Current numbers

`worldMinX = -4083.8, worldMaxX = 4674.4, worldMinY = -5019.5, worldMaxY = 8344.6`
-- WEIGHTED fit from Humane Labs, Maze Bank Arena (weight 5 each -- precise
single-icon matches), and Elysian Island's docks (weight 1 -- an eyeballed
cluster center, not a precise icon match, so deliberately down-weighted; see
`shared/config.lua`'s `Config.Map` comment for the exact measured points,
weights, and residuals). An unweighted fit through all three was tried
first and technically had a lower total error, but it did so by dragging
Maze Bank Arena's own residual out to ~127px to better fit the noisiest
point -- worse for the whole populated central-LS cluster near it than
leaving one far-south outlier a bit off. If you add a fourth landmark,
weight it by how precisely you can pin down BOTH its real coordinate and
its pixel position, not equally with the others by default.

## Other real bugs already fixed here, for whoever touches this next

- Transparency in the source map art (real alpha in the DXT5 minimap tiles)
  got flattened to black by the JPEG encoder during stitching (JPEG has no
  alpha channel) -- fixed by compositing onto a sky-blue background before
  flattening. See `_tools/map_extract`.
- The Locations panel used to be a hand-typed `Config.Locations` list (each
  entry grepped out of the resource that placed the matching real blip) --
  replaced by `client/blips.lua`'s `GK.ScanBlips()`, which reads every
  active native blip server-wide directly. See that file's header comment.
- A full downloaded-icon-per-blip-sprite pipeline, and separately a
  CSS `mask-image` tint on top of it, were each tried and torn back out --
  see `client/native_pages.lua`'s header comment for both. The Map tab now
  shows each blip's real icon (where `html/data/blip_sprites.json` has one)
  via a plain `<img>` at its own native colour, with a plain coloured dot
  (the blip's real HUD colour) as the fallback.
