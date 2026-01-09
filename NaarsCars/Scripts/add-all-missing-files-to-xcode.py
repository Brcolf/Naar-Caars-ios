#!/usr/bin/env python3
"""
Add all missing Phase 1 and Phase 2 files to Xcode project
This script adds files that exist on disk but aren't in the Xcode project
"""

import re
import uuid
import os

def generate_xcode_id():
    """Generate a 24-character hex ID for Xcode"""
    return ''.join([f'{uuid.uuid4().hex[i:i+2].upper()}' for i in range(0, 24, 2)])

# All missing files with their full paths
missing_files = [
    # App
    'App/AppDelegate.swift',
    
    # Core Models
    'Core/Models/RequestQA.swift',
    
    # Core Services
    'Core/Services/ClaimService.swift',
    'Core/Services/ConversationService.swift',
    'Core/Services/FavorService.swift',
    'Core/Services/MessageService.swift',
    'Core/Services/NotificationService.swift',
    'Core/Services/PushNotificationService.swift',
    'Core/Services/RideService.swift',
    
    # Core Utilities
    'Core/Utilities/Constants.swift',
    'Core/Utilities/DeepLinkParser.swift',
    'Core/Utilities/DeviceIdentifier.swift',
    'Core/Utilities/Logger.swift',
    
    # Claiming
    'Features/Claiming/ViewModels/ClaimViewModel.swift',
    'Features/Claiming/Views/ClaimSheet.swift',
    'Features/Claiming/Views/CompleteSheet.swift',
    'Features/Claiming/Views/PhoneRequiredSheet.swift',
    'Features/Claiming/Views/UnclaimSheet.swift',
    
    # Favors
    'Features/Favors/ViewModels/CreateFavorViewModel.swift',
    'Features/Favors/ViewModels/FavorDetailViewModel.swift',
    'Features/Favors/ViewModels/FavorsDashboardViewModel.swift',
    'Features/Favors/Views/CreateFavorView.swift',
    'Features/Favors/Views/EditFavorView.swift',
    'Features/Favors/Views/FavorDetailView.swift',
    'Features/Favors/Views/FavorsDashboardView.swift',
    
    # Messaging
    'Features/Messaging/ViewModels/ConversationDetailViewModel.swift',
    'Features/Messaging/ViewModels/ConversationsListViewModel.swift',
    'Features/Messaging/Views/ConversationDetailView.swift',
    'Features/Messaging/Views/ConversationsListView.swift',
    
    # Rides
    'Features/Rides/ViewModels/CreateRideViewModel.swift',
    'Features/Rides/ViewModels/RideDetailViewModel.swift',
    'Features/Rides/ViewModels/RidesDashboardViewModel.swift',
    'Features/Rides/Views/CreateRideView.swift',
    'Features/Rides/Views/EditRideView.swift',
    'Features/Rides/Views/RideDetailView.swift',
    'Features/Rides/Views/RidesDashboardView.swift',
    
    # Test Files
    'NaarsCarsTests/Core/Services/ClaimServiceTests.swift',
    'NaarsCarsTests/Core/Services/FavorServiceTests.swift',
    'NaarsCarsTests/Core/Services/RideServiceTests.swift',
    'NaarsCarsTests/Features/Claiming/ClaimViewModelTests.swift',
    'NaarsCarsTests/Features/Favors/CreateFavorViewModelTests.swift',
    'NaarsCarsTests/Features/Favors/FavorsDashboardViewModelTests.swift',
    'NaarsCarsTests/Features/Rides/CreateRideViewModelTests.swift',
    'NaarsCarsTests/Features/Rides/RideDetailViewModelTests.swift',
    'NaarsCarsTests/Features/Rides/RidesDashboardViewModelTests.swift',
    'NaarsCarsUITests/NaarsCarsUITests.swift',
    'NaarsCarsUITests/NaarsCarsUITestsLaunchTests.swift',
    
    # UI Components
    'UI/Components/Buttons/ClaimButton.swift',
    'UI/Components/Cards/FavorCard.swift',
    'UI/Components/Cards/RideCard.swift',
    'UI/Components/Common/RequestQAView.swift',
    'UI/Components/Feedback/SkeletonConversationRow.swift',
    'UI/Components/Feedback/SkeletonFavorCard.swift',
    'UI/Components/Feedback/SkeletonLeaderboardRow.swift',
    'UI/Components/Feedback/SkeletonMessageRow.swift',
    'UI/Components/Feedback/SkeletonRideCard.swift',
    'UI/Components/Feedback/SkeletonView.swift',
    'UI/Components/Messaging/MessageBubble.swift',
    'UI/Components/Messaging/MessageInputBar.swift',
    
    # Scripts
    'Scripts/obfuscate.swift',
]

# Generate IDs for all files
file_ids = {}
for filepath in missing_files:
    file_ids[filepath] = (generate_xcode_id(), generate_xcode_id())

project_file = 'NaarsCars.xcodeproj/project.pbxproj'

with open(project_file, 'r') as f:
    content = f.read()

# Add PBXFileReference entries
file_ref_pattern = r'(/\* Begin PBXFileReference section \*/.*?)(/\* End PBXFileReference section \*/)'
match = re.search(file_ref_pattern, content, re.DOTALL)
if match:
    file_refs = match.group(1)
    for filepath, (file_id, build_id) in file_ids.items():
        filename = os.path.basename(filepath)
        file_ref_line = f'\t\t{file_id} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = "<group>"; }};\n'
        if file_id not in file_refs:
            file_refs = file_refs.rstrip() + '\n' + file_ref_line
    content = content[:match.start(1)] + file_refs + content[match.end(1):]

# Add PBXBuildFile entries
build_file_pattern = r'(/\* Begin PBXBuildFile section \*/.*?)(/\* End PBXBuildFile section \*/)'
match = re.search(build_file_pattern, content, re.DOTALL)
if match:
    build_files = match.group(1)
    for filepath, (file_id, build_id) in file_ids.items():
        filename = os.path.basename(filepath)
        build_file_line = f'\t\t{build_id} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_id} /* {filename} */; }};\n'
        if build_id not in build_files:
            build_files = build_files.rstrip() + '\n' + build_file_line
    content = content[:match.start(1)] + build_files + content[match.end(1):]

# Add to Sources build phase (main target)
sources_pattern = r'(ACDCBDC42F0B74F400956D1C /\* Sources \*/ = \{.*?files = \(.*?)(\);.*?runOnlyForDeploymentPostprocessing = 0;)'
match = re.search(sources_pattern, content, re.DOTALL)
if match:
    files = match.group(1)
    for filepath, (file_id, build_id) in file_ids.items():
        # Only add source files, not test files
        if 'Tests' not in filepath and 'UITests' not in filepath:
            filename = os.path.basename(filepath)
            file_entry = f'\t\t\t\t{build_id} /* {filename} in Sources */,\n'
            if build_id not in files:
                files = files.rstrip() + '\n' + file_entry
    content = content[:match.start(1)] + files + content[match.end(1):]

# Add to Test Sources build phase
test_sources_pattern = r'(ACDCBDD12F0B74F700956D1C /\* Sources \*/ = \{.*?files = \(.*?)(\);.*?runOnlyForDeploymentPostprocessing = 0;)'
match = re.search(test_sources_pattern, content, re.DOTALL)
if match:
    files = match.group(1)
    for filepath, (file_id, build_id) in file_ids.items():
        if 'Tests' in filepath or 'UITests' in filepath:
            filename = os.path.basename(filepath)
            file_entry = f'\t\t\t\t{build_id} /* {filename} in Sources */,\n'
            if build_id not in files:
                files = files.rstrip() + '\n' + file_entry
    content = content[:match.start(1)] + files + content[match.end(1):]

# Note: File groups are handled by PBXFileSystemSynchronizedRootGroup
# Files should be auto-discovered, but we're adding explicit references
# for files that aren't being picked up

with open(project_file, 'w') as f:
    f.write(content)

print(f"✅ Added {len(missing_files)} missing files to Xcode project")
print("⚠️  Note: Since project uses file system sync, files should auto-discover.")
print("   If files still don't appear, open Xcode and refresh the project.")




