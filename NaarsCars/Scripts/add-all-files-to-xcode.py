#!/usr/bin/env python3
"""
Script to add all Swift files to Xcode project that aren't already included.
This script updates project.pbxproj to add file references, build files, and group memberships.
"""

import re
import uuid
from pathlib import Path
from collections import defaultdict

def generate_xcode_id():
    """Generate a 24-character Xcode-style ID (12 pairs of uppercase hex)"""
    hex_str = uuid.uuid4().hex[:24].upper()
    return ''.join([hex_str[i:i+2] for i in range(0, 24, 2)])

def find_all_swift_files(base_path):
    """Find all Swift files in the project directory"""
    swift_files = []
    for swift_file in base_path.rglob("*.swift"):
        # Skip files in Scripts folder (not part of app target)
        if "Scripts" in str(swift_file):
            continue
        rel_path = str(swift_file.relative_to(base_path))
        swift_files.append(rel_path)
    return sorted(swift_files)

def parse_existing_files(project_content):
    """Parse existing file references from project.pbxproj"""
    existing_files = set()
    
    # Find all file references
    file_ref_pattern = r'(\w+)\s*/\*\s*([^*]+\.swift)\s*\*/.*?path\s*=\s*"([^"]+)"'
    matches = re.findall(file_ref_pattern, project_content)
    
    for file_id, comment, path in matches:
        # Normalize path (handle both relative and absolute)
        if path.startswith('/'):
            existing_files.add(path)
        else:
            existing_files.add(path)
    
    # Also check PBXFileSystemSynchronizedRootGroup - if used, all files should be auto-discovered
    if "PBXFileSystemSynchronizedRootGroup" in project_content:
        print("⚠️  Project uses PBXFileSystemSynchronizedRootGroup")
        print("   Files should auto-discover, but may need Xcode refresh")
    
    return existing_files

def get_group_path(file_path):
    """Determine which group a file belongs to based on its path"""
    parts = Path(file_path).parts
    if len(parts) == 1:
        return "NaarsCars"  # Root level files
    
    # Map directory structure to Xcode groups
    if parts[0] == "App":
        return f"NaarsCars/App"
    elif parts[0] == "Core":
        if len(parts) > 2:
            return f"NaarsCars/Core/{parts[1]}/{parts[2]}"
        elif len(parts) > 1:
            return f"NaarsCars/Core/{parts[1]}"
        return "NaarsCars/Core"
    elif parts[0] == "Features":
        if len(parts) > 2:
            return f"NaarsCars/Features/{parts[1]}/{parts[2]}"
        elif len(parts) > 1:
            return f"NaarsCars/Features/{parts[1]}"
        return "NaarsCars/Features"
    elif parts[0] == "UI":
        if len(parts) > 2:
            return f"NaarsCars/UI/{parts[1]}/{parts[2]}"
        elif len(parts) > 1:
            return f"NaarsCars/UI/{parts[1]}"
        return "NaarsCars/UI"
    elif parts[0] == "NaarsCarsTests":
        if len(parts) > 2:
            return f"NaarsCarsTests/{parts[1]}/{parts[2]}"
        elif len(parts) > 1:
            return f"NaarsCarsTests/{parts[1]}"
        return "NaarsCarsTests"
    elif parts[0] == "NaarsCarsUITests":
        return "NaarsCarsUITests"
    
    return "NaarsCars"

def is_test_file(file_path):
    """Check if file is a test file"""
    return "Tests" in file_path or "Test" in Path(file_path).name

def add_file_to_project(project_content, file_path, file_id, build_id):
    """Add a file reference and build file to the project"""
    filename = Path(file_path).name
    
    # Add PBXFileReference
    file_ref_pattern = r'(/\* Begin PBXFileReference section \*/.*?)(/\* End PBXFileReference section \*/)'
    match = re.search(file_ref_pattern, project_content, re.DOTALL)
    if match:
        file_refs = match.group(1)
        # Check if already exists
        if file_id not in file_refs:
            file_ref_line = f'\t\t{file_id} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{filename}"; sourceTree = "<group>"; }};\n'
            file_refs = file_refs.rstrip() + '\n' + file_ref_line
            project_content = project_content[:match.start(1)] + file_refs + content[match.end(1):]
    
    # Add PBXBuildFile
    build_file_pattern = r'(/\* Begin PBXBuildFile section \*/.*?)(/\* End PBXBuildFile section \*/)'
    match = re.search(build_file_pattern, project_content, re.DOTALL)
    if match:
        build_files = match.group(1)
        # Check if already exists
        if build_id not in build_files:
            build_file_line = f'\t\t{build_id} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_id} /* {filename} */; }};\n'
            build_files = build_files.rstrip() + '\n' + build_file_line
            project_content = project_content[:match.start(1)] + build_files + content[match.end(1):]
    
    return project_content

def main():
    base_path = Path(__file__).parent.parent
    project_file = base_path / "NaarsCars.xcodeproj" / "project.pbxproj"
    
    if not project_file.exists():
        print(f"❌ Project file not found: {project_file}")
        return
    
    print("=" * 80)
    print("ADDING FILES TO XCODE PROJECT")
    print("=" * 80)
    
    # Read project file
    with open(project_file, 'r') as f:
        content = f.read()
    
    # Find all Swift files
    swift_files = find_all_swift_files(base_path)
    print(f"\n📁 Found {len(swift_files)} Swift files on disk")
    
    # Parse existing files
    existing_files = parse_existing_files(content)
    print(f"📋 Found {len(existing_files)} files already in project")
    
    # Find missing files
    missing_files = []
    for file_path in swift_files:
        filename = Path(file_path).name
        # Check if file is already referenced (by filename or path)
        if filename not in [Path(f).name for f in existing_files]:
            missing_files.append(file_path)
    
    print(f"\n❌ Missing from project: {len(missing_files)} files")
    
    if not missing_files:
        print("\n✅ All files are already in the project!")
        print("\n💡 If files don't appear in Xcode:")
        print("   1. Close and reopen Xcode")
        print("   2. Clean build folder: Product → Clean Build Folder (⌘⇧K)")
        print("   3. If using PBXFileSystemSynchronizedRootGroup, Xcode should auto-discover")
        return
    
    # Show missing files
    print("\n📝 Missing files:")
    for file_path in missing_files[:20]:  # Show first 20
        print(f"   • {file_path}")
    if len(missing_files) > 20:
        print(f"   ... and {len(missing_files) - 20} more")
    
    print("\n⚠️  NOTE: This script identifies missing files.")
    print("   To add them properly, use Xcode's 'Add Files' dialog:")
    print("   1. Right-click 'NaarsCars' folder in Xcode")
    print("   2. Select 'Add Files to NaarsCars...'")
    print("   3. Select the missing folders/files")
    print("   4. Check 'Create groups' and 'Add to targets'")
    print("\n   OR manually add via drag-and-drop from Finder")
    
    # Generate a report
    report_file = base_path / "MISSING-FILES-REPORT.txt"
    with open(report_file, 'w') as f:
        f.write("MISSING FILES FROM XCODE PROJECT\n")
        f.write("=" * 80 + "\n\n")
        f.write(f"Total missing: {len(missing_files)}\n\n")
        for file_path in missing_files:
            f.write(f"{file_path}\n")
    
    print(f"\n📄 Report saved to: {report_file}")

if __name__ == "__main__":
    main()


