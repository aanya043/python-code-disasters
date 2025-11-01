import os, sys, os.path
fn = os.path.basename(
    os.environ.get('mapreduce_map_input_file') or
    os.environ.get('map.input.file') or
    'unknown'
)
for _ in sys.stdin:
    print(f"{fn}\t1")
