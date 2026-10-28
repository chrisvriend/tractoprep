#!/usr/bin/env bash
# map_visual_rois.sh: visual cortex ROIs for one FreeSurfer subject (portable kit).
#
# Maps the atlases in this kit from fsaverage to the subject's own surface (via the subject's
# ?h.sphere.reg, the same route recon-all uses for its own atlas labels), fills them into the
# cortical ribbon (white to pial surface) and writes everything into the subject's own
# FreeSurfer directory, <subjects-dir>/<subject>/visocd (created if it does not exist):
#   visocd/labels/{lh,rh}.<atlas>_<area>.label     surface labels, native mesh
#   visocd/<subject>_space-orig_atlas-<atlas>_dseg.nii.gz    volume in FreeSurfer's
#                                       conformed space (same grid as aparc+aseg.mgz)
#   visocd/<subject>_space-T1w_atlas-<atlas>_dseg.nii.gz     same, on the raw T1w
#                                       grid (rawavg.mgz), if present
#   visocd/<subject>_atlas-<atlas>_dseg.tsv         index, name, hemisphere
#   visocd/<subject>_visual_rois_stats.csv          per atlas, hemisphere and area:
#                                       mean thickness, surface area, grey volume, vertices.
#                                       As Aim 1: the labels of an atlas are merged into one
#                                       annotation (mris_label2annot --maxstatwinner, so a vertex
#                                       counts in one area only), then mris_anatomical_stats -a.
#                                       Skip with --no-stats.
#   visocd/provenance.json
# Atlases: vcAtlas (Rosenke et al. 2018: hOc1, hOc2, hOc3v, hOc4v, FG1-FG4) and Wang et al.
# (2015) V1-V3. Within an atlas areas do not overlap; between atlases they do (separate
# volumes). Left hemisphere indices 1..N, right N+1..2N.
#
# Scratch files go to ${workdir}/${subj}/visocd_tmp (removed on exit). ${workdir} is taken from
# the environment variable "workdir" (set by the container) or from --workdir.
#
# Reads the subject's recon-all output; writes only to <subject>/visocd and the scratch dir.
#
# Usage: map_visual_rois.sh --subjects-dir DIR --subject ID [--workdir DIR] [--kit DIR] [--no-stats]
#   --subject ID   subject folder name inside --subjects-dir (e.g. sub-01); also $subj if unset
#   --workdir DIR  base for the scratch dir (default: $workdir)
#   --kit DIR      this kit's folder (default: the folder of this script)

set -euo pipefail
die() { echo "map_visual_rois.sh: ERROR: $*" >&2; exit 1; }
log() { echo "[$(date '+%F %T')] $*"; }

KIT="/tracto/visocd"
ATLAS_ROOT="/tracto/atlases/visocd"
SD=""; SUB="${subj:-}"; WORKDIR="${workdir:-}"; STATS=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --subjects-dir) SD="${2:-}"; shift 2 ;;
    --subject) SUB="${2:-}"; shift 2 ;;
    --workdir) WORKDIR="${2:-}"; shift 2 ;;
    --kit) KIT="${2:-}"; shift 2 ;;
    --no-stats) STATS=0; shift ;;
    *) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
  esac
done
[[ -n "$SD" && -n "$SUB" ]] || die "--subjects-dir and --subject are required"
[[ -n "$WORKDIR" ]] || die "workdir not set (set \$workdir in the container or pass --workdir)"
S="$SD/$SUB"
for f in surf/lh.sphere.reg surf/rh.sphere.reg surf/lh.white surf/rh.white surf/lh.pial surf/rh.pial mri/orig.mgz; do
  [[ -s "$S/$f" ]] || die "missing $S/$f (complete recon-all output needed)"
done
if (( STATS )); then
  for f in mri/wm.mgz mri/transforms/talairach.xfm surf/lh.thickness surf/rh.thickness; do
    [[ -s "$S/$f" ]] || die "missing $S/$f (needed for the thickness and area table; or use --no-stats)"
  done
  for t in mris_anatomical_stats mris_label2annot; do command -v "$t" >/dev/null || die "$t not on PATH"; done
fi
for t in mri_label2label mri_label2vol mri_vol2vol; do command -v "$t" >/dev/null || die "$t not on PATH (source FreeSurfer)"; done
PY=""
for p in fspython python3; do
  if command -v "$p" >/dev/null && "$p" -c "import nibabel, numpy" 2>/dev/null; then PY="$p"; break; fi
done
[[ -n "$PY" ]] || die "no Python with nibabel and numpy (fspython or python3)"
( cd "$KIT" && sha256sum -c --quiet checksums.sha256 ) || die "kit files do not match checksums.sha256"

# output: inside the subject's FreeSurfer directory
O="$S/visocd"
mkdir -p "$O/labels"

# scratch: ${workdir}/${subj}/visocd_tmp (no mktemp); start clean, remove on exit
TMP="${WORKDIR}/${SUB}/visocd_tmp"
rm -rf -- "$TMP"
mkdir -p "$TMP"
trap 'rm -rf -- "$TMP"' EXIT
# private SUBJECTS_DIR: the subject (link) and the kit's own fsaverage
mkdir -p "$TMP/sd"
ln -s "$(cd "$S" && pwd)" "$TMP/sd/$SUB"
ln -s "$KIT/fsaverage" "$TMP/sd/fsaverage"
export SUBJECTS_DIR="$TMP/sd"
CSV="$O/${SUB}_visual_rois_stats.csv"
if (( STATS )); then echo "subject,atlas,hemi,region,thickness_mm,area_mm2,grayvol_mm3,n_vertices" > "$CSV"; fi
log "subject $SUB, kit $(cat "$KIT/VERSION"), FreeSurfer $(cat "$FREESURFER_HOME/build-stamp.txt" 2>/dev/null || echo unknown)"
log "output: $O, scratch: $TMP"

# identical fsaverage labels (e.g. vcAtlas areas reused in the visual sets) are mapped once
declare -A MAPPED=()


for atlas_dir in "$ATLAS_ROOT"/*/; do
  atlas="$(basename "$atlas_dir")"
  mapfile -t AREAS < "$atlas_dir/areas.txt"
  for h in lh rh; do
    labs=()
    for a in "${AREAS[@]}"; do
      key="$h:$(sha256sum < "$atlas_dir/$h.$a.label" | cut -d' ' -f1)"
      if [[ -n "${MAPPED[$key]:-}" ]]; then
        cp "${MAPPED[$key]}" "$O/labels/$h.${atlas}_$a.label"
      else
        mri_label2label --srcsubject fsaverage --srclabel "$atlas_dir/$h.$a.label" \
          --trgsubject "$SUB" --trglabel "$O/labels/$h.${atlas}_$a.label" \
          --hemi "$h" --regmethod surface > "$TMP/l2l.log" 2>&1 || { cat "$TMP/l2l.log" >&2; die "mri_label2label $h $atlas $a"; }
        MAPPED[$key]="$O/labels/$h.${atlas}_$a.label"
      fi
      labs+=(--label "$O/labels/$h.${atlas}_$a.label")
    done
    if (( STATS )); then
      # one annotation per group of areas, then one stats call per annotation (as Aim 1).
      # stat_groups.txt (visual sets): "<group> <maxstatwinner 0|1> <areas...>"; else one group
      if [[ -f "$atlas_dir/stat_groups.txt" ]]; then mapfile -t SGROUPS < "$atlas_dir/stat_groups.txt"
      else SGROUPS=("$atlas 1 ${AREAS[*]}"); fi
      declare -A ROW=()
      for g in "${SGROUPS[@]}"; do
        read -r gname gmax gareas <<< "$g"
        read -r -a GA <<< "$gareas"
        { echo "0  unknown  25 5 25 0"
          i=0; for a in "${GA[@]}"; do i=$((i + 1)); echo "$i  ${atlas}_$a  $(( (i * 67) % 256 )) $(( (i * 131) % 256 )) $(( (i * 197) % 256 )) 0"; done
        } > "$TMP/ctab.txt"
        annl=(); for a in "${GA[@]}"; do annl+=(--l "$O/labels/$h.${atlas}_$a.label"); done
        winner=(); [[ "$gmax" == 1 ]] && winner=(--maxstatwinner)
        mris_label2annot --s "$SUB" --hemi "$h" --ctab "$TMP/ctab.txt" ${winner[@]+"${winner[@]}"} \
          --annot-path "$TMP/$h.$atlas.$gname.annot" "${annl[@]}" > "$TMP/l2a.log" 2>&1 \
          || { cat "$TMP/l2a.log" >&2; die "mris_label2annot $h $atlas $gname"; }
        mris_anatomical_stats -a "$TMP/$h.$atlas.$gname.annot" -f "$TMP/stats.txt" "$SUB" "$h" > "$TMP/st.log" 2>&1 \
          || { cat "$TMP/st.log" >&2; die "mris_anatomical_stats $h $atlas $gname"; }
        # columns: StructName NumVert SurfArea GrayVol ThickAvg ...
        for a in "${GA[@]}"; do
          [[ -z "${ROW[$a]:-}" ]] || die "$atlas: area $a in two stat groups"
          ROW[$a]=$(awk -v s="$SUB" -v at="$atlas" -v h="$h" -v r="$a" -v n="${atlas}_$a" \
            '!/^#/ && $1 == n {print s","at","h","r","$5","$3","$4","$2}' "$TMP/stats.txt")
          [[ -n "${ROW[$a]}" ]] || ROW[$a]="$SUB,$atlas,$h,$a,,0,0,0"   # area lost all vertices to others
        done
      done
      for a in "${AREAS[@]}"; do
        [[ -n "${ROW[$a]:-}" ]] || die "$atlas: area $a in no stat group"
        echo "${ROW[$a]}" >> "$CSV"
      done
      unset ROW
    fi
    # label i of this hemisphere -> value i; a voxel goes to the label that fills it most
    mri_label2vol "${labs[@]}" --temp "$S/mri/orig.mgz" --identity --subject "$SUB" --hemi "$h" \
      --proj frac 0 1 0.1 --o "$TMP/${atlas}_$h.nii.gz" > "$TMP/l2v.log" 2>&1 \
      || { cat "$TMP/l2v.log" >&2; die "mri_label2vol $h $atlas"; }
  done
  "$PY" "$KIT/combine_rois.py" --lh "$TMP/${atlas}_lh.nii.gz" --rh "$TMP/${atlas}_rh.nii.gz" \
    --areas "$atlas_dir/areas.txt" --atlas "$atlas" \
    --out "$O/${SUB}_space-orig_atlas-${atlas}_dseg.nii.gz" --tsv "$O/${SUB}_atlas-${atlas}_dseg.tsv"
  if [[ -s "$S/mri/rawavg.mgz" ]]; then
    mri_vol2vol --mov "$O/${SUB}_space-orig_atlas-${atlas}_dseg.nii.gz" --targ "$S/mri/rawavg.mgz" \
      --regheader --nearest --o "$O/${SUB}_space-T1w_atlas-${atlas}_dseg.nii.gz" > "$TMP/v2v.log" 2>&1 \
      || { cat "$TMP/v2v.log" >&2; die "mri_vol2vol $atlas"; }
  fi
  log "$atlas: ${#AREAS[@]} areas per hemisphere (${#MAPPED[@]} unique labels mapped so far)"
done

cat > "$O/provenance.json" <<JSON
{"subject": "$SUB", "kit_version": "$(cat "$KIT/VERSION")",
 "freesurfer": "$(cat "$FREESURFER_HOME/build-stamp.txt" 2>/dev/null || echo unknown)",
 "mapping": "mri_label2label --regmethod surface (fsaverage -> subject), mri_label2vol --proj frac 0 1 0.1",
 "created": "$(date '+%F %T')", "host": "$(hostname)"}
JSON
if (( STATS )); then log "stats: $CSV ($(( $(wc -l < "$CSV") - 1 )) rows)"; fi
log "done: $O"