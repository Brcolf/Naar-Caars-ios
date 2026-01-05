#!/usr/bin/env python3
"""
Add model files to Xcode project.pbxproj
"""
import re
import uuid

def generate_xcode_id():
    """Generate a 24-character hex ID like Xcode uses"""
    return ''.join([f'{uuid.uuid4().hex[i:i+2].upper()}' for i in range(0, 24, 2)])

# Model files with their IDs
models = {
    'Profile.swift': ('3E213562F51C49A48F8FFF22', '84D9FCFB10CF4588B6DBDE7B'),
    'Ride.swift': ('2B634CBD0C4F4A449A464E94', 'E45167AB602B45E7B6D76981'),
    'Favor.swift': ('EAA13F58C91D42D592759C0A', 'CCD8C9BD002E479487AEC882'),
    'Message.swift': ('ACCB369A6355469493FD86E2', 'CEE4883F511E4863BD984568'),
    'Conversation.swift': ('BD9C1B07712F4342B2190EC3', '4AEC6FC9813D460387D9E4C0'),
    'AppNotification.swift': ('C1C3095B25134EB5AEC9473F', 'B29F4A793E8647D9911439DC'),
    'InviteCode.swift': ('5AB659281CBB4F4F8D32CAA1', 'DBEB76AEBDE842259F2C55B0'),
    'Review.swift': ('BC5778A5153E4104992A72BB', '789FE0C64BB34FBD80D8B882'),
    'TownHallPost.swift': ('A5BD6728D2674DDB93C700C3', '1F9DB8AF994C4A7198BC39C7'),
}

# Test files with their IDs
tests = {
    'ProfileTests.swift': ('137CEAA3220D4C2D9BE917E3', 'B3BDA45A8E05444CAB1EF3A8'),
    'RideTests.swift': ('BB8F6F3E319E4B4FB1541AE0', 'DC8A8AB167BC402DB2FCC38F'),
    'FavorTests.swift': ('4AD8D7D6054B4B559ED772AC', '28B926AB58164D40896CFF72'),
}

project_file = 'NaarsCars.xcodeproj/project.pbxproj'

with open(project_file, 'r') as f:
    content = f.read()

# Add file references
file_refs_section = re.search(r'(/\* Begin PBXFileReference section \*/.*?)(/\* End PBXFileReference section \*/)', content, re.DOTALL)
if file_refs_section:
    file_refs = file_refs_section.group(1)
    
    # Add model file references
    for filename, (file_id, build_id) in models.items():
        file_ref = f'\t\t{file_id} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = "<group>"; }};\n'
        if file_id not in file_refs:
            file_refs += file_ref
    
    # Add test file references
    for filename, (file_id, build_id) in tests.items():
        file_ref = f'\t\t{file_id} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = "<group>"; }};\n'
        if file_id not in file_refs:
            file_refs += file_ref
    
    content = content.replace(file_refs_section.group(1), file_refs)

# Add build files
build_files_section = re.search(r'(/\* Begin PBXBuildFile section \*/.*?)(/\* End PBXBuildFile section \*/)', content, re.DOTALL)
if build_files_section:
    build_files = build_files_section.group(1)
    
    # Add model build files
    for filename, (file_id, build_id) in models.items():
        build_file = f'\t\t{build_id} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_id} /* {filename} */; }};\n'
        if build_id not in build_files:
            build_files += build_file
    
    # Add test build files
    for filename, (file_id, build_id) in tests.items():
        build_file = f'\t\t{build_id} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_id} /* {filename} */; }};\n'
        if build_id not in build_files:
            build_files += build_file
    
    content = content.replace(build_files_section.group(1), build_files)

# Add to Models group
models_group = re.search(r'(ACDCBE012F0B784900956D1C /\* Models \*/ = \{.*?children = \(.*?)(\);.*?path = Models;)', content, re.DOTALL)
if models_group:
    children = models_group.group(1)
    for filename, (file_id, build_id) in models.items():
        child = f'\t\t\t\t{file_id} /* {filename} */,\n'
        if file_id not in children:
            children += child
    content = content.replace(models_group.group(1), children)

# Add to Sources build phase
sources_phase = re.search(r'(ACDCBDC42F0B74F400956D1C /\* Sources \*/ = \{.*?files = \(.*?)(\);.*?runOnlyForDeploymentPostprocessing = 0;)', content, re.DOTALL)
if sources_phase:
    files = sources_phase.group(1)
    for filename, (file_id, build_id) in models.items():
        file_entry = f'\t\t\t\t{build_id} /* {filename} in Sources */,\n'
        if build_id not in files:
            files += file_entry
    content = content.replace(sources_phase.group(1), files)

# Add to test Sources build phase
test_sources_phase = re.search(r'(ACDCBDD12F0B74F700956D1C /\* Sources \*/ = \{.*?files = \(.*?)(\);.*?runOnlyForDeploymentPostprocessing = 0;)', content, re.DOTALL)
if test_sources_phase:
    files = test_sources_phase.group(1)
    for filename, (file_id, build_id) in tests.items():
        file_entry = f'\t\t\t\t{build_id} /* {filename} in Sources */,\n'
        if build_id not in files:
            files += file_entry
    content = content.replace(test_sources_phase.group(1), files)

# Find test Models group (need to check if it exists)
test_models_group = re.search(r'(/\* Models \*/.*?children = \(.*?)(\);.*?path = Models;)', content, re.DOTALL)
if test_models_group:
    children = test_models_group.group(1)
    for filename, (file_id, build_id) in tests.items():
        child = f'\t\t\t\t{file_id} /* {filename} */,\n'
        if file_id not in children:
            children += child
    content = content.replace(test_models_group.group(1), children)
else:
    # Need to find the test Core group and add Models group
    pass

with open(project_file, 'w') as f:
    f.write(content)

print("✅ Added all model files to Xcode project")


