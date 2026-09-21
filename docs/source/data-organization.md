# Imaging Data Organization Requirements

- A **BIDS-organized** dataset containing at minimum `anat/` (T1w) and
  `dwi/` data with valid JSON sidecars. The pipeline reads
  `PhaseEncodingDirection` and `TotalReadoutTime` directly from the
  diffusion MRI JSON file — make sure these fields are populated.
- Optionally, field maps with `PhaseEncodingDirection`,
  `TotalReadoutTime`, and a correct `IntendedFor` entry (pointing to the
  diffusion MRI image(s)). If no field maps are present, the pipeline
  automatically falls back to **Synb0-DISCO** (synthetic b0) for
  susceptibility distortion correction — this needs the anatomical T1w
  to be available.
- (Optional) A **FreeSurfer output directory** (`freesurferdir`) if you
  already have FreeSurfer output available for these participants.


```{note}
while existing FreeSurfer output for a subject is optional. the freesurferdir should be indicated 
in the {doc}`spec.json` file. 

```

The files can be organized with or without a session label, as long as
the organization is BIDS-compliant. Either of these is correct:


```text
bidsdir/
└── sub-01/
    └── [ses-Tx/]                              # optional session directory
        ├── anat/
        │   ├── sub-01[_<ses-Tx>]_T1w.nii[.gz] # T1-weighted whole-brain anatomical image (with skull)
        │   └── sub-01[_<ses-Tx>]_T1w.json     # JSON sidecar with sequence information
        │
        ├── dwi/
        │   ├── sub-01[_<ses-Tx>][_<dir-PE1/2>]_dwi.nii[.gz] # 
        │   ├── sub-01[_<ses-Tx>][_<dir-PE1/2>]_dwi.bvec  # b-vector file
        │   ├── sub-01[_<ses-Tx>][_<dir-PE1/2>]_dwi.bval  # b-value file
        │   └── sub-01[_<ses-Tx>][_<dir-PE1/2>]_dwi.json  # Must contain at least
        │                                                   # TotalReadoutTime and PhaseEncodingDirection
        │
        └── fmap/
            ├── sub-01[_<ses-Tx>][_<dir-PE1>]_epi.nii[.gz] # (Optional) Same-phase-encoding b0 image(s)
            └── sub-01[_<ses-Tx>][_<dir-PE1>]_epi.json     # (Optional) Must contain at least
                                                            # TotalReadoutTime, PhaseEncodingDirection and IntendedFor (pointing to dwi scan)
            ├── sub-01[_<ses-Tx>][_<dir-PE2>]_epi.nii[.gz] # Reverse-phase-encoding b0 image(s)
            └── sub-01[_<ses-Tx>][_<dir-PE2>]_epi.json     # Must contain at least
                                                            # TotalReadoutTime, PhaseEncodingDirection and IntendedFor (pointing to dwi scan)

```

```{note}
dir-PE (PhaseEncoding direction) should not be specified in the filename in case the diffusion MRI was acquired in only one PE direction. In case of multiple runs (with for example directions AP and PA) save as sub-01[_<ses-Tx>]_dir-AP_dwi.nii[.gz] and sub-01[_<ses-Tx>]_dir-PA_dwi.nii[.gz] with accompanying bvals, bvecs and json files.
```

If you use a session label, indicate it in the `spec.json` file — see
{doc}`spec-json`.
