#!/usr/bin/env bash

########################################
# CONFIGURATION
########################################

jsonfile=$1

# Colors
NC='\033[0m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'

Usage() {
  echo "Usage: $0 <path_to_spec.json>"
  echo "prepare datapackage to send to for analyses"
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

# read spec.json file into variables
# FIX: '// empty' turns JSON null/false into "" instead of the string "null"
for key in $(jq -r 'keys[]' "${jsonfile}"); do
  value=$(jq -r --arg k "$key" '.[$k] // empty' "${jsonfile}")
  declare "$key"="$value"
done

# check if required variables are non-empty
for var in outputdir sitename ; do
  if [[ -z "${!var}" ]]; then
    log "$RED" "Error: Variable '$var' is not set or is empty."
    exit 1
  fi
done

# FIX: make outputdir absolute, because the script cd's around below
outputdir=$(realpath -m "${outputdir}")

# FIX: normalise optional session: "01" -> "ses-01", unset stays empty
session="${session:-}"
if [[ -n "${session}" && "${session}" != ses-* ]]; then
  session="ses-${session}"
fi

# FIX: start from a clean package so stale files from earlier runs are not shipped
rm -rf "${outputdir}/dwi-send"
mkdir -p "${outputdir}/dwi-send"


### DWI parameters
# Re-extract if the params folder OR the report is missing
if [[ ! -d "${outputdir}/dwi-params" || ! -f "${outputdir}/dwi-params/parameter_report.html" ]]; then

  log "${YELLOW}" "extract dwi / T1w parameters (to write methods section)"

  /tracto/dwi-extract_parameters.sh "${jsonfile}"

fi

# Copy params into the package if they exist (after extraction or already present)
if [[ -d "${outputdir}/dwi-params" ]]; then
  cp -r "${outputdir}/dwi-params" "${outputdir}/dwi-send/"
else
  log "$RED" "WARNING: ${outputdir}/dwi-params not found, parameters will not be included"
fi

# connectivity matrices
cd "${outputdir}/dwi-tracto" || { log "$RED" "Error: cannot cd to ${outputdir}/dwi-tracto"; exit 1; }

# Required file suffixes. The full name is built per subject AND per session:
#   <subj>_<suffix>              (no session)
#   <subj>_<ses>_<suffix>        (with session)
required_suffixes=(
    'atlas-300P7N_desc-streams_connmatrix.csv'
    'atlas-300P7N_desc-FA_connmatrix.csv'
    'atlas-300P17N_desc-streams_connmatrix.csv'
    'atlas-300P17N_desc-FA_connmatrix.csv'
    'atlas-400P7N_desc-streams_connmatrix.csv'
    'atlas-400P7N_desc-FA_connmatrix.csv'
    'atlas-400P17N_desc-streams_connmatrix.csv'
    'atlas-400P17N_desc-FA_connmatrix.csv'
    'atlas-300P17N-Buckner_desc-streams_connmatrix.csv'
    'atlas-300P17N-Buckner_desc-FA_connmatrix.csv'
    'atlas-400P17N-Buckner_desc-streams_connmatrix.csv'
    'atlas-400P17N-Buckner_desc-FA_connmatrix.csv'
    'atlas-BNA_desc-streams_connmatrix.csv'
    'atlas-BNA_desc-FA_connmatrix.csv'
)

# Usage: conn_filename <subj> <ses> <suffix>   (ses may be empty)
conn_filename() {
    echo "${1}_${2:+${2}_}${3}"
}

# Usage: have_all_files <conn_dir> <subj> <ses>
# Returns 0 if all files exist, 1 otherwise.
# Populates the global array `missing_files` with any missing file names.
have_all_files() {
    local conn_dir="$1" subj="$2" ses="$3" suffix fname
    missing_files=()
    for suffix in "${required_suffixes[@]}"; do
        fname=$(conn_filename "${subj}" "${ses}" "${suffix}")
        [ -f "${conn_dir}/${fname}" ] || missing_files+=("${fname}")
    done
    [ ${#missing_files[@]} -eq 0 ]
}

declare -A missing_report
sent_subjects=()
n_sent=0

for subj in sub-*; do
    [ -d "${subj}" ] || continue

    missing_report=()
    found=0

    # Candidate sessions ("" means no session level)
    if [[ -n "${session}" ]]; then
        # session fixed in spec.json: only look there
        candidates=("${session}")
    else
        # no session in spec: try no-session layout, then every ses-* folder
        candidates=("")
        for sesdir in "${subj}"/ses-*; do
            if [ -d "${sesdir}" ]; then
                candidates+=("${sesdir##*/}")
            fi
        done
    fi

    for ses in "${candidates[@]}"; do
        src_conn="${subj}/${ses:+${ses}/}conn"

        if have_all_files "${src_conn}" "${subj}" "${ses}"; then
            # Destination preserves the session level if there is one
            dest_conn="${outputdir}/dwi-send/${subj}/${ses:+${ses}/}conn"
            mkdir -p "${dest_conn}"
            for suffix in "${required_suffixes[@]}"; do
                fname=$(conn_filename "${subj}" "${ses}" "${suffix}")
                rsync -rltpD "${src_conn}/${fname}" "${dest_conn}/"
            done
            found=1
            n_sent=$((n_sent + 1))
        else
            missing_report["${src_conn}"]="${missing_files[*]}"
        fi
    done

    if [ "${found}" -eq 0 ]; then
        log "$RED" "ERROR! ${subj} does not have all required output files"
        for loc in "${!missing_report[@]}"; do
            if [ -d "${loc}" ]; then
                log "$RED" "  Missing in ${loc}/:"
                for m in ${missing_report[$loc]}; do
                    log "$RED" "    - ${m}"
                done
            else
                log "$RED" "  Directory not found: ${loc}/"
            fi
        done
        log "$RED" "rerun dwi-tracto for ${subj} or delete the folder"
        continue
    fi

    sent_subjects+=("${subj}")
done

# FIX: don't build an empty package
if [ "${n_sent}" -eq 0 ]; then
    log "$RED" "Error: no complete subject/session found, nothing to send."
    exit 1
fi
log "$BLUE" "Packaged ${n_sent} subject/session(s) from ${#sent_subjects[@]} subject(s)"


# qc html files (only for subjects that were actually packaged)
cd "${outputdir}/dwi-preproc" || { log "$RED" "Error: cannot cd to ${outputdir}/dwi-preproc"; exit 1; }

for subj in "${sent_subjects[@]}"; do
  for subjhtml in "${subj}_qc.html" "${subj}"_*qc.html; do
    [ -f "${subjhtml}" ] || continue   # skip if nothing matched
    rsync -rltpD "${subjhtml}" "${outputdir}/dwi-send/"
  done
done


cd "${outputdir}" || exit 1
# FIX: remove a stale folder, otherwise mv nests dwi-send *inside* it
rm -rf "${sitename}_dwi_output"
mv dwi-send "${sitename}_dwi_output"
tar -jcvf "${sitename}_dwi_output.tar.bz2" "${sitename}_dwi_output"
rm -r "${sitename}_dwi_output"

log "${GREEN}" "----------------"
log "${GREEN}" "Zipping complete"
log "${GREEN}" "----------------"
echo
log "${GREEN}" "Please upload this tar file along with the Covariates file using the Surfdrive link on tractoprep.readthedocs.io/en/latest/enigma-ocd.html"
echo
log "${GREEN}" "Many thanks for your contribution to this ENIGMA project!!"