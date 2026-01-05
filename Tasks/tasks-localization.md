# Tasks: Localization

Based on `prd-localization.md`

## Relevant Files

### Source Files
- `Resources/Localizable.strings` - English strings
- `Resources/es.lproj/Localizable.strings` - Spanish strings
- `Core/Utilities/LocalizationManager.swift` - Localization helpers

### Test Files
- `NaarsCarsTests/Core/Utilities/LocalizationTests.swift`

## Notes

- Start with English, structure for Spanish
- Use String(localized:) for all user-facing text
- 🧪 items are QA tasks | 🔒 CHECKPOINT items are mandatory gates

## Tasks

- [ ] 0.0 Create feature branch: `git checkout -b feature/localization`

- [ ] 1.0 Set up localization structure
  - [ ] 1.1 Create Resources folder if not exists
  - [ ] 1.2 Create Localizable.strings for English (Base)
  - [ ] 1.3 Add project to localization in Xcode
  - [ ] 1.4 Create Spanish localization folder

- [ ] 2.0 Extract all strings
  - [ ] 2.1 Audit all views for hardcoded strings
  - [ ] 2.2 Add strings to Localizable.strings
  - [ ] 2.3 Replace hardcoded text with String(localized:)
  - [ ] 2.4 Use meaningful keys (e.g., "login.button.submit")

### 🔒 CHECKPOINT: QA-LOCALIZATION-001
> Run: `./QA/Scripts/checkpoint.sh localization-001`
> Guide: QA/CHECKPOINT-GUIDE.md
> Verify: No hardcoded strings, app builds
> Must pass before continuing

- [ ] 3.0 Create LocalizationManager
  - [ ] 3.1 Create LocalizationManager.swift
  - [ ] 3.2 Add method for pluralization
  - [ ] 3.3 Add method for date/number formatting
  - [ ] 3.4 🧪 Write LocalizationTests.testPluralization

- [ ] 4.0 Add Spanish translations
  - [ ] 4.1 Create es.lproj/Localizable.strings
  - [ ] 4.2 Translate all strings to Spanish
  - [ ] 4.3 Handle plural forms correctly

- [ ] 5.0 Test localization
  - [ ] 5.1 Test English in simulator
  - [ ] 5.2 Test Spanish in simulator (change language)
  - [ ] 5.3 Check for truncation issues
  - [ ] 5.4 Verify date/number formatting
  - [ ] 5.5 Commit: "feat: implement localization"

### 🔒 CHECKPOINT: QA-LOCALIZATION-FINAL
> Run: `./QA/Scripts/checkpoint.sh localization-final`
> Guide: QA/CHECKPOINT-GUIDE.md
> Localization tests must pass
