#!/bin/bash
echo "=========================================="
echo "Verifying All Critical Files"
echo "=========================================="
echo ""
PROJECT_ROOT="/Users/bcolf/Documents/naars-cars-ios/NaarsCars"

FILES=(
    "UI/Components/Buttons/PrimaryButton.swift"
    "Core/Utilities/Validators.swift"
    "Core/Utilities/AppError.swift"
    "Core/Utilities/InviteCodeGenerator.swift"
    "Features/Authentication/Views/SignupDetailsView.swift"
    "Features/Authentication/Views/SignupInviteCodeView.swift"
    "Features/Authentication/Views/LoginView.swift"
    "Features/Authentication/Views/PasswordResetView.swift"
    "Features/Authentication/Views/PendingApprovalView.swift"
)

ALL_EXIST=true
for file in "${FILES[@]}"; do
    full_path="$PROJECT_ROOT/$file"
    if [ -f "$full_path" ]; then
        echo "✅ $file"
    else
        echo "❌ MISSING: $file"
        ALL_EXIST=false
    fi
done

echo ""
if [ "$ALL_EXIST" = true ]; then
    echo "✅ All files exist at correct locations"
    echo ""
    echo "Next: Refresh Xcode file system synchronization"
    echo "  1. Close Xcode (⌘Q)"
    echo "  2. Reopen project"
    echo "  3. Wait for indexing"
    echo "  4. Build (⌘B)"
else
    echo "❌ Some files are missing - copy from worktree"
fi
