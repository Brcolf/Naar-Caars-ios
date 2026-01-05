#!/usr/bin/env python3
"""
Add navigation and UI component files to Xcode project.pbxproj
"""
import re
import sys

def generate_xcode_id():
    """Generate a 24-character hex ID like Xcode uses"""
    import uuid
    return ''.join([f'{ord(c):02X}' if c.isalpha() else c for c in str(uuid.uuid4()).replace('-', '')[:24]])

project_file = 'NaarsCars.xcodeproj/project.pbxproj'

# Files to add with their desired IDs (using pattern from existing files)
files_to_add = {
    # Navigation files
    'App/MainTabView.swift': ('ACDCBDD12F0B74F600956D1C', 'ACDCBDD32F0B74F600956D1C'),
    'Features/Authentication/Views/PendingApprovalView.swift': ('ACDCBDD42F0B74F700956D1C', 'ACDCBDD52F0B74F700956D1C'),
    'Features/Rides/Views/DashboardView.swift': ('ACDCBDD62F0B74F800956D1C', 'ACDCBDD62F0B74F810956D1C'),
    'Features/Messaging/Views/MessagesListView.swift': ('ACDCBDD72F0B74F900956D1C', 'ACDCBDD72F0B74F910956D1C'),
    'Features/Notifications/Views/NotificationsListView.swift': ('ACDCBDD82F0B74FA00956D1C', 'ACDCBDD82F0B74FA10956D1C'),
    'Features/Leaderboards/Views/LeaderboardView.swift': ('ACDCBDD92F0B74FB00956D1C', 'ACDCBDD92F0B74FB10956D1C'),
    'Features/Profile/Views/ProfileView.swift': ('ACDCBDDA2F0B74FC00956D1C', 'ACDCBDDA2F0B74FC10956D1C'),
    # UI Components
    'UI/Styles/ColorTheme.swift': ('ACDCBE2A2F0B7DB100956D1C', 'ACDCBE2B2F0B7DB100956D1C'),
    'UI/Styles/Typography.swift': ('ACDCBE2C2F0B7DB200956D1C', 'ACDCBE2D2F0B7DB200956D1C'),
    'UI/Components/Buttons/PrimaryButton.swift': ('ACDCBE2E2F0B7DB300956D1C', 'ACDCBE2F2F0B7DB300956D1C'),
    'UI/Components/Buttons/SecondaryButton.swift': ('ACDCBE302F0B7DB400956D1C', 'ACDCBE312F0B7DB400956D1C'),
    'UI/Components/Feedback/LoadingView.swift': ('ACDCBE322F0B7DB500956D1C', 'ACDCBE332F0B7DB500956D1C'),
    'UI/Components/Feedback/ErrorView.swift': ('ACDCBE342F0B7DB600956D1C', 'ACDCBE352F0B7DB600956D1C'),
    'UI/Components/Feedback/EmptyStateView.swift': ('ACDCBE362F0B7DB700956D1C', 'ACDCBE372F0B7DB700956D1C'),
    'UI/Components/Common/AvatarView.swift': ('ACDCBE382F0B7DB800956D1C', 'ACDCBE392F0B7DB800956D1C'),
    'UI/Components/Cards/RideCard.swift': ('ACDCBE3A2F0B7DB900956D1C', 'ACDCBE3B2F0B7DB900956D1C'),
    'UI/Components/Cards/FavorCard.swift': ('ACDCBE3C2F0B7DBA00956D1C', 'ACDCBE3D2F0B7DBA00956D1C'),
    # Utilities
    'Core/Utilities/Constants.swift': ('ACDCBE3E2F0B7DBB00956D1C', 'ACDCBE3F2F0B7DBB00956D1C'),
    'Core/Utilities/Logger.swift': ('ACDCBE402F0B7DBC00956D1C', 'ACDCBE412F0B7DBC00956D1C'),
    'Core/Extensions/Date+Extensions.swift': ('ACDCBE422F0B7DBD00956D1C', 'ACDCBE432F0B7DBD00956D1C'),
    'Core/Extensions/View+Extensions.swift': ('ACDCBE442F0B7DBE00956D1C', 'ACDCBE452F0B7DBE00956D1C'),
}

with open(project_file, 'r') as f:
    content = f.read()

# Check if files already exist
for filepath, (file_id, build_id) in files_to_add.items():
    if file_id in content:
        print(f"⚠️  {filepath} already in project")
        continue
    
    filename = filepath.split('/')[-1]
    
    # Add PBXFileReference
    file_ref_pattern = r'(/\* Begin PBXFileReference section \*/.*?)(/\* End PBXFileReference section \*/)'
    match = re.search(file_ref_pattern, content, re.DOTALL)
    if match:
        file_refs = match.group(1)
        file_ref_line = f'\t\t{file_id} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = "<group>"; }};\n'
        if file_id not in file_refs:
            file_refs = file_refs.rstrip() + '\n' + file_ref_line
            content = content[:match.start(1)] + file_refs + content[match.end(1):]
    
    # Add PBXBuildFile
    build_file_pattern = r'(/\* Begin PBXBuildFile section \*/.*?)(/\* End PBXBuildFile section \*/)'
    match = re.search(build_file_pattern, content, re.DOTALL)
    if match:
        build_files = match.group(1)
        build_file_line = f'\t\t{build_id} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_id} /* {filename} */; }};\n'
        if build_id not in build_files:
            build_files = build_files.rstrip() + '\n' + build_file_line
            content = content[:match.start(1)] + build_files + content[match.end(1):]
    
    # Add to appropriate group
    if 'App/' in filepath:
        # Add to App group
        app_group_pattern = r'(ACDCBDF22F0B779600956D1C /\* App \*/ = \{[^}]+children = \(.*?)(\);[\s\n]+path = App;)'
        match = re.search(app_group_pattern, content, re.DOTALL)
        if match:
            children = match.group(1)
            if file_id not in children:
                children = children.rstrip() + '\n' + f'\t\t\t\t{file_id} /* {filename} */,\n'
                content = content[:match.start(1)] + children + content[match.end(1):]
    
    # Add to Sources build phase
    sources_pattern = r'(ACDCBDC42F0B74F400956D1C /\* Sources \*/ = \{[^}]+files = \(.*?)(\);[\s\n]+runOnlyForDeploymentPostprocessing)'
    match = re.search(sources_pattern, content, re.DOTALL)
    if match:
        files = match.group(1)
        if build_id not in files:
            files = files.rstrip() + '\n' + f'\t\t\t\t{build_id} /* {filename} in Sources */,\n'
            content = content[:match.start(1)] + files + content[match.end(1):]
    
    print(f"✅ Added {filepath}")

with open(project_file, 'w') as f:
    f.write(content)

print("✅ All files added to Xcode project")

