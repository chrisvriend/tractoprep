#!/usr/bin/env python3
"""combine_rois.py (kit helper): left and right label volumes from mri_label2vol (values
1..N per hemisphere) -> one volume with left 1..N and right N+1..2N, plus a TSV lookup table.
Voxels claimed by both hemispheres (rare, at the midline) are set to 0 and counted."""
import argparse

import nibabel as nib
import numpy as np

ap = argparse.ArgumentParser()
for k in ["--lh", "--rh", "--areas", "--atlas", "--out", "--tsv"]:
    ap.add_argument(k, required=True)
a = ap.parse_args()
areas = [x.strip() for x in open(a.areas) if x.strip()]
n = len(areas)
lh_img = nib.load(a.lh)
lh = np.asarray(lh_img.dataobj).astype(np.int32)
rh = np.asarray(nib.load(a.rh).dataobj).astype(np.int32)
if lh.shape != rh.shape:
    raise SystemExit("hemisphere volumes differ in shape")
out = np.where(lh > 0, lh, 0) + np.where(rh > 0, rh + n, 0)
both = (lh > 0) & (rh > 0)
out[both] = 0
hdr = lh_img.header.copy()
hdr.set_data_dtype(np.int16)
nib.save(nib.Nifti1Image(out.astype(np.int16), lh_img.affine, hdr), a.out)
with open(a.tsv, "w") as f:
    f.write("index\tname\themisphere\tatlas\n")
    for i, name in enumerate(areas):
        f.write(f"{i + 1}\t{name}\tleft\t{a.atlas}\n")
    for i, name in enumerate(areas):
        f.write(f"{i + 1 + n}\t{name}\tright\t{a.atlas}\n")
counts = ", ".join(f"{h}.{name} {int((out == i + 1 + off).sum())}" for off, h in [(0, "lh"), (n, "rh")]
                   for i, name in enumerate(areas))
print(f"{a.atlas}: voxels {counts}; claimed by both hemispheres (set to 0): {int(both.sum())}")
