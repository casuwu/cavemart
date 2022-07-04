#! /usr/bin/env python3

import argparse

# Create the parser
parser = argparse.ArgumentParser()

# Add the arguments
parser.add_argument('-f', required=True)
parser.add_argument('-c', required=True)
parser.add_argument('-n', required=True)

# Parse the arguments
args = parser.parse_args()

def _write(file, content, new_line):
    
    if new_line == "True":
        content = "\n" + content
    
    with open(file, "a") as f:
        f.write(content)

_write(args.f, args.c, args.n)