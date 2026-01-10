#!/bin/bash
# Script to clear Xcode caches and resolve Info.plist conflicts

echo "🧹 Clearing Xcode caches..."

# Clean DerivedData
rm -rf ~/Library/Developer/Xcode/DerivedData/NaarsCars-*

# Clean Module Cache
rm -rf ~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex

# Clean Archives
rm -rf ~/Library/Developer/Xcode/Archives/*/NaarsCars*

echo "✅ Xcode caches cleared"
echo ""
echo "Next steps:"
echo "1. Close Xcode completely (Cmd+Q)"
echo "2. Reopen the project"
echo "3. Product → Clean Build Folder (Shift+Cmd+K)"
echo "4. Try building again"

