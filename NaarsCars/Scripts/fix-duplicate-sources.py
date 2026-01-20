#!/usr/bin/env python3
"""Remove duplicate source file entries from Xcode project"""

import re

PROJECT_FILE = "NaarsCars.xcodeproj/project.pbxproj"

def main():
    with open(PROJECT_FILE, 'r') as f:
        content = f.read()
    
    # Find the PBXSourcesBuildPhase section and remove duplicate entries
    # Each entry looks like: UUID /* filename.swift in Sources */ = {isa = PBXBuildFile; ...
    
    # First, find all "in Sources" build file entries
    build_file_pattern = r'(\s+[A-F0-9]{24} /\* .+\.swift in Sources \*/ = \{isa = PBXBuildFile;[^}]+\};)'
    
    # Find all source file references in the files array of PBXSourcesBuildPhase
    sources_section_pattern = r'(/\* Sources \*/ = \{[^}]*files = \()([^)]+)(\);)'
    
    def dedupe_sources_section(match):
        prefix = match.group(1)
        files_content = match.group(2)
        suffix = match.group(3)
        
        # Split into individual file references
        file_refs = [f.strip() for f in files_content.split(',') if f.strip()]
        
        # Extract unique file names and keep only first occurrence
        seen_files = {}
        unique_refs = []
        
        for ref in file_refs:
            # Extract filename from comment like "UUID /* filename.swift in Sources */"
            name_match = re.search(r'/\* (.+\.swift) in Sources \*/', ref)
            if name_match:
                filename = name_match.group(1)
                if filename not in seen_files:
                    seen_files[filename] = True
                    unique_refs.append(ref)
            else:
                unique_refs.append(ref)
        
        removed = len(file_refs) - len(unique_refs)
        if removed > 0:
            print(f"  Removed {removed} duplicate entries from Sources build phase")
        
        return prefix + '\n\t\t\t\t' + ',\n\t\t\t\t'.join(unique_refs) + ',\n\t\t\t' + suffix
    
    # Process all Sources build phases
    new_content = re.sub(sources_section_pattern, dedupe_sources_section, content, flags=re.DOTALL)
    
    if new_content != content:
        with open(PROJECT_FILE, 'w') as f:
            f.write(new_content)
        print("✅ Removed duplicate source file entries from project")
    else:
        print("No duplicates found in Sources build phases")

if __name__ == "__main__":
    main()
