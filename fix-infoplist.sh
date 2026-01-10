#!/bin/bash
# Temporary workaround: Move Info.plist to exclude from fileSystemSynchronizedGroups
# Then update INFOPLIST_FILE path

echo "Moving Info.plist to Resources directory to exclude from fileSystemSynchronizedGroups..."
mv NaarsCars/NaarsCars/Info.plist NaarsCars/Resources/Info.plist

# Update INFOPLIST_FILE in project.pbxproj
sed -i '' 's|INFOPLIST_FILE = NaarsCars/NaarsCars/Info.plist|INFOPLIST_FILE = NaarsCars/Resources/Info.plist|g' NaarsCars/NaarsCars.xcodeproj/project.pbxproj

echo "✅ Info.plist moved to Resources/Info.plist"
echo "✅ Updated INFOPLIST_FILE path in project.pbxproj"
echo ""
echo "Now try building again. If issues persist, you may need to:"
echo "1. Open Xcode"
echo "2. Go to Target → Build Phases → Copy Bundle Resources"
echo "3. Remove Info.plist if it appears there"
