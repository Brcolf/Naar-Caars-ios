#!/usr/bin/env python3
"""Deep clean duplicate entries from Xcode project"""

import re
from collections import defaultdict

PROJECT_FILE = "NaarsCars.xcodeproj/project.pbxproj"

def main():
    with open(PROJECT_FILE, 'r') as f:
        lines = f.readlines()
    
    # Track seen entries by filename for "in Sources" entries
    seen_sources = set()
    new_lines = []
    removed_count = 0
    
    # Track which file references we've seen in the files = ( ) arrays
    in_files_array = False
    current_files = []
    files_start_line = -1
    
    i = 0
    while i < len(lines):
        line = lines[i]
        
        # Check if this is a duplicate "in Sources" build file entry
        source_match = re.search(r'/\* (.+\.swift) in Sources \*/', line)
        if source_match and 'PBXBuildFile' not in line:
            filename = source_match.group(1)
            if filename in seen_sources:
                # Skip this duplicate line
                removed_count += 1
                i += 1
                continue
            seen_sources.add(filename)
        
        new_lines.append(line)
        i += 1
    
    if removed_count > 0:
        with open(PROJECT_FILE, 'w') as f:
            f.writelines(new_lines)
        print(f"✅ Removed {removed_count} duplicate source references")
    else:
        print("No line-level duplicates found")

if __name__ == "__main__":
    main()
