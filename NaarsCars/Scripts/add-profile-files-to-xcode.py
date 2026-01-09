#!/usr/bin/env python3
"""
Add profile feature files to Xcode project.pbxproj
"""
import re
import uuid
import os

def generate_xcode_id():
    """Generate a 24-character hex ID like Xcode uses"""
    return ''.join([f'{uuid.uuid4().hex[i:i+2].upper()}' for i in range(0, 24, 2)])

# Files to add with their generated IDs
# Format: 'path/to/file.swift': (file_ref_id, build_file_id)
files_to_add = {
    # Core Services
    'Core/Services/ProfileService.swift': (generate_xcode_id(), generate_xcode_id()),
    
    # Core Utilities
    'Core/Utilities/Validators.swift': (generate_xcode_id(), generate_xcode_id()),
    
    # ViewModels
    'Features/Profile/ViewModels/MyProfileViewModel.swift': (generate_xcode_id(), generate_xcode_id()),
    'Features/Profile/ViewModels/EditProfileViewModel.swift': (generate_xcode_id(), generate_xcode_id()),
    'Features/Profile/ViewModels/PublicProfileViewModel.swift': (generate_xcode_id(), generate_xcode_id()),
    
    # Views
    'Features/Profile/Views/MyProfileView.swift': (generate_xcode_id(), generate_xcode_id()),
    'Features/Profile/Views/EditProfileView.swift': (generate_xcode_id(), generate_xcode_id()),
    'Features/Profile/Views/PublicProfileView.swift': (generate_xcode_id(), generate_xcode_id()),
    
    # UI Components
    'UI/Components/Common/UserAvatarLink.swift': (generate_xcode_id(), generate_xcode_id()),
    'UI/Components/Common/StarRatingView.swift': (generate_xcode_id(), generate_xcode_id()),
    'UI/Components/Cards/ReviewCard.swift': (generate_xcode_id(), generate_xcode_id()),
    'UI/Components/Cards/InviteCodeCard.swift': (generate_xcode_id(), generate_xcode_id()),
}

# Test files
test_files_to_add = {
    'NaarsCarsTests/Core/Services/ProfileServiceTests.swift': (generate_xcode_id(), generate_xcode_id()),
    'NaarsCarsTests/Core/Utilities/ValidatorsTests.swift': (generate_xcode_id(), generate_xcode_id()),
    'NaarsCarsTests/Features/Profile/MyProfileViewModelTests.swift': (generate_xcode_id(), generate_xcode_id()),
    'NaarsCarsTests/Features/Profile/EditProfileViewModelTests.swift': (generate_xcode_id(), generate_xcode_id()),
    'NaarsCarsTests/Features/Profile/PublicProfileViewModelTests.swift': (generate_xcode_id(), generate_xcode_id()),
}

project_file = 'NaarsCars.xcodeproj/project.pbxproj'

if not os.path.exists(project_file):
    print(f"❌ Error: {project_file} not found")
    print("Please run this script from the NaarsCars directory")
    exit(1)

with open(project_file, 'r') as f:
    content = f.read()

# Add file references
file_refs_section = re.search(r'(/\* Begin PBXFileReference section \*/.*?)(/\* End PBXFileReference section \*/)', content, re.DOTALL)
if file_refs_section:
    file_refs = file_refs_section.group(1)
    
    # Add source file references
    for filepath, (file_id, build_id) in files_to_add.items():
        filename = filepath.split('/')[-1]
        file_ref = f'\t\t{file_id} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = "<group>"; }};\n'
        if file_id not in file_refs:
            file_refs += file_ref
            print(f"✅ Added file reference: {filepath}")
        else:
            print(f"⚠️  File reference already exists: {filepath}")
    
    # Add test file references
    for filepath, (file_id, build_id) in test_files_to_add.items():
        filename = filepath.split('/')[-1]
        file_ref = f'\t\t{file_id} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = "<group>"; }};\n'
        if file_id not in file_refs:
            file_refs += file_ref
            print(f"✅ Added test file reference: {filepath}")
        else:
            print(f"⚠️  Test file reference already exists: {filepath}")
    
    content = content.replace(file_refs_section.group(1), file_refs)

# Add build files
build_files_section = re.search(r'(/\* Begin PBXBuildFile section \*/.*?)(/\* End PBXBuildFile section \*/)', content, re.DOTALL)
if build_files_section:
    build_files = build_files_section.group(1)
    
    # Add source build files
    for filepath, (file_id, build_id) in files_to_add.items():
        filename = filepath.split('/')[-1]
        build_file = f'\t\t{build_id} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_id} /* {filename} */; }};\n'
        if build_id not in build_files:
            build_files += build_file
            print(f"✅ Added build file: {filepath}")
        else:
            print(f"⚠️  Build file already exists: {filepath}")
    
    # Add test build files
    for filepath, (file_id, build_id) in test_files_to_add.items():
        filename = filepath.split('/')[-1]
        build_file = f'\t\t{build_id} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_id} /* {filename} */; }};\n'
        if build_id not in build_files:
            build_files += build_file
            print(f"✅ Added test build file: {filepath}")
        else:
            print(f"⚠️  Test build file already exists: {filepath}")
    
    content = content.replace(build_files_section.group(1), build_files)

# Add to appropriate groups
# This is a simplified version - you may need to adjust group IDs based on your project structure

# Add ProfileService to Services group
services_group_pattern = r'(/\* Services \*/.*?children = \(.*?)(\);.*?path = Services;)'
match = re.search(services_group_pattern, content, re.DOTALL)
if match:
    children = match.group(1)
    file_id = files_to_add['Core/Services/ProfileService.swift'][0]
    filename = 'ProfileService.swift'
    child = f'\t\t\t\t{file_id} /* {filename} */,\n'
    if file_id not in children:
        children += child
        content = content.replace(match.group(1), children)
        print(f"✅ Added ProfileService to Services group")

# Add Validators to Utilities group
utilities_group_pattern = r'(/\* Utilities \*/.*?children = \(.*?)(\);.*?path = Utilities;)'
match = re.search(utilities_group_pattern, content, re.DOTALL)
if match:
    children = match.group(1)
    file_id = files_to_add['Core/Utilities/Validators.swift'][0]
    filename = 'Validators.swift'
    child = f'\t\t\t\t{file_id} /* {filename} */,\n'
    if file_id not in children:
        children += child
        content = content.replace(match.group(1), children)
        print(f"✅ Added Validators to Utilities group")

# Add ViewModels to Profile group (create if needed)
# Add Views to Profile group (create if needed)
# Add UI Components to appropriate groups

# Add to Sources build phase
sources_phase_pattern = r'(ACDCBDC42F0B74F400956D1C /\* Sources \*/ = \{.*?files = \(.*?)(\);.*?runOnlyForDeploymentPostprocessing = 0;)'
match = re.search(sources_phase_pattern, content, re.DOTALL)
if match:
    files = match.group(1)
    for filepath, (file_id, build_id) in files_to_add.items():
        filename = filepath.split('/')[-1]
        file_entry = f'\t\t\t\t{build_id} /* {filename} in Sources */,\n'
        if build_id not in files:
            files += file_entry
            print(f"✅ Added {filepath} to Sources build phase")
    content = content.replace(match.group(1), files)

# Add to test Sources build phase
test_sources_phase_pattern = r'(ACDCBDD12F0B74F700956D1C /\* Sources \*/ = \{.*?files = \(.*?)(\);.*?runOnlyForDeploymentPostprocessing = 0;)'
match = re.search(test_sources_phase_pattern, content, re.DOTALL)
if match:
    files = match.group(1)
    for filepath, (file_id, build_id) in test_files_to_add.items():
        filename = filepath.split('/')[-1]
        file_entry = f'\t\t\t\t{build_id} /* {filename} in Sources */,\n'
        if build_id not in files:
            files += file_entry
            print(f"✅ Added {filepath} to test Sources build phase")
    content = content.replace(match.group(1), files)

with open(project_file, 'w') as f:
    f.write(content)

print("\n✅ All profile files added to Xcode project")
print("⚠️  Note: You may need to manually add files to group folders in Xcode Project Navigator")
print("⚠️  Note: Verify all files appear in Project Navigator and build the project")

