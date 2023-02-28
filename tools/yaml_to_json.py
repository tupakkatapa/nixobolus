#!/usr/bin/env python3
# Nixobolus - Automated creation of bootable NixOS images
# https://github.com/ponkila/Nixobolus

import argparse
import json, yaml

# Parse command-line arguments
parser = argparse.ArgumentParser(description='Convert YAML to JSON')
parser.add_argument('input', metavar='INPUT_FILE', help='input YAML/YML file')
parser.add_argument('-o', '--output', metavar='OUTPUT_FILE', help='output JSON file')

args = parser.parse_args()

# Load YAML file
with open(args.input, 'r') as f:
    data = yaml.safe_load(f)

# Convert YAML to JSON
json_data = json.dumps(data, indent=4)

# Write output JSON file if specified
if args.output:
    with open(args.output, 'w') as f:
        f.write(json_data)
else:
    # Print output to console if output file not specified
    print(json_data)
