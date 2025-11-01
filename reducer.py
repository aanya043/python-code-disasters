import sys
from collections import defaultdict
counts = defaultdict(int)
for line in sys.stdin:
    file, cnt = line.strip().split('\t', 1)
    counts[file] += int(cnt)
for file, total in counts.items():
    print(f'"{file}": {total}')
