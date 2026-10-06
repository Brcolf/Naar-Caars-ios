#!/bin/bash
#
# design-token-audit.sh
# Read-only usage counts for the design tokens in NaarsCars/UI/Styles and
# Core/Utilities/Constants.swift, and for the raw values that bypass them.
# The numbers in Docs/design-system/README.md come from this script.
#
# Usage: scripts/design-token-audit.sh [color|type|layout|structure|all]
#

set -u
cd "$(dirname "$0")/../NaarsCars" || exit 1

DIRS="App Core Features UI"
g() { grep -rEoh "$1" --include='*.swift' $DIRS 2>/dev/null; }
n() { grep -rEo "$1" --include='*.swift' $DIRS 2>/dev/null | wc -l | tr -d ' '; }
f() { grep -rlE "$1" --include='*.swift' $DIRS 2>/dev/null | wc -l | tr -d ' '; }

audit_color() {
  echo "### Color tokens (occurrences / files)"
  for t in naarsPrimary naarsAccent naarsSuccess naarsWarning naarsError favorAccent rideAccent 'naarsBackground\b' naarsBackgroundSecondary naarsCardBackground naarsTextPrimary naarsTextSecondary naarsTextTertiary naarsDivider naarsBorder naarsDisabled naarsOverlay; do
    echo "$t $(n "\.$t") / $(f "\.$t")"
  done
  echo; echo "### SwiftUI named colors written directly"
  g "(Color)?\.(red|blue|green|orange|yellow|purple|pink|gray|black|white|primary|secondary|accentColor|teal|indigo|mint|cyan|brown|clear)\b(\.opacity\([0-9.]+\))?" \
    | sed -E 's/^Color//; s/\.opacity\([0-9.]+\)/.opacity(x)/' | sort | uniq -c | sort -rn | head -40
  echo; echo "### UIKit system colors written directly"
  g "(Color\(UIColor\.|Color\(uiColor: *\.|Color\(\.|UIColor\.|: *\.)(system[A-Z][A-Za-z0-9]+|label|secondaryLabel|tertiaryLabel|quaternaryLabel|separator|opaqueSeparator|placeholderText|tertiarySystemFill|secondarySystemFill|quaternarySystemFill)\b" \
    | sed -E 's/^(Color\(UIColor\.|Color\(uiColor: *\.|Color\(\.|UIColor\.|: *\.)//' | sort | uniq -c | sort -rn | head -40
  echo; echo "### Hex or RGB literals outside ColorTheme.swift (expect none)"
  grep -rEn "hex: *\"#?[0-9A-Fa-f]{3,8}\"|Color\(red:|UIColor\(red:|UIColor\(white:|Color\(white:" --include='*.swift' $DIRS | grep -v "UI/Styles/ColorTheme.swift" | head -40
  echo; echo "### Opacity steps applied to tokens"
  g "\.(naars[A-Za-z]+|favorAccent|rideAccent)\.opacity\([0-9.]+\)" | sort | uniq -c | sort -rn | head -40
}

audit_type() {
  echo "### Font tokens"
  g "\.naars(LargeTitle|Title2|Title3|Title|Headline|Body|Callout|Subheadline|Footnote|Caption)\b" | sort | uniq -c | sort -rn
  echo; echo "### Raw system text styles"
  g "\.font\(\.(largeTitle|title3|title2|title|headline|subheadline|body|callout|footnote|caption2|caption)\b" | sort | uniq -c | sort -rn
  echo; echo "### Fixed sizes: $(n '\.system\(size:') calls in $(f '\.system\(size:') files"
  g "\.system\(size: *[0-9.]+" | grep -Eo "[0-9.]+$" | sort -n | uniq -c
  echo; echo "### UIKit fonts"
  g "UIFont\.(preferredFont\(forTextStyle: *\.[a-zA-Z0-9]+|systemFont\(ofSize: *[0-9.]+(, *weight: *\.[a-z]+)?|boldSystemFont\(ofSize: *[0-9.]+)|\.preferredFont\(forTextStyle: *\.[a-zA-Z0-9]+" | sort | uniq -c | sort -rn | head -20
  echo; echo "### Designs, custom faces, weights"
  g "design: *\.[a-z]+|Font\.custom\(\"[^\"]+\"|\.fontDesign\(\.[a-z]+\)" | sort | uniq -c | sort -rn
  g "\.fontWeight\(\.[a-z]+\)|\.weight\(\.[a-z]+\)|\.bold\(\)" | sort | uniq -c | sort -rn
  echo; echo "### Dynamic Type handling"
  echo "isAccessibilitySize branches: $(n 'isAccessibilitySize')   @ScaledMetric: $(n '@ScaledMetric')   minimumScaleFactor: $(n 'minimumScaleFactor')"
}

audit_layout() {
  echo "### Spacing tokens"
  g "Constants\.Spacing\.(xs|sm|md|lg|xl)" | sort | uniq -c | sort -rn
  echo; echo "### Literal padding values"
  g "\.padding\((\.[a-zA-Z]+, *|\[[^]]+\], *)?[0-9.]+\)" | grep -Eo "[0-9.]+\)$" | tr -d ')' | sort -n | uniq -c | sort -rn | head -30
  echo "bare .padding(): $(n '\.padding\(\)')   .padding(.edge) with the default amount: $(n '\.padding\(\.[a-z]+\)')"
  echo; echo "### Literal stack spacing"
  g "(VStack|HStack|LazyVStack|LazyHStack|LazyVGrid|Grid)\([^)]*spacing: *[0-9.]+" | grep -Eo "spacing: *[0-9.]+" | sort | uniq -c | sort -rn | head -25
  echo; echo "### Corner radii"
  g "(cornerRadius\(|cornerRadius: *|cornerRadius *= *)[0-9.]+" | grep -Eo "[0-9.]+$" | sort -n | uniq -c | sort -rn
  echo "continuous: $(n 'style: *\.continuous')  Capsule: $(n 'Capsule\(')  Circle: $(n 'Circle\(')  concentric: $(n 'ConcentricRectangle|ContainerRelativeShape|containerConcentric')"
  echo; echo "### Shadows"
  g "\.shadow\([^)]*\)" | sed -E 's/ +/ /g' | sort | uniq -c | sort -rn | head -30
  echo; echo "### Materials and Liquid Glass"
  g "\.(ultraThinMaterial|thinMaterial|regularMaterial|thickMaterial|ultraThickMaterial)\b|glassEffect|GlassEffectContainer|buttonStyle\(\.glass[A-Za-z]*\)|UIGlassEffect|UIBlurEffect\(style: *\.[A-Za-z]+|backgroundExtensionEffect|tabBarMinimizeBehavior|scrollEdgeEffectStyle|tabViewBottomAccessory" | sort | uniq -c | sort -rn
  echo; echo "### Gradients"
  g "LinearGradient|RadialGradient|AngularGradient|MeshGradient|\.gradient\b" | sort | uniq -c
  echo; echo "### Animation"
  g "Constants\.Animation\.(short|medium|long)|\.(easeInOut|easeIn|easeOut|linear)\(duration: *[0-9.]+\)|\.spring\([^)]*\)|\.(snappy|bouncy|smooth|interactiveSpring)\b(\([^)]*\))?|withAnimation *\{" | sort | uniq -c | sort -rn | head -45
  echo; echo "### Haptics"
  g "HapticManager\.[a-zA-Z]+" | sort | uniq -c | sort -rn | head
  echo "UIKit feedback generators outside HapticManager.swift: $(grep -rEo 'UIImpactFeedbackGenerator|UINotificationFeedbackGenerator|UISelectionFeedbackGenerator' --include='*.swift' $DIRS | grep -v 'HapticManager.swift' | wc -l | tr -d ' ')"
}

audit_structure() {
  echo "### Containers, controls and shared components (occurrences / files)"
  for p in 'NavigationStack' 'TabView' '\bList\b *[({]' '\bForm\b *[({]' 'ScrollView' '\.sheet\(' '\.fullScreenCover\(' '\.alert\(' '\.confirmationDialog\(' '\.toolbar *[({]' '\.searchable\(' '\.refreshable' '\.swipeActions' '\.navigationTitle\(' 'navigationBarTitleDisplayMode\(\.inline\)' 'navigationBarTitleDisplayMode\(\.large\)' '\.presentationDetents' 'Picker\(' 'pickerStyle\(\.segmented' 'Toggle\(' 'Menu *[({]' 'ProgressView' 'TextField\(' 'NaarsTextField\(' 'PrimaryButton\(' 'SecondaryButton\(' 'ClaimButton\(' 'EmptyStateView\(' 'ErrorView\(' 'ErrorBanner\(' 'LoadingView\(' 'SkeletonView\(' 'AvatarView\(' 'NotificationBadge\(' 'ToastView\(' 'RideCard\(' 'FavorCard\(' 'buttonStyle\(\.borderedProminent\)' 'buttonStyle\(\.bordered\)' 'buttonStyle\(\.plain\)' 'Button\(' 'Image\(systemName:' 'accessibilityLabel\(' 'accessibilityIdentifier\(' 'accessibilityHint\(' '#Preview'; do
    echo "$(n "$p") / $(f "$p")  $p"
  done
  echo; echo "### List styles and sheet detents"
  g "\.listStyle\(\.[a-zA-Z]+\)|\.presentationDetents\(\[[^]]*\]\)" | sort | uniq -c | sort -rn
  echo; echo "### SF Symbols: $(g 'systemName: *"[a-z0-9.]+"' | sort -u | wc -l | tr -d ' ') distinct; top 40"
  g 'systemName: *"[a-z0-9.]+"' | sed -E 's/systemName: *//' | sort | uniq -c | sort -rn | head -40
  echo; echo "### Image assets referenced"
  grep -rEoh 'Image\("[^"]+"\)|UIImage\(named: *"[^"]+"\)|customImage: *"[^"]+"' --include='*.swift' $DIRS | sort | uniq -c | sort -rn
}

case "${1:-all}" in
  color) audit_color ;;
  type) audit_type ;;
  layout) audit_layout ;;
  structure) audit_structure ;;
  all) audit_color; echo; audit_type; echo; audit_layout; echo; audit_structure ;;
  *) echo "Usage: $0 [color|type|layout|structure|all]"; exit 2 ;;
esac
