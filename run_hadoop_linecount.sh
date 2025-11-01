#!/bin/bash
set -euo pipefail

SRC_DIR="${SRC_DIR:-.}"

STREAMING_JAR="/usr/lib/hadoop/hadoop-streaming.jar"
if [ ! -f "$STREAMING_JAR" ]; then
  echo "[ERROR] Streaming JAR not found at: $STREAMING_JAR" >&2
  exit 1
fi
echo "[INFO] Using streaming jar: $STREAMING_JAR"
echo "[INFO] Source dir: $SRC_DIR"

# Recursively find *.py (exclude runner + junk)
mapfile -t FILES < <(
  find "$SRC_DIR" -type f -name '*.py' \
    ! -name 'mapper.py' \
    ! -name 'reducer.py' \
    ! -path '*/.git/*' \
    ! -path '*/__pycache__/*' \
    ! -path '*/venv/*' \
    ! -path '*/.venv/*' \
    | sort
)

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "[ERROR] No input .py files found under $SRC_DIR (besides mapper/reducer)." >&2
  echo "[DEBUG] Example tree:"
  find "$SRC_DIR" -maxdepth 2 -type f | sed 's/^/  /' | head -n 50
  exit 2
fi

echo "[INFO] Will process ${#FILES[@]} Python files. First few:"
printf '  - %s\n' "${FILES[@]:0:10}"

# Prep HDFS
hadoop fs -rm -r /tmp/input /tmp/output || true
hadoop fs -mkdir -p /tmp/input

# Upload sources
hadoop fs -put -f "${FILES[@]}" /tmp/input/

# Run streaming (mapper gets filename from env)
hadoop jar "$STREAMING_JAR" \
  -files mapper.py,reducer.py \
  -mapper "python3 mapper.py" \
  -reducer "python3 reducer.py" \
  -input "/tmp/input/*.py" \
  -output /tmp/output

# Collect results
hadoop fs -cat /tmp/output/* > /tmp/results.txt
cp /tmp/results.txt "$PWD/linecount.txt" || true
gsutil cp /tmp/results.txt gs://hadoop-jobs-bucket-165fb971/results.txt || true

echo "[INFO] Wrote /tmp/results.txt and copied to linecount.txt"
