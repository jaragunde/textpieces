#!/usr/bin/env python3

from sys import stdin, stdout, stderr

import json
import yaml

try:
    _dict = json.load(stdin)
except json.JSONDecodeError:
    stderr.write("Invalid JSON")
    exit(1)

yaml.dump(
    _dict,
    stdout,
    sort_keys=False
)
