# Shenzhen map.svg — status and export steps

## Status (2026-11-19)

`stations.json` (351 stations) and `routes.json` (17 lines, 433 line entries,
416 edges) are DONE and fully verified — see `build_sz.py`, which regenerates
both from `network.json` + `rmp-gallery-shenzhen.json` and asserts every check
(match 351/351, adjacency walk 416/416, no unopened stations).

`map.svg` is NOT done: there is no direct SVG download for it (see below).
It needs one browser step in the RMP app — a subagent cannot do that part.

## Why no direct download exists

- RMP Gallery HAS a Shenzhen map: gallery entry `Shenzhen`
  (`railmapgen/rmp-gallery`, `public/resources/metadata/shenzhen.json`,
  last update 2026-06-28 "Northern extension of Line 13 has been opened").
- The gallery serves the map only as an **RMP project JSON**
  (`public/resources/real_world/shenzhen.json`) — saved locally here as
  `rmp-gallery-shenzhen.json` (791 nodes, 634 edges, version 76) — and as a
  PNG thumbnail (`resources/thumbnails/shenzhen@300.png`). A PNG is a raster
  and must NOT be substituted for the vector map.
- The SVG is produced by RMP's in-browser export (Download → SVG), which
  clones the live DOM canvas (`makeRenderReadySVGElement` in
  `railmapgen/rmp`, `src/util/download.ts`). There is no headless/server
  endpoint that returns the exported SVG.

## Exact export steps (browser agent)

1. Open the gallery share link, which loads Shenzhen in RMP:
   `https://railmapgen.org/?app=rmp&searchParams=shenzhen`
   (or open `https://railmapgen.org/?app=rmp-gallery`, open Shenzhen, "Open in RMP").
2. In RMP: header **Download** → format **SVG**, version **2** → save the file as
   `web/shenzhen/map.svg`.
3. Post-process exactly as the other 8 cities' maps:
   - Rename the SVG root id `canvas` → `svg8`
     (`build_offline.py` asserts `id="svg8"`).
   - Delete the `<g id="rmp_info">…</g>` element the export appends
     (text `https://railmapgen.org/?app=rmp`, x=60, y=25, font-size 32).
     The other cities' files already have this stripped.
   - Verify the file contains no `</script`.
4. Verify: `stations.json` x,y are the RMP node coordinates verbatim (same
   convention as the other 8 cities — proven for Shanghai), so they match the
   exported SVG by construction; re-run `python3 build_sz.py` — it must still
   print `ALL CHECKS PASS`.

## Notes for the exporter (do not "fix" these)

- The RMP artwork draws stations/lines that are correctly EXCLUDED from the
  app data: unopened Line 13 stations 歌剧院 / 潮汐公园 / 西丽高铁站 (the last
  sits between 高新北 and 石鼓), the Longhua tram, 坪山云巴1号线, the Hong Kong
  East Rail segment (罗湖/落马洲—上水), a legend and a not-in-service bar.
  They belong to the artwork; leave them in the SVG, keep them out of the data.
- The Dec 2025 extensions ARE in this RMP map (verified by the 416/416
  adjacency walk in `build_sz.py`): Line 5 to 大剧院, Line 8 to 溪涌,
  Line 11 to 红岭南, Line 13 to 李松蓢, Line 16 to 园山西坑, 6B to 深理工.
- Lines 2/8 through-run: RMP colours all 2/8 edges `sz2` (no `sz8`); 莲塘 is
  the single shared node. `routes.json` keeps them as two lines, as specified.
- RMP's Line 1 colour is `#00B140`; `routes.json` uses `network.json`'s
  `00AB39` per the task spec — do not "correct" it to the RMP colour.
- Out-of-station pairs have TWO dots in the artwork but ONE `stations.json`
  entry at the midpoint: 湖贝 (-100.25, 135), 红岭南 (-207.5, 225),
  福田口岸 (-415, 330). Do not move them to either single dot.
