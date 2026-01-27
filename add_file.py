#!/usr/bin/env python3
import sys
import re
import uuid
import os

def generate_uuid():
    return uuid.uuid4().hex[:24].upper()

def add_file_to_project(project_path, file_path, group_name):
    file_name = os.path.basename(file_path)
    
    with open(project_path, 'r') as f:
        content = f.read()
    
    if file_name in content:
        print(f"⚠️  {file_name} already in project")
        return False
    
    file_ref_uuid = generate_uuid()
    build_file_uuid = generate_uuid()
    
    # 1. PBXBuildFile
    build_file_entry = f'\t\t{build_file_uuid} /* {file_name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_uuid} /* {file_name} */; }};\n'
    content = re.sub(r'(/\* Begin PBXBuildFile section \*/\n)', r'\1' + build_file_entry, content)
    
    # 2. PBXFileReference
    file_ref_entry = f'\t\t{file_ref_uuid} /* {file_name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {file_name}; sourceTree = "<group>"; }};\n'
    content = re.sub(r'(/\* Begin PBXFileReference section \*/\n)', r'\1' + file_ref_entry, content)
    
    # 3. Add to Group
    group_pattern = rf'(/\* {group_name} \*/ = \{{[^}}]*children = \(\n)([^)]*)(\);)'
    def add_to_group(match):
        return match.group(1) + f'\t\t\t\t{file_ref_uuid} /* {file_name} */,\n' + match.group(2) + match.group(3)
    
    if re.search(group_pattern, content):
        content = re.sub(group_pattern, add_to_group, content, count=1)
    else:
        print(f"❌ Group {group_name} not found")
        return False
        
    # 4. Add to Sources build phase
    sources_pattern = r'(/\* Sources \*/ = \{[^}]*isa = PBXSourcesBuildPhase[^}]*files = \(\n)([^)]*)(\);)'
    def add_to_sources(match):
        return match.group(1) + f'\t\t\t\t{build_file_uuid} /* {file_name} in Sources */,\n' + match.group(2) + match.group(3)
    
    content = re.sub(sources_pattern, add_to_sources, content, count=1)
    
    with open(project_path, 'w') as f:
        f.write(content)
    
    print(f"✅ Added {file_name} to group {group_name}")
    return True

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: add_file.py <project_path> <file_path> <group_name>")
        sys.exit(1)
    add_file_to_project(sys.argv[1], sys.argv[2], sys.argv[3])
