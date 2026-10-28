#!/usr/bin/env bash
# export_for_visual_proxies.sh: one site's structural package for the visual proxies project.
#
# For every subject in the list:
#   Aim 1 (thickness, surface area): map_visual_rois.sh makes the ROIs and the table for all
#          atlases and regions here; only the table and ROIs are sent
#   Aim 2 (retinotopy, run centrally with deepRetinotopy): the files that pipeline reads are
#          copied: surf/?h.{white,pial,sphere.reg} (symlinks resolved), stats/aseg.stats (eTIV),
#          samseg/sbtiv.stats (if present), scripts/build-stamp.txt (FreeSurfer version).
#          No volume images. deepRetinotopy on only these surf/ files gave results identical to
#          the full surf/ (test_deepret_minimal_surf.sh, 2026-10-15: 44 GIfTIs, 3 tables).
#   Aim 3 (connectopic mapping): not part of this export (later, with the HALFpipe rollout)
# Writes <out>/<site>/<subject>/{freesurfer,visual_rois}/, a manifest per subject (file,
# size, sha256), a site summary, and <out>/<site>_visual_proxies_export.tar.
#
# Reads the subjects directory only; writes only to --out.
#
# Needs: FreeSurfer (as map_visual_rois.sh), tar, sha256sum.
#
# Usage: export_for_visual_proxies.sh --subjects-dir DIR --subjects LIST --site NAME --out DIR
#   LIST   text file, one FreeSurfer subject folder name per line

set -euo pipefail
die() { echo "export_for_visual_proxies.sh: ERROR: $*" >&2; exit 1; }
log() { echo "[$(date '+%F %T')] $*"; }
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SD=""; LIST=""; SITE=""; OUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --subjects-dir) SD="${2:-}"; shift 2 ;;
    --subjects) LIST="${2:-}"; shift 2 ;;
    --site) SITE="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    *) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
  esac
done
[[ -n "$SD" && -n "$LIST" && -n "$SITE" && -n "$OUT" ]] || die "--subjects-dir, --subjects, --site and --out are required"
[[ "$SITE" =~ ^[A-Za-z0-9_-]+$ ]] || die "--site: letters, digits, _ and - only"
[[ -s "$LIST" ]] || die "subject list $LIST is empty or missing"
SITE_OUT="$OUT/$SITE"
mkdir -p "$SITE_OUT"

# files the central deepRetinotopy pipeline (Aim 2) reads
SURF=(surf/lh.white surf/rh.white surf/lh.pial surf/rh.pial surf/lh.sphere.reg surf/rh.sphere.reg)
FILES=("${SURF[@]}" stats/aseg.stats samseg/sbtiv.stats scripts/build-stamp.txt)
REQUIRED=("${SURF[@]}" stats/aseg.stats scripts/build-stamp.txt)

SUMMARY="$SITE_OUT/summary.tsv"
printf 'subject\tstatus\tdetail\n' > "$SUMMARY"
n_ok=0; n_fail=0
while IFS= read -r SUB || [[ -n "$SUB" ]]; do
  SUB="${SUB//[$'\r\t ']/}"
  [[ -n "$SUB" ]] || continue
  S="$SD/$SUB"; D="$SITE_OUT/$SUB"
  missing=()
  for f in "${REQUIRED[@]}"; do [[ -s "$S/$f" ]] || missing+=("$f"); done
  if (( ${#missing[@]} )); then
    log "FAIL $SUB: missing ${missing[*]}"; printf '%s\tfail\tmissing %s\n' "$SUB" "${missing[*]}" >> "$SUMMARY"
    n_fail=$((n_fail + 1)); continue
  fi
  log "$SUB: ROIs, thickness and area"
  mkdir -p "$D"
  if ! bash "$KIT/map_visual_rois.sh" --subjects-dir "$SD" --subject "$SUB" --out "$D/visual_rois_tmp" > "$D/map_visual_rois.log" 2>&1; then
    log "FAIL $SUB: map_visual_rois.sh (see $D/map_visual_rois.log)"
    printf '%s\tfail\tmap_visual_rois.sh\n' "$SUB" >> "$SUMMARY"; n_fail=$((n_fail + 1)); continue
  fi
  rm -rf -- "$D/visual_rois"; mv "$D/visual_rois_tmp/$SUB" "$D/visual_rois"; rmdir "$D/visual_rois_tmp"
  log "$SUB: copying the FreeSurfer files for Aim 2"
  for f in "${FILES[@]}"; do
    [[ -e "$S/$f" ]] || continue
    mkdir -p "$D/freesurfer/$(dirname "$f")"
    cp -L --preserve=timestamps "$S/$f" "$D/freesurfer/$f"   # -L: ?h.pial is a link to ?h.pial.T1
  done
  ( cd "$D" && find freesurfer visual_rois -type f | sort | while IFS= read -r f; do
      printf '%s\t%s\t%s\n' "$f" "$(stat -c %s "$f")" "$(sha256sum "$f" | cut -d' ' -f1)"
    done ) > "$D/manifest.tsv"
  printf '%s\tok\t%s files\n' "$SUB" "$(wc -l < "$D/manifest.tsv")" >> "$SUMMARY"
  n_ok=$((n_ok + 1))
done < "$LIST"

{
  echo "site=$SITE"; echo "kit_version=$(cat "$KIT/VERSION")"
  echo "freesurfer=$(cat "${FREESURFER_HOME:-}/build-stamp.txt" 2>/dev/null || echo unknown)"
  echo "created=$(date '+%F %T')"; echo "subjects_ok=$n_ok"; echo "subjects_failed=$n_fail"
} > "$SITE_OUT/export_info.txt"
sync 2>/dev/null || true
rc=0; tar -C "$OUT" -cf "$OUT/${SITE}_visual_proxies_export.tar" "$SITE" || rc=$?
(( rc <= 1 )) || die "tar failed ($rc)"   # 1 = 'file changed as we read it' (network file systems)
# check the tar: every subject manifest must match the files inside it
CHK="$(mktemp -d)"; trap 'rm -rf -- "$CHK"' EXIT
tar -C "$CHK" -xf "$OUT/${SITE}_visual_proxies_export.tar"
for m in "$CHK/$SITE"/*/manifest.tsv; do
  [[ -e "$m" ]] || continue
  ( cd "$(dirname "$m")" && awk -F'\t' '{print $3"  "$1}' manifest.tsv | sha256sum --quiet -c - ) \
    || die "tar content does not match $(basename "$(dirname "$m")")/manifest.tsv"
done
log "done: $n_ok subjects exported, $n_fail failed (see $SUMMARY)"
log "send: $OUT/${SITE}_visual_proxies_export.tar ($(du -h --apparent-size "$OUT/${SITE}_visual_proxies_export.tar" | cut -f1))"
