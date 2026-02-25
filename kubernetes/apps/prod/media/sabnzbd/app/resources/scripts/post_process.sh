#!/bin/sh
# Wrapper for SABnzbd post-processor hook: runs clean_nzb_name.py (invoked in pre-queue style)
# then replace_for.py (invoked in post-processor style).
#
# Usage: put this file in the same directory as the two scripts and set it as the
# single post-processing script in SABnzbd.
#
# The wrapper expects the SABnzbd post-processing argument list:
#   $1 = directory
#   $2 = orgnzbname
#   $3 = jobname
#   $4 = reportnumber
#   $5 = category
#   $6 = group
#   $7 = postprocstatus
#   $8 = url
#
# Map to clean_nzb_name.py's expected (pre-queue) args:
#   clean_nzb_name.py nzbname postprocflags category script prio downloadsize grouplist
# We map:
#   nzbname       <- orgnzbname ($2)
#   postprocflags <- postprocstatus ($7)
#   category      <- category ($5)
#   script        <- jobname ($3)
#   prio          <- reportnumber ($4)
#   downloadsize  <- "" (not available in postproc)
#   grouplist     <- group ($6)
set -u

SCRIPTDIR="$(cd "$(dirname "$0")" && pwd)"
PYTHON="${PYTHON:-python3}"

# Ensure the wrapper received postproc args from SABnzbd
if [ "$#" -lt 8 ]; then
  echo "Expected 8 post-processing arguments from SABnzbd, got $#." >&2
  echo "Args: $*" >&2
  exit 1
fi

# Map positions (shell indices: $1..$8)
# Note: in earlier messages the scripts used different numbering; these match the replace_for.py expectations.
directory="$1"
orgnzbname="$2"
jobname="$3"
reportnumber="$4"
category="$5"
group="$6"
postprocstatus="$7"
url="$8"

RC_CLEAN=0
RC_REPLACE=0

# Run clean_nzb_name.py by constructing pre-queue style arguments:
# pass 7 args after the script so that clean_nzb_name.py sees sys.argv with length 8
CLEAN_SCRIPT="$SCRIPTDIR/clean_nzb_name.py"
if [ -x "$CLEAN_SCRIPT" ] || [ -f "$CLEAN_SCRIPT" ]; then
  echo "Running clean_nzb_name.py (invoked in pre-queue style) ..."
  "$PYTHON" "$CLEAN_SCRIPT" \
    "$orgnzbname" \
    "$postprocstatus" \
    "$category" \
    "$jobname" \
    "$reportnumber" \
    "" \
    "$group" || RC_CLEAN=$?
else
  echo "Error: $CLEAN_SCRIPT not found" >&2
  RC_CLEAN=127
fi

# Run replace_for.py with the original post-processing args
REPLACE_SCRIPT="$SCRIPTDIR/replace_for.py"
if [ -x "$REPLACE_SCRIPT" ] || [ -f "$REPLACE_SCRIPT" ]; then
  echo "Running replace_for.py (post-processing) ..."
  "$PYTHON" "$REPLACE_SCRIPT" \
    "$directory" \
    "$orgnzbname" \
    "$jobname" \
    "$reportnumber" \
    "$category" \
    "$group" \
    "$postprocstatus" \
    "$url" || RC_REPLACE=$?
else
  echo "Error: $REPLACE_SCRIPT not found" >&2
  RC_REPLACE=127
fi

# Return non-zero if either failed. Prefer RETURN of the first failure (clean) if both failed.
if [ "$RC_CLEAN" -ne 0 ]; then
  exit "$RC_CLEAN"
fi
if [ "$RC_REPLACE" -ne 0 ]; then
  exit "$RC_REPLACE"
fi
exit 0
