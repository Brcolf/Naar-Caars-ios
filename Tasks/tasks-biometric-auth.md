# Tasks: Biometric Authentication

Based on `prd-biometric-auth.md`

## Relevant Files

### Source Files
- `Core/Services/BiometricService.swift` - Face ID/Touch ID handling
- `Features/Settings/Views/SecuritySettingsView.swift` - Enable/disable biometric
- `Features/Authentication/Views/BiometricUnlockView.swift` - Unlock screen

### Test Files
- `NaarsCarsTests/Core/Services/BiometricServiceTests.swift`

## Notes

- Optional security feature
- Uses LocalAuthentication framework
- Requires Info.plist key for Face ID
- 🧪 items are QA tasks | 🔒 CHECKPOINT items are mandatory gates

## Tasks

- [ ] 0.0 Create feature branch: `git checkout -b feature/biometric-auth`

- [ ] 1.0 Configure biometric capability
  - [ ] 1.1 Import LocalAuthentication framework
  - [ ] 1.2 Verify NSFaceIDUsageDescription in Info.plist

- [ ] 2.0 Implement BiometricService
  - [ ] 2.1 Create BiometricService.swift
  - [ ] 2.2 Implement canUseBiometrics() checking availability
  - [ ] 2.3 Implement biometricType() returning faceID, touchID, or none
  - [ ] 2.4 Implement authenticate() using LAContext
  - [ ] 2.5 Store biometric enabled preference in UserDefaults
  - [ ] 2.6 🧪 Write BiometricServiceTests.testCanUseBiometrics
  - [ ] 2.7 🧪 Write BiometricServiceTests.testAuthenticate_Success

### 🔒 CHECKPOINT: QA-BIOMETRIC-001
> Run: `./QA/Scripts/checkpoint.sh biometric-001`
> Guide: QA/CHECKPOINT-GUIDE.md
> Verify: BiometricService tests pass
> Must pass before continuing

- [ ] 3.0 Build Security Settings View
  - [ ] 3.1 Create SecuritySettingsView.swift
  - [ ] 3.2 Add Toggle for biometric unlock
  - [ ] 3.3 Show appropriate label (Face ID / Touch ID)
  - [ ] 3.4 Require authentication to enable
  - [ ] 3.5 Save preference on toggle

- [ ] 4.0 Build Biometric Unlock View
  - [ ] 4.1 Create BiometricUnlockView.swift
  - [ ] 4.2 Show lock icon and app name
  - [ ] 4.3 Prompt for biometric on appear
  - [ ] 4.4 Add "Use Password" fallback button
  - [ ] 4.5 Navigate to main app on success

- [ ] 5.0 Integrate unlock flow
  - [ ] 5.1 Check biometric preference on app launch
  - [ ] 5.2 If enabled, show BiometricUnlockView
  - [ ] 5.3 Track app background/foreground
  - [ ] 5.4 Re-prompt after returning from background

- [ ] 6.0 Verify biometric auth
  - [ ] 6.1 Test on device with Face ID
  - [ ] 6.2 Test on device with Touch ID
  - [ ] 6.3 Test fallback to password
  - [ ] 6.4 Test enable/disable toggle
  - [ ] 6.5 Commit: "feat: implement biometric authentication"

### 🔒 CHECKPOINT: QA-BIOMETRIC-FINAL
> Run: `./QA/Scripts/checkpoint.sh biometric-final`
> Guide: QA/CHECKPOINT-GUIDE.md
> Biometric auth tests must pass
