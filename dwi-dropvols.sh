#!/usr/bin/env bash

########################################
# CONFIGURATION
########################################

jsonfile=$1

# python script that performs the actual volume deletion
# (can be overridden with the 'dropscript' key in spec.json)
dropscript="${dropscript:-/tracto/helpers/dwi-dropvols.py}"

# Colors
NC='\033[0m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0m'
YELLOW='\033[0;33m'

Usage() {
  echo "Usage: $0 <path_to_spec.json>"
  echo "delete volumes from a processed dwi scan"
  echo "(nii / bval / bvec are updated in place, the originals are kept as .orig"
  echo " and a *_desc-cleaned.json log is written next to the nifti)"
  echo "the script asks for confirmation (y/N) before deleting anything"
  echo ""
  echo "spec.json must contain at least:"
  echo "  {"
  echo "    \"subj\":      \"sub-01\","
  echo "    \"session\":   \"ses-01\","
  echo "    \"outputdir\": \"/path/to/output\","
  echo "    \"volumes\":   [0, 1, 5]"
  echo "  }"
  echo ""
  echo "  subj      : subject label"
  echo "  session   : session label, empty string (\"\") if the data has no session"
  echo "  outputdir : output directory that contains the dwi-preproc folder"
  echo "  volumes   : zero-based volume indices to delete, as a list,"
  echo "              e.g. [0, 1, 5]; ranges are also allowed, e.g. [\"3-7\", 12]"
  echo ""
  echo "the dwi files are expected at (session folder and the ses- part in the"
  echo "filename are only present when the data has sessions):"
  echo "  \${outputdir}/dwi-preproc/\${subj}/dwi/\${subj}_space-dwi_desc-preproc_dwi.nii.gz"
  echo "  \${outputdir}/dwi-preproc/\${subj}/\${session}/dwi/\${subj}_\${session}_space-dwi_desc-preproc_dwi.nii.gz"
  echo "  (with matching .bval and .bvec files)"
  echo ""
  echo "optional keys:"
  echo "  dwidir     : folder containing the subject folders (default: \${outputdir}/dwi-preproc)"
  echo "  dropscript : path to the python script (default: /tracto/helpers/dwi-dropvol.py)"
  exit 1
}

# Helper function for colored output
log() {
    local color="$1"
    shift
    echo -e "${color}$*${NC}"
}

# Check input json
if [[ -z "$jsonfile" || ! -f "$jsonfile" ]]; then
  log "$RED" "Error: spec.json file not provided or does not exist."
  Usage
fi

# check that the spec file is valid json and contains an object
if ! jq -e 'type == "object"' "${jsonfile}" >/dev/null 2>&1; then
  log "$RED" "Error: ${jsonfile} is not valid json or does not contain a json object"
  exit 1
fi

# read spec.json file into variables
for key in $(jq -r 'keys[]' "${jsonfile}"); do
  value=$(jq -r --arg k "$key" '.[$k]' "${jsonfile}")
  declare "$key"="$value"
done

# treat json null values as empty
[[ "${session}" == "null" ]] && session=""
[[ "${volumes}" == "null" ]] && volumes=""

# check if required variables are non-empty
for var in subj outputdir volumes ; do
  if [[ -z "${!var}" ]]; then
    log "$RED" "Error: Variable '$var' is not set or is empty."
    exit 1
  fi
done

# 'volumes' must be a json list of zero-based volume indices, e.g. [0, 1, 5]
if ! jq -e '.volumes | type == "array"' "${jsonfile}" >/dev/null 2>&1; then
  log "$RED" "Error: 'volumes' must be a list of volume indices, e.g. \"volumes\": [0, 1, 5]"
  exit 1
fi

# convert the list to a comma-separated string for the python script
volumes=$(jq -r '.volumes | map(tostring) | join(",")' "${jsonfile}")

# validate 'volumes': zero-based indices, comma separated (ranges allowed)
volumes_regex='^[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$'
if ! [[ "${volumes}" =~ ${volumes_regex} ]]; then
  log "$RED" "Error: invalid 'volumes' specification: ${volumes}"
  log "$RED" "Expected zero-based volume indices, e.g. [0, 1, 5]"
  exit 1
fi

# reversed ranges (e.g. "7-3") are not allowed
if printf '%s\n' "${volumes}" | tr ',' '\n' | awk -F- 'NF == 2 && $1 > $2 { bad = 1 } END { exit bad ? 0 : 1 }'; then
  log "$RED" "Error: invalid 'volumes' specification: ${volumes} (reversed range)"
  exit 1
fi

# normalize labels: accept "01" as well as "sub-01" / "ses-01"
[[ "${subj}" == sub-* ]] || subj="sub-${subj}"
if [[ -n "${session}" && "${session}" != ses-* ]]; then
  session="ses-${session}"
fi

# check dependencies
if ! command -v python3 >/dev/null 2>&1; then
  log "$RED" "Error: python3 not found"
  exit 1
fi

if [[ ! -f "${dropscript}" ]]; then
  log "$RED" "Error: python script not found: ${dropscript}"
  log "$RED" "set the 'dropscript' key in spec.json to its location"
  exit 1
fi

if [[ ! -d "${outputdir}" ]]; then
  log "$RED" "Error: outputdir does not exist: ${outputdir}"
  exit 1
fi

########################################
# LOCATE THE DWI FILE SET (nii + bval + bvec)
########################################

dwidir="${dwidir:-${outputdir}/dwi-preproc}"

if [[ ! -d "${dwidir}" ]]; then
  log "$RED" "Error: ${dwidir} not found"
  log "$RED" "set the 'dwidir' key in spec.json if the dwi files live elsewhere"
  exit 1
fi

if [[ ! -d "${dwidir}/${subj}" ]]; then
  log "$RED" "Error: subject folder not found: ${dwidir}/${subj}"
  exit 1
fi

# locate the dwi folder:
#   with session   : ${dwidir}/${subj}/${session}/dwi
#   without session: ${dwidir}/${subj}/dwi
if [[ -n "${session}" ]]; then
  dwi_dir="${dwidir}/${subj}/${session}/dwi"
else
  dwi_dir="${dwidir}/${subj}/dwi"
  if [[ ! -d "${dwi_dir}" ]]; then
    # no session given, but the subject may only have session folders:
    # use the single session if there is exactly one, otherwise ask for one
    declare -a sesdirs=()
    for sesdir in "${dwidir}/${subj}"/ses-*/dwi; do
      [[ -d "${sesdir}" ]] && sesdirs+=("${sesdir}")
    done
    if [[ ${#sesdirs[@]} -eq 1 ]]; then
      session="$(basename "$(dirname "${sesdirs[0]}")")"
      dwi_dir="${sesdirs[0]}"
      log "${YELLOW}" "no session specified, using the only session found: ${session}"
    elif [[ ${#sesdirs[@]} -gt 1 ]]; then
      log "$RED" "Error: multiple sessions found for ${subj}:"
      for d in "${sesdirs[@]}"; do
        log "$RED" "  - $(basename "$(dirname "${d}")")"
      done
      log "$RED" "add the 'session' key to spec.json to select one"
      exit 1
    fi
  fi
fi

if [[ ! -d "${dwi_dir}" ]]; then
  log "$RED" "Error: dwi folder not found: ${dwi_dir}"
  if [[ -n "${session}" && -d "${dwidir}/${subj}/dwi" ]]; then
    log "$RED" "       (subject-level dwi data exists, try leaving 'session' empty)"
  fi
  exit 1
fi

# the preprocessed dwi files are always named:
#   with session   : ${subj}_${session}_space-dwi_desc-preproc_dwi.nii.gz / .bval / .bvec
#   without session: ${subj}_space-dwi_desc-preproc_dwi.nii.gz / .bval / .bvec
if [[ -n "${session}" ]]; then
  dwi_base="${dwi_dir}/${subj}_${session}_space-dwi_desc-preproc_dwi"
else
  dwi_base="${dwi_dir}/${subj}_space-dwi_desc-preproc_dwi"
fi

if [[ -f "${dwi_base}.nii.gz" ]]; then
  nii_file="${dwi_base}.nii.gz"
elif [[ -f "${dwi_base}.nii" ]]; then
  nii_file="${dwi_base}.nii"
else
  # fall back: look for any ${subj}_*space-dwi_desc-preproc_dwi nifti in the dwi folder
  declare -a found=()
  for f in "${dwi_dir}"/${subj}_*space-dwi_desc-preproc_dwi.nii.gz \
           "${dwi_dir}"/${subj}_*space-dwi_desc-preproc_dwi.nii; do
    [[ -f "${f}" ]] && found+=("${f}")
  done
  if [[ ${#found[@]} -eq 1 ]]; then
    nii_file="${found[0]}"
    log "${YELLOW}" "using ${nii_file} (filename differs from the expected pattern)"
  elif [[ ${#found[@]} -gt 1 ]]; then
    log "$RED" "Error: multiple dwi files found in ${dwi_dir}:"
    for f in "${found[@]}"; do
      log "$RED" "  - ${f}"
    done
    exit 1
  else
    log "$RED" "Error: dwi file not found: ${dwi_base}.nii.gz"
    exit 1
  fi
fi

# derive bval / bvec from the nifti basename and check that they exist
base="${nii_file%.nii.gz}"
base="${base%.nii}"
bval_file="${base}.bval"
bvec_file="${base}.bvec"

for f in "${nii_file}" "${bval_file}" "${bvec_file}"; do
  if [[ ! -f "${f}" ]]; then
    log "$RED" "Error: ${f} not found"
    exit 1
  fi
done

########################################
# FAILSAFE: REFUSE TO RUN IF BACKUPS ALREADY EXIST
########################################

for f in "${nii_file}" "${bval_file}" "${bvec_file}"; do
  if [[ -f "${f}.orig" ]]; then
    log "$RED" "Error: ${f}.orig already exists"
    log "$RED" "volumes were already dropped for this scan;"
    log "$RED" "move or delete the .orig files first if you really want to re-run"
    exit 1
  fi
done

########################################
# DROP THE VOLUMES
########################################

n_vols=$(awk '{n+=NF} END{print n+0}' "${bval_file}")

# check that all requested volumes exist before touching any file
bad_vols=$(printf '%s\n' "${volumes}" | tr ',' '\n' | awk -v n="${n_vols}" '
  /-/ { split($0, r, "-"); for (i = r[1]; i <= r[2]; i++) if (i >= n) print i; next }
  { if ($1 >= n) print $1 }')
if [[ -n "${bad_vols}" ]]; then
  log "$RED" "Error: volume index(es) out of range: $(echo ${bad_vols} | tr '\n' ' ')"
  log "$RED" "       the scan has ${n_vols} volumes (valid indices: 0-$((n_vols - 1)))"
  exit 1
fi

# summary of what will be done
ses_part=""
[[ -n "${session}" ]] && ses_part=" (${session})"

log "${BLUE}" "subject                  : ${subj}"
[[ -n "${session}" ]] && log "${BLUE}" "session                  : ${session}"
log "${BLUE}" "dwi                      : ${nii_file}"
log "${BLUE}" "No. volumes in scan       : ${n_vols}"
log "${BLUE}" "volume(s) to drop (0-based): ${volumes}"

########################################
# CONFIRMATION
########################################

# ask the user to confirm before any file is modified
# (read from the terminal so this also works when stdin is redirected)
echo -e "${YELLOW}Delete volume(s) ${volumes} from ${subj}${ses_part}? [y/N]${NC}"
if ! read -r answer < /dev/tty; then
  log "$RED" "Error: no confirmation received, aborting"
  exit 1
fi

case "${answer}" in
  [Yy]|[Yy][Ee][Ss])
    log "${GREEN}" "confirmed, dropping volume(s)"
    ;;
  *)
    log "$RED" "Aborted, no files were modified"
    exit 1
    ;;
esac

if ! python3 "${dropscript}" "${nii_file}" "${bval_file}" "${bvec_file}" --drop "${volumes}"; then
  log "$RED" "Error: dropping volumes failed for ${subj}"
  exit 1
fi

log "${GREEN}" "----------------"
log "${GREEN}" "Volumes dropped"
log "${GREEN}" "----------------"
log "${GREEN}" "originals kept as: ${nii_file}.orig, ${bval_file}.orig, ${bvec_file}.orig"
log "${GREEN}" "log written to    : ${base}_desc-cleaned.json"
log "${GREEN}" "to undo           : rename the .orig files back to their original names"

# warn about downstream results that are based on the original volumes
if [[ -d "${outputdir}/dwi-tracto/${subj}" ]]; then
  log "${YELLOW}" "WARNING: existing tractography output for ${subj} is based on the original volumes"
  log "${YELLOW}" "         consider re-running dwi-tracto for ${subj}"
fi
if [[ -f "${outputdir}/dwi-params/parameter_report.html" ]]; then
  log "${YELLOW}" "WARNING: dwi parameters were extracted from the original volumes"
  log "${YELLOW}" "         consider re-running dwi-extract_parameters"
fi
