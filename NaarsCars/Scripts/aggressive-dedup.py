#!/usr/bin/env python3
"""Aggressively deduplicate Xcode project file references"""

import re
import os

PROJECT_FILE = "NaarsCars.xcodeproj/project.pbxproj"

def get_filename(path):
    """Extract just the filename from a path"""
    return os.path.basename(path)

def main():
    with open(PROJECT_FILE, 'r') as f:
        content = f.read()
    
    # Find all PBXBuildFile entries for Swift sources
    # Format: UUID /* filename.swift in Sources */ = {isa = PBXBuildFile; fileRef = UUID /* filename.swift */; };
    build_file_pattern = r'([A-F0-9]{24}) /\* (.+?\.swift) in Sources \*/ = \{isa = PBXBuildFile; fileRef = ([A-F0-9]{24})[^}]+\};'
    
    # Group build files by their base filename
    build_files_by_name = {}
    for match in re.finditer(build_file_pattern, content):
        uuid = match.group(1)
        filename = get_filename(match.group(2))
        build_files_by_name.setdefault(filename, []).append(uuid)
    
    # Find duplicates (files with more than one build file entry)
    duplicates = {k: v for k, v in build_files_by_name.items() if len(v) > 1}
    
    if not duplicates:
        print("No duplicate build files found")
        return
    
    print(f"Found {len(duplicates)} files with duplicate entries:")
    
    # For each duplicate, keep the first UUID and remove references to the others
    uuids_to_remove = set()
    for filename, uuids in duplicates.items():
        print(f"  {filename}: {len(uuids)} entries -> keeping 1")
        uuids_to_remove.update(uuids[1:])  # Keep first, remove rest
    
    # Remove the duplicate build file declarations
    lines = content.split('\n')
    new_lines = []
    removed = 0
    
    for line in lines:
        # Check if this line contains a UUID to remove
        should_remove = False
        for uuid in uuids_to_remove:
            if uuid in line and 'in Sources' in line:
                should_remove = True
                break
        
        if should_remove:
            removed += 1
        else:
            new_lines.append(line)
    
    new_content = '\n'.join(new_lines)
    
    if removed > 0:
        with open(PROJECT_FILE, 'w') as f:
            f.write(new_content)
        print(f"✅ Removed {removed} duplicate build file entries")
    else:
        print("No entries removed")

if __name__ == "__main__":
    main()
