import os, sys, os.path
fn = os.path.basename(
    os.environ.get('mapreduce_map_input_file') or
    os.environ.get('map.input.file') or
    'unknown'
)
for line in sys.stdin:
    if line.strip():
        print(f"{fn}\t1")