#!/usr/bin/env bash
#
# ConvosCore Test Runner
# Runs tests on iOS Simulator (required because ConvosCore is iOS-only)
#

set -e
set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}📦 Running ConvosCore Tests${NC}"
echo ""

# Show environment
echo "Xcode version:"
xcodebuild -version
echo ""
echo "Swift version:"
swift --version
echo ""

# List available simulators (optional, for debugging)
if [ "${VERBOSE:-0}" = "1" ]; then
  echo "Available iOS Simulators:"
  xcrun simctl list devices available iOS | grep iPhone
  echo ""
fi

# Run tests on iOS Simulator
echo -e "${YELLOW}🧪 Running tests on iOS Simulator...${NC}"
echo ""

# Find first available iPhone simulator dynamically
SIMULATOR_ID=$(xcrun simctl list devices available iPhone | grep -m 1 "iPhone" | sed -n 's/.* (\(.*\)).*/\1/p')

if [ -z "$SIMULATOR_ID" ]; then
  echo -e "${RED}❌ No iPhone simulator found${NC}"
  echo "Please install an iPhone simulator via Xcode"
  exit 1
fi

echo "Using simulator: $(xcrun simctl list devices | grep "$SIMULATOR_ID" | sed 's/^[[:space:]]*//')"
echo ""

xcodebuild test \
  -scheme ConvosCore \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -enableCodeCoverage YES \
  -skipPackagePluginValidation \
  -resultBundlePath TestResults.xcresult

TEST_EXIT_CODE=$?

echo ""

if [ $TEST_EXIT_CODE -ne 0 ]; then
  echo -e "${RED}❌ Tests failed with exit code $TEST_EXIT_CODE${NC}"
  exit $TEST_EXIT_CODE
fi

echo -e "${GREEN}✅ All tests passed!${NC}"
echo ""
echo "Test results saved to: TestResults.xcresult"
echo ""
echo "To view detailed results:"
echo "  open TestResults.xcresult"
