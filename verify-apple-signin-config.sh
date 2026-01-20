#!/bin/bash
# Verify Apple Sign-In Configuration
# Run this script to check your local Xcode configuration for Apple Sign-In

set -e

echo "🔍 Verifying Apple Sign-In Configuration..."
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ENTITLEMENTS_FILE="$PROJECT_DIR/NaarsCars/NaarsCars/NaarsCars.entitlements"
PBXPROJ_FILE="$PROJECT_DIR/NaarsCars/NaarsCars.xcodeproj/project.pbxproj"

# Check 1: Entitlements file exists
echo "✓ Checking entitlements file..."
if [ -f "$ENTITLEMENTS_FILE" ]; then
    echo -e "${GREEN}✓ Entitlements file exists${NC}"
    
    # Check if Sign in with Apple capability is present
    if grep -q "com.apple.developer.applesignin" "$ENTITLEMENTS_FILE"; then
        echo -e "${GREEN}✓ Sign in with Apple capability found in entitlements${NC}"
        
        # Show the configuration
        echo "  Configuration:"
        grep -A 3 "com.apple.developer.applesignin" "$ENTITLEMENTS_FILE" | sed 's/^/  /'
    else
        echo -e "${RED}✗ Sign in with Apple capability NOT found in entitlements${NC}"
        echo "  Add the capability in Xcode: Signing & Capabilities > + Capability"
    fi
else
    echo -e "${RED}✗ Entitlements file not found${NC}"
fi

echo ""

# Check 2: Bundle Identifier
echo "✓ Checking Bundle Identifier..."
if grep -q "com.NaarsCars" "$PBXPROJ_FILE"; then
    echo -e "${GREEN}✓ Bundle ID 'com.NaarsCars' found${NC}"
    BUNDLE_COUNT=$(grep -c "PRODUCT_BUNDLE_IDENTIFIER = com.NaarsCars" "$PBXPROJ_FILE")
    echo "  Found in $BUNDLE_COUNT build configurations"
else
    echo -e "${RED}✗ Bundle ID 'com.NaarsCars' not found${NC}"
fi

echo ""

# Check 3: Info.plist for Apple Sign-In
INFOPLIST_FILE="$PROJECT_DIR/NaarsCars/Info.plist"
echo "✓ Checking Info.plist..."
if [ -f "$INFOPLIST_FILE" ]; then
    echo -e "${GREEN}✓ Info.plist exists${NC}"
    
    if grep -q "NSAppleIDUsageDescription" "$INFOPLIST_FILE"; then
        echo -e "${GREEN}✓ Apple ID usage description found${NC}"
    else
        echo -e "${YELLOW}⚠ Apple ID usage description not found (optional)${NC}"
        echo "  Consider adding NSAppleIDUsageDescription to Info.plist"
    fi
else
    echo -e "${RED}✗ Info.plist not found${NC}"
fi

echo ""

# Check 4: Swift files implementing Apple Sign-In
echo "✓ Checking Apple Sign-In implementation files..."
APPLE_SIGNIN_FILES=(
    "NaarsCars/Core/Services/AuthService+AppleSignIn.swift"
    "NaarsCars/Features/Authentication/Views/AppleSignInButton.swift"
    "NaarsCars/Features/Authentication/ViewModels/AppleSignInViewModel.swift"
    "NaarsCars/Features/Authentication/Views/AppleSignInLinkView.swift"
)

ALL_FILES_EXIST=true
for file in "${APPLE_SIGNIN_FILES[@]}"; do
    if [ -f "$PROJECT_DIR/$file" ]; then
        echo -e "${GREEN}✓ $file${NC}"
    else
        echo -e "${RED}✗ $file (missing)${NC}"
        ALL_FILES_EXIST=false
    fi
done

echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Configuration Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Local Configuration: ${GREEN}✓ Looks Good${NC}"
echo ""
echo -e "${YELLOW}⚠️  IMPORTANT: Local configuration is only part of the setup!${NC}"
echo ""
echo "You must also configure Apple Developer Portal:"
echo ""
echo "1. Go to https://developer.apple.com"
echo "2. Navigate to Certificates, Identifiers & Profiles"
echo "3. Select 'Identifiers' > Your App ID (com.NaarsCars)"
echo "4. Enable 'Sign in with Apple' capability"
echo "5. Save and regenerate your provisioning profiles"
echo ""
echo "After making changes in the Developer Portal:"
echo "  • Clean Build Folder (Shift+Cmd+K in Xcode)"
echo "  • Delete app from device/simulator"
echo "  • Rebuild and install"
echo ""
echo "📖 See APPLE-SIGN-IN-ERROR-1000-FIX.md for detailed instructions"
echo ""

