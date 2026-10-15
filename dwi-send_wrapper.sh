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
for key in $(jq -r 'keys[]' "${jsonfile}"); do
  value=$(jq -r --arg k "$key" '.[$k]' "${jsonfile}")
  declare "$key"="$value"
done

# check if required variables are non-empty
for var in outputdir sitename ; do
  if [[ -z "${!var}" ]]; then
    log "$RED" "Error: Variable '$var' is not set or is empty."
    exit 1
  fi
done

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

# List of required files (relative to conn/, use ${subj} placeholder)
# NOTE: single-quoted so ${subj} is NOT expanded here — it's expanded later via eval,
# once ${subj} is actually set inside the loop.

required_files=(
    '${subj}_atlas-300P7N_desc-streams_connmatrix.csv'
    '${subj}_atlas-300P7N_desc-FA_connmatrix.csv'
    '${subj}_atlas-300P17N_desc-streams_connmatrix.csv'
    '${subj}_atlas-300P17N_desc-FA_connmatrix.csv'
    '${subj}_atlas-400P7N_desc-streams_connmatrix.csv'
    '${subj}_atlas-400P7N_desc-FA_connmatrix.csv'
    '${subj}_atlas-400P17N_desc-streams_connmatrix.csv'
    '${subj}_atlas-400P17N_desc-FA_connmatrix.csv'
    '${subj}_atlas-300P17N-Buckner_desc-streams_connmatrix.csv'
    '${subj}_atlas-300P17N-Buckner_desc-FA_connmatrix.csv'
    '${subj}_atlas-400P17N-Buckner_desc-streams_connmatrix.csv'
    '${subj}_atlas-400P17N-Buckner_desc-FA_connmatrix.csv'
    '${subj}_atlas-BNA_desc-streams_connmatrix.csv'
    '${subj}_atlas-BNA_desc-FA_connmatrix.csv'
)

# Usage: have_all_files <basepath>
# (relies on $subj being set in the calling scope)
# Returns 0 if all files exist, 1 otherwise.
# Populates the global array `missing_files` with the names of any missing files.
have_all_files() {
    local basepath="$1"
    local f fname
    missing_files=()
    for f in "${required_files[@]}"; do
        fname=$(eval echo "$f")
        [ -f "${basepath}/${fname}" ] || missing_files+=("${fname}")
    done
    [ ${#missing_files[@]} -eq 0 ]
}

# Tracks missing files per location so they can be reported if nothing is complete
declare -A missing_report

for subj in sub-*; do
    [ -d "${subj}" ] || continue

    src_conn=""
    ses=""
    missing_report=()

    # 1) Try without session: sub-XXX/conn/
    if have_all_files "${subj}/conn"; then
        src_conn="${subj}/conn"
    else
        missing_report["${subj}/conn"]="${missing_files[*]}"

        # 2) Try with any session: sub-XXX/ses-YYY/conn/
        for sesdir in "${subj}"/ses-*; do
            [ -d "${sesdir}" ] || continue
            if have_all_files "${sesdir}/conn"; then
                src_conn="${sesdir}/conn"
                ses="$(basename "${sesdir}")"
                break
            else
                missing_report["${sesdir}/conn"]="${missing_files[*]}"
            fi
        done
    fi

    if [ -z "${src_conn}" ]; then
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

    # Build destination, preserving session subdir if present
    if [ -n "${ses}" ]; then
        dest_conn="${outputdir}/dwi-send/${subj}/${ses}/conn"
    else
        dest_conn="${outputdir}/dwi-send/${subj}/conn"
    fi
    mkdir -p "${dest_conn}"

    for f in "${required_files[@]}"; do
        fname=$(eval echo "$f")
        rsync -rltpD "${src_conn}/${fname}" "${dest_conn}/"
    done
done


# qc html files
cd "${outputdir}/dwi-preproc" || { log "$RED" "Error: cannot cd to ${outputdir}/dwi-preproc"; exit 1; }

for subjhtml in sub-*.html; do
  [ -f "${subjhtml}" ] || continue   # skip if the glob matched nothing
  rsync -rltpD "${subjhtml}" "${outputdir}/dwi-send/"
done


cd "${outputdir}" || exit 1
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