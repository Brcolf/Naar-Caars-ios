#!/usr/bin/env python3
"""Add a single file to Xcode project safely"""

import re
import uuid

PROJECT_FILE = "NaarsCars.xcodeproj/project.pbxproj"
FILE_TO_ADD = "UI/Components/Map/AddressText.swift"
FILE_NAME = "AddressText.swift"
GROUP_NAME = "Map"

def generate_uuid():
    """Generate a 24-char hex UUID like Xcode uses"""
    return uuid.uuid4().hex[:24].upper()

def main():
    with open(PROJECT_FILE, 'r') as f:
        content = f.read()
    
    # Check if already added
    if FILE_NAME in content:
        print(f"⚠️  {FILE_NAME} already in project")
        return
    
    file_ref_uuid = generate_uuid()
    build_file_uuid = generate_uuid()
    
    # 1. Add PBXBuildFile entry (after first PBXBuildFile line)
    build_file_entry = f'\t\t{build_file_uuid} /* {FILE_NAME} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_uuid} /* {FILE_NAME} */; }};\n'
    
    # Find the PBXBuildFile section and add entry
    pbx_build_match = re.search(r'/\* Begin PBXBuildFile section \*/\n', content)
    if pbx_build_match:
        insert_pos = pbx_build_match.end()
        content = content[:insert_pos] + build_file_entry + content[insert_pos:]
    
    # 2. Add PBXFileReference entry
    file_ref_entry = f'\t\t{file_ref_uuid} /* {FILE_NAME} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {FILE_NAME}; sourceTree = "<group>"; }};\n'
    
    # Find the PBXFileReference section and add entry
    pbx_file_match = re.search(r'/\* Begin PBXFileReference section \*/\n', content)
    if pbx_file_match:
        insert_pos = pbx_file_match.end()
        content = content[:insert_pos] + file_ref_entry + content[insert_pos:]
    
    # 3. Add to Map group's children
    # Find the Map group and add the file reference
    map_group_pattern = r'(/\* Map \*/ = \{[^}]*children = \(\n)([^)]+)(\);)'
    
    def add_to_group(match):
        prefix = match.group(1)
        children = match.group(2)
        suffix = match.group(3)
        new_child = f'\t\t\t\t{file_ref_uuid} /* {FILE_NAME} */,\n'
        return prefix + new_child + children + suffix
    
    content = re.sub(map_group_pattern, add_to_group, content, count=1)
    
    # 4. Add to Sources build phase
    # Find the main target's Sources build phase and add the build file
    sources_pattern = r'(/\* Sources \*/ = \{[^}]*isa = PBXSourcesBuildPhase[^}]*files = \(\n)([^)]+)(\);)'
    
    def add_to_sources(match):
        prefix = match.group(1)
        files = match.group(2)
        suffix = match.group(3)
        new_file = f'\t\t\t\t{build_file_uuid} /* {FILE_NAME} in Sources */,\n'
        return prefix + new_file + files + suffix
    
    content = re.sub(sources_pattern, add_to_sources, content, count=1)
    
    with open(PROJECT_FILE, 'w') as f:
        f.write(content)
    
    print(f"✅ Added {FILE_NAME} to project")

if __name__ == "__main__":
    main()
