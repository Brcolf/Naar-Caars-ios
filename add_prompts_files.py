#!/usr/bin/env python3
import re
import uuid

def generate_uuid():
    return uuid.uuid4().hex.upper()[:24]

# UUIDs generated
PROMPT_MODELS_FILE_ID = "D0A7626088EB4EEA92769463"
PROMPT_MODELS_BUILD_ID = "FB3400ECF3C94500BFA999EC"
PROMPT_QUEUE_FILE_ID = "1C74567335D747008AFF1A27"
PROMPT_QUEUE_BUILD_ID = "0C6159EB517240BB98866104"
PROMPT_QUEUE_TESTS_FILE_ID = "6BA83FF7E3554BDE8735846E"
PROMPT_QUEUE_TESTS_BUILD_ID = "F20784961007464C82C09B9F"
PROMPTS_GROUP_ID = "A5A425C88A4C4940ADE819AB"
TEST_PROMPTS_GROUP_ID = "325B966833854F288E03A425"

project_file = "NaarsCars/NaarsCars.xcodeproj/project.pbxproj"

with open(project_file, 'r') as f:
    content = f.read()

# Check if already added
if "PromptModels.swift" in content:
    print("⚠️  PromptModels.swift already in project")
else:
    # 1. Add PBXFileReference entries
    file_ref_pattern = r'(/\* Begin PBXFileReference section \*/.*?)(/\* End PBXFileReference section \*/)'
    match = re.search(file_ref_pattern, content, re.DOTALL)
    if match:
        file_refs = match.group(1)
        file_refs += f'\t\t{PROMPT_MODELS_FILE_ID} /* PromptModels.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PromptModels.swift; sourceTree = "<group>"; }};\n'
        file_refs += f'\t\t{PROMPT_QUEUE_FILE_ID} /* PromptQueue.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PromptQueue.swift; sourceTree = "<group>"; }};\n'
        file_refs += f'\t\t{PROMPT_QUEUE_TESTS_FILE_ID} /* PromptQueueTests.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PromptQueueTests.swift; sourceTree = "<group>"; }};\n'
        content = content[:match.start(1)] + file_refs + content[match.end(1):]
        print("✅ Added PBXFileReference entries")

    # 2. Add PBXBuildFile entries
    build_file_pattern = r'(/\* Begin PBXBuildFile section \*/.*?)(/\* End PBXBuildFile section \*/)'
    match = re.search(build_file_pattern, content, re.DOTALL)
    if match:
        build_files = match.group(1)
        build_files += f'\t\t{PROMPT_MODELS_BUILD_ID} /* PromptModels.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {PROMPT_MODELS_FILE_ID} /* PromptModels.swift */; }};\n'
        build_files += f'\t\t{PROMPT_QUEUE_BUILD_ID} /* PromptQueue.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {PROMPT_QUEUE_FILE_ID} /* PromptQueue.swift */; }};\n'
        build_files += f'\t\t{PROMPT_QUEUE_TESTS_BUILD_ID} /* PromptQueueTests.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {PROMPT_QUEUE_TESTS_FILE_ID} /* PromptQueueTests.swift */; }};\n'
        content = content[:match.start(1)] + build_files + content[match.end(1):]
        print("✅ Added PBXBuildFile entries")

    # 3. Add Prompts group to Features
    features_group_pattern = r'(ACDCBDF32F0B77A600956D1C /\* Features \*/ = \{[^}]*children = \(\n)([^)]+)(\);)'
    match = re.search(features_group_pattern, content, re.DOTALL)
    if match:
        children = match.group(2)
        if PROMPTS_GROUP_ID not in children:
            children = f'\t\t\t\t{PROMPTS_GROUP_ID} /* Prompts */,\n' + children
            content = content[:match.start(2)] + children + content[match.end(2):]
            print("✅ Added Prompts group to Features")
    
    # 4. Create Prompts group
    prompts_group_entry = f'\t\t{PROMPTS_GROUP_ID} /* Prompts */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{PROMPT_MODELS_FILE_ID} /* PromptModels.swift */,\n\t\t\t\t{PROMPT_QUEUE_FILE_ID} /* PromptQueue.swift */,\n\t\t\t);\n\t\t\tpath = Prompts;\n\t\t\tsourceTree = "<group>";\n\t\t}};\n'
    # Find a good place to insert (after Reviews group)
    reviews_group_pattern = r'(AC8197BA2F14C2C1003BB08B /\* Reviews \*/ = \{.*?\};\n)'
    match = re.search(reviews_group_pattern, content, re.DOTALL)
    if match:
        content = content[:match.end()] + prompts_group_entry + content[match.end():]
        print("✅ Created Prompts group")

    # 5. Add Prompts group to test Features
    test_features_group_pattern = r'(ACDCBE162F0B799D00956D1C /\* Features \*/ = \{[^}]*children = \(\n)([^)]+)(\);)'
    match = re.search(test_features_group_pattern, content, re.DOTALL)
    if match:
        children = match.group(2)
        if TEST_PROMPTS_GROUP_ID not in children:
            children = f'\t\t\t\t{TEST_PROMPTS_GROUP_ID} /* Prompts */,\n' + children
            content = content[:match.start(2)] + children + content[match.end(2):]
            print("✅ Added Prompts group to test Features")
    
    # 6. Create test Prompts group
    test_prompts_group_entry = f'\t\t{TEST_PROMPTS_GROUP_ID} /* Prompts */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{PROMPT_QUEUE_TESTS_FILE_ID} /* PromptQueueTests.swift */,\n\t\t\t);\n\t\t\tpath = Prompts;\n\t\t\tsourceTree = "<group>";\n\t\t}};\n'
    # Find a good place to insert (after Profile group in tests)
    test_profile_group_pattern = r'(ACDCBE192F0B79BD00956D1C /\* Profile \*/ = \{.*?\};\n)'
    match = re.search(test_profile_group_pattern, content, re.DOTALL)
    if match:
        content = content[:match.end()] + test_prompts_group_entry + content[match.end():]
        print("✅ Created test Prompts group")

    # 7. Add to Sources build phase (main target)
    sources_pattern = r'(ACDCBDC42F0B74F400956D1C /\* Sources \*/ = \{.*?files = \(\n)([^)]+)(\);)'
    match = re.search(sources_pattern, content, re.DOTALL)
    if match:
        files = match.group(2)
        files = f'\t\t\t\t{PROMPT_MODELS_BUILD_ID} /* PromptModels.swift in Sources */,\n\t\t\t\t{PROMPT_QUEUE_BUILD_ID} /* PromptQueue.swift in Sources */,\n' + files
        content = content[:match.start(2)] + files + content[match.end(2):]
        print("✅ Added to Sources build phase")

    # 8. Add to test Sources build phase
    test_sources_pattern = r'(ACDCBDD42F0B74F700956D1C /\* NaarsCarsTests \*/ = \{.*?/\* Sources \*/ = \{.*?files = \(\n)([^)]+)(\);)'
    match = re.search(test_sources_pattern, content, re.DOTALL)
    if match:
        files = match.group(2)
        files = f'\t\t\t\t{PROMPT_QUEUE_TESTS_BUILD_ID} /* PromptQueueTests.swift in Sources */,\n' + files
        content = content[:match.start(2)] + files + content[match.end(2):]
        print("✅ Added to test Sources build phase")

    with open(project_file, 'w') as f:
        f.write(content)
    
    print("✅ Successfully added all files to Xcode project")
