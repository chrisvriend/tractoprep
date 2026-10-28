# Visual proxies structural kit

For ENIGMA-OCD sites (run inside TractoPrep or on its own). Two scripts:

- `export_for_visual_proxies.sh`: **what a site runs and sends back.** Per subject it makes the
  visual cortex ROIs, thickness and area (`map_visual_rois.sh`) and copies the FreeSurfer files
  the central visual proxies pipelines need (Aim 1 thickness/area, Aim 2 retinotopy). One tar
  file per site.
- `map_visual_rois.sh`: the ROIs and the thickness/area table for one subject (also usable on
  its own, e.g. to get the ROI volumes for tractography).

Self-contained: needs only FreeSurfer (bash tools `mri_label2label`, `mri_label2vol`,
`mri_vol2vol`, `mris_label2annot`, `mris_anatomical_stats`) and a Python 3 with nibabel and
numpy (FreeSurfer 7's `fspython` has them). Tested with FreeSurfer 7.3.2 (official container);
other versions are expected to work but have not been tested. The FreeSurfer version used is
recorded in the output.

## Site export

```bash
source $FREESURFER_HOME/SetUpFreeSurfer.sh
bash export_for_visual_proxies.sh --subjects-dir /path/to/freesurfer --subjects subjects.txt \
     --site SITENAME --out /path/to/export
```

What is sent per subject:
- **Aim 1** (thickness, surface area): the table `visual_rois/<subject>_visual_rois_stats.csv`
  for all atlases and regions, made at the site, plus the ROI labels and volumes.
- **Aim 2** (retinotopy, run centrally): `surf/?h.white`, `surf/?h.pial`, `surf/?h.sphere.reg`,
  `stats/aseg.stats`, `samseg/sbtiv.stats` (if present) and `scripts/build-stamp.txt` from the
  FreeSurfer folder. No volume images. (deepRetinotopy gives identical results from these
  surfaces as from the full `surf/`.)
- A manifest with checksums. About 35 MB per subject.

Send `<site>_visual_proxies_export.tar`.

## Atlases

| Folder | Areas | Overlap | Reference |
|---|---|---|---|
| `atlases/vcatlas/` | hOc1 (V1), hOc2 (V2), hOc3v, hOc4v, FG1-FG4 (cytoarchitectonic) | as published | Rosenke et al. (2018) |
| `atlases/wang/` | V1, V2, V3 (retinotopic, maximum probability) | as published | Wang et al. (2015) |
| `atlases/mt/`, `atlases/mt_full/` | MT, thresholded / not thresholded | as published | Malikovic et al. (2007); Fischl et al. (2008) |
| `atlases/julich_visual/` | all visual Julich areas (hOc1, hOc2, hOc3v/d, hOc4v/d/la/lp, hOc5, ..., FG1-FG4; list in `areas.txt`) | unmasked; overlaps the other atlases | Amunts et al. (2020), Julich-Brain 3.1 |
| `atlases/visual/` | vcAtlas 8 + MT (thresholded) + Julich 4 | none: vcAtlas > MT > Julich | as above |
| `atlases/visual_mtfull/` | vcAtlas 8 + MT (full) + Julich 4 | none: vcAtlas > MT_full > Julich | as above |

Different atlases overlap (e.g. hOc1 and Wang V1 are two definitions of V1), so every atlas
gets its own volume. Which MT version is primary is decided later; both are produced.
Julich-Brain is CC BY-NC-SA (`LICENCE_JulichBrain.pdf`): attribution, non-commercial.

Both are stored on fsaverage and mapped to each subject through the subject's own
`?h.sphere.reg`, the same way recon-all maps its atlas labels. The kit brings its own
fsaverage surfaces, so results do not depend on the site's FreeSurfer copy. Details and
licence notes: `PROVENANCE.txt`.

## Run

```bash
source $FREESURFER_HOME/SetUpFreeSurfer.sh          # tested with 7.3.2
bash map_visual_rois.sh --subjects-dir /path/to/freesurfer --subject sub-XXXX --out /path/to/output
```

The subject folder needs a complete recon-all (`surf/?h.{sphere.reg,white,pial,thickness}`,
`mri/orig.mgz`, `mri/wm.mgz`, `mri/transforms/talairach.xfm`; `mri/rawavg.mgz` for the
T1w-space output). It is only read.

## Output (`<out>/<subject>/`)

| File | Content |
|---|---|
| `labels/{lh,rh}.<atlas>_<area>.label` | surface labels on the subject's native mesh |
| `<subject>_space-orig_atlas-<atlas>_dseg.nii.gz` | volume, FreeSurfer conformed space (same grid as `aparc+aseg.mgz`) |
| `<subject>_space-T1w_atlas-<atlas>_dseg.nii.gz` | the same on the raw T1w grid (`rawavg.mgz`) |
| `<subject>_atlas-<atlas>_dseg.tsv` | index, area name, hemisphere (left 1..N, right N+1..2N) |
| `<subject>_visual_rois_stats.csv` | per atlas, hemisphere and area: mean thickness, surface area (white surface), grey matter volume, vertices (`mris_anatomical_stats` per annotation; `--no-stats` to skip) |
| `provenance.json` | kit version, FreeSurfer build, date |

The volumes fill each surface label into the cortical ribbon (sampled from the white to the
pial surface in steps of 10% of the thickness); a voxel goes to the area that fills it most.
The two atlases overlap (e.g. hOc1 and Wang V1 are two definitions of V1), so each atlas has
its own volume. Registration to diffusion or functional space is left to the calling pipeline.

The kit checks its own files against `checksums.sha256` before it runs. Thickness and area are
computed as in Aim 1: labels are merged into annotations (`mris_label2annot`, with
`--maxstatwinner` and the vcAtlas probabilities for vcAtlas, so a vertex counts in one vcAtlas
area only) and measured with `mris_anatomical_stats -a`. For `visual` and `visual_mtfull`,
`stat_groups.txt` gives the annotations Aim 1 uses (vcAtlas, MT, masked Julich), so the table
equals Aim 1's.
