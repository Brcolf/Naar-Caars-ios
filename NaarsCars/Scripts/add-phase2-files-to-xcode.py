#!/usr/bin/env python3
"""
Add Phase 2 Communication feature files to Xcode project
"""

import re
import uuid

def generate_xcode_id():
    """Generate a 24-character hex ID for Xcode"""
    return ''.join([f'{uuid.uuid4().hex[i:i+2].upper()}' for i in range(0, 24, 2)])

# Phase 2 files to add with their paths and generated IDs
files_to_add = {
    # Messaging Services
    'Core/Services/MessageService.swift': (generate_xcode_id(), generate_xcode_id()),
    'Core/Services/ConversationService.swift': (generate_xcode_id(), generate_xcode_id()),
    
    # Messaging ViewModels
    'Features/Messaging/ViewModels/ConversationsListViewModel.swift': (generate_xcode_id(), generate_xcode_id()),
    'Features/Messaging/ViewModels/ConversationDetailViewModel.swift': (generate_xcode_id(), generate_xcode_id()),
    
    # Messaging Views
    'Features/Messaging/Views/ConversationsListView.swift': (generate_xcode_id(), generate_xcode_id()),
    'Features/Messaging/Views/ConversationDetailView.swift': (generate_xcode_id(), generate_xcode_id()),
    
    # Messaging UI Components
    'UI/Components/Messaging/MessageBubble.swift': (generate_xcode_id(), generate_xcode_id()),
    'UI/Components/Messaging/MessageInputBar.swift': (generate_xcode_id(), generate_xcode_id()),
    
    # Push Notifications
    'Core/Services/PushNotificationService.swift': (generate_xcode_id(), generate_xcode_id()),
    'Core/Utilities/DeepLinkParser.swift': (generate_xcode_id(), generate_xcode_id()),
    'App/AppDelegate.swift': (generate_xcode_id(), generate_xcode_id()),
    
    # In-App Notifications
    'Core/Services/NotificationService.swift': (generate_xcode_id(), generate_xcode_id()),
}

project_file = 'NaarsCars.xcodeproj/project.pbxproj'

with open(project_file, 'r') as f:
    content = f.read()

# Add PBXFileReference entries
file_ref_pattern = r'(/\* Begin PBXFileReference section \*/.*?)(/\* End PBXFileReference section \*/)'
match = re.search(file_ref_pattern, content, re.DOTALL)
if match:
    file_refs = match.group(1)
    for filepath, (file_id, build_id) in files_to_add.items():
        filename = filepath.split('/')[-1]
        file_ref_line = f'\t\t{file_id} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = "<group>"; }};\n'
        if file_id not in file_refs:
            file_refs = file_refs.rstrip() + '\n' + file_ref_line
    content = content[:match.start(1)] + file_refs + content[match.end(1):]

# Add PBXBuildFile entries
build_file_pattern = r'(/\* Begin PBXBuildFile section \*/.*?)(/\* End PBXBuildFile section \*/)'
match = re.search(build_file_pattern, content, re.DOTALL)
if match:
    build_files = match.group(1)
    for filepath, (file_id, build_id) in files_to_add.items():
        filename = filepath.split('/')[-1]
        build_file_line = f'\t\t{build_id} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_id} /* {filename} */; }};\n'
        if build_id not in build_files:
            build_files = build_files.rstrip() + '\n' + build_file_line
    content = content[:match.start(1)] + build_files + content[match.end(1):]

# Add to appropriate groups
# Services group
services_group_pattern = r'(/\* Services \*/.*?children = \(.*?)(\);.*?path = Services;)'
match = re.search(services_group_pattern, content, re.DOTALL)
if match:
    children = match.group(1)
    for filepath, (file_id, build_id) in files_to_add.items():
        if 'Services' in filepath:
            filename = filepath.split('/')[-1]
            child_line = f'\t\t\t\t{file_id} /* {filename} */,\n'
            if file_id not in children:
                children = children.rstrip() + '\n' + child_line
    content = content[:match.start(1)] + children + content[match.end(1):]

# Utilities group
utilities_group_pattern = r'(/\* Utilities \*/.*?children = \(.*?)(\);.*?path = Utilities;)'
match = re.search(utilities_group_pattern, content, re.DOTALL)
if match:
    children = match.group(1)
    for filepath, (file_id, build_id) in files_to_add.items():
        if 'Utilities' in filepath:
            filename = filepath.split('/')[-1]
            child_line = f'\t\t\t\t{file_id} /* {filename} */,\n'
            if file_id not in children:
                children = children.rstrip() + '\n' + child_line
    content = content[:match.start(1)] + children + content[match.end(1):]

# Messaging ViewModels group (create if needed)
messaging_vm_pattern = r'(/\* ViewModels \*/.*?path = ViewModels.*?Messaging.*?children = \(.*?)(\);.*?path = ViewModels;)'
# Try to find existing Messaging ViewModels group or create it
# For now, add to a generic location - this may need manual adjustment

# Messaging Views group
messaging_views_pattern = r'(/\* Views \*/.*?path = Views.*?Messaging.*?children = \(.*?)(\);.*?path = Views;)'
# Similar issue - may need manual group creation

# UI Components Messaging group
messaging_components_pattern = r'(/\* Messaging \*/.*?children = \(.*?)(\);.*?path = Messaging;)'
# May need to create this group

# App group
app_group_pattern = r'(ACDCBDF22F0B779600956D1C /\* App \*/ = \{.*?children = \(.*?)(\);.*?path = App;)'
match = re.search(app_group_pattern, content, re.DOTALL)
if match:
    children = match.group(1)
    for filepath, (file_id, build_id) in files_to_add.items():
        if 'App' in filepath:
            filename = filepath.split('/')[-1]
            child_line = f'\t\t\t\t{file_id} /* {filename} */,\n'
            if file_id not in children:
                children = children.rstrip() + '\n' + child_line
    content = content[:match.start(1)] + children + content[match.end(1):]

# Add to Sources build phase
sources_pattern = r'(ACDCBDC42F0B74F400956D1C /\* Sources \*/ = \{.*?files = \(.*?)(\);.*?runOnlyForDeploymentPostprocessing = 0;)'
match = re.search(sources_pattern, content, re.DOTALL)
if match:
    files = match.group(1)
    for filepath, (file_id, build_id) in files_to_add.items():
        filename = filepath.split('/')[-1]
        file_entry = f'\t\t\t\t{build_id} /* {filename} in Sources */,\n'
        if build_id not in files:
            files = files.rstrip() + '\n' + file_entry
    content = content[:match.start(1)] + files + content[match.end(1):]

with open(project_file, 'w') as f:
    f.write(content)

print("✅ Phase 2 files added to Xcode project")
print("⚠️  Note: Some files may need manual group organization in Xcode")




