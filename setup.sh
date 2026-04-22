#!/bin/bash
# ─────────────────────────────────────────────────────────────────
# setup.sh  —  Run this ONCE in the Lightning AI Studio terminal
# before launching the Streamlit app.
#
#   bash setup.sh
#
# ─────────────────────────────────────────────────────────────────

set -e

echo "▶  Installing system dependencies..."
sudo apt-get update -qq

# ── Install ALL Chrome runtime dependencies first ──
# (Missing these causes the 'error while loading shared libraries' errors)
echo "   Installing Chrome runtime libraries..."
sudo apt-get install -y \
    wget curl unzip \
    libnspr4 libnss3 libnss3-dev \
    libasound2 libatk-bridge2.0-0 libatk1.0-0 \
    libcups2 libdbus-1-3 libdrm2 libgbm1 libglib2.0-0 \
    libgtk-3-0 libpango-1.0-0 libx11-6 libxcb1 \
    libxcomposite1 libxdamage1 libxext6 libxfixes3 \
    libxrandr2 libxshmfence1 xdg-utils fonts-liberation \
    libgl1-mesa-glx libgl1 2>/dev/null || true

# Fix any broken installs from previous attempts
sudo apt --fix-broken install -y 2>/dev/null || true

# ── Install Google Chrome via .deb (bypasses apt repo conflicts) ──
if ! command -v google-chrome-stable &>/dev/null && ! command -v google-chrome &>/dev/null; then
    echo "   Downloading Google Chrome .deb..."
    wget -q -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb

    echo "   Installing Google Chrome..."
    # Use dpkg + fix-broken to handle dependency resolution
    sudo dpkg -i /tmp/chrome.deb 2>/dev/null || true
    sudo apt-get -f install -y 2>/dev/null || true
    rm -f /tmp/chrome.deb

    if command -v google-chrome-stable &>/dev/null; then
        echo "   ✅ Google Chrome installed."
    else
        echo "   ❌ Chrome install failed — cannot continue."
        exit 1
    fi
else
    echo "   Google Chrome already installed."
fi

# ── Verify Chrome works ──
CHROME_BIN=""
for bin in google-chrome-stable google-chrome; do
    if command -v "$bin" &>/dev/null; then
        CHROME_BIN="$bin"
        break
    fi
done

CHROME_VERSION=$("$CHROME_BIN" --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+\.\d+')
if [ -z "$CHROME_VERSION" ]; then
    echo "❌ Chrome binary found but cannot run — missing shared libraries."
    echo "   Run: ldd \$(which google-chrome-stable) | grep 'not found'"
    exit 1
fi
CHROME_MAJOR=$(echo "$CHROME_VERSION" | cut -d. -f1)
echo "✅ Chrome: $CHROME_VERSION (major $CHROME_MAJOR)"

# ── Download matching chromedriver directly from Google ──
# We NEVER use chromium-chromedriver from apt — it conflicts with snap on Lightning AI.
if ! command -v chromedriver &>/dev/null; then
    echo "   Downloading matching chromedriver for Chrome $CHROME_VERSION ..."
    sudo apt-get install -y unzip 2>/dev/null || true

    DRIVER_URL=""
    if [ "$CHROME_MAJOR" -ge 115 ] 2>/dev/null; then
        # Chrome 115+ — use Chrome for Testing JSON API
        DRIVER_URL=$(wget -qO- "https://googlechromelabs.github.io/chrome-for-testing/known-good-versions-with-downloads.json" \
          | python3 -c "
import sys, json
data = json.load(sys.stdin)
major = '$CHROME_MAJOR'
best = None
for v in data['versions']:
    if v['version'].startswith(major + '.'):
        for d in v.get('downloads', {}).get('chromedriver', []):
            if d['platform'] == 'linux64':
                best = d['url']
if best:
    print(best)
" 2>/dev/null)
    else
        # Chrome <115 — use old storage endpoint
        DRIVER_VERSION=$(wget -qO- "https://chromedriver.storage.googleapis.com/LATEST_RELEASE_${CHROME_MAJOR}" 2>/dev/null)
        if [ -n "$DRIVER_VERSION" ]; then
            DRIVER_URL="https://chromedriver.storage.googleapis.com/${DRIVER_VERSION}/chromedriver_linux64.zip"
        fi
    fi

    if [ -n "$DRIVER_URL" ]; then
        echo "   Fetching: $DRIVER_URL"
        wget -q -O /tmp/chromedriver.zip "$DRIVER_URL"
        cd /tmp && unzip -o chromedriver.zip -d chromedriver_extracted && cd -
        EXTRACTED=$(find /tmp/chromedriver_extracted -name 'chromedriver' -type f 2>/dev/null | head -1)
        if [ -n "$EXTRACTED" ]; then
            sudo mv "$EXTRACTED" /usr/local/bin/chromedriver
            sudo chmod +x /usr/local/bin/chromedriver
            echo "   ✅ chromedriver installed to /usr/local/bin/chromedriver"
        else
            echo "   ❌ Could not find chromedriver binary in downloaded zip."
            exit 1
        fi
        rm -rf /tmp/chromedriver.zip /tmp/chromedriver_extracted
    else
        echo "   ❌ Could not determine chromedriver download URL."
        exit 1
    fi
else
    echo "   chromedriver already installed."
fi

# ── Final verification ──
echo "✅ chromedriver: $(chromedriver --version 2>/dev/null)"

# Quick sanity check — make sure Chrome can actually launch headlessly
echo "   Verifying headless Chrome launch..."
"$CHROME_BIN" --headless=new --no-sandbox --disable-dev-shm-usage \
    --dump-dom about:blank > /dev/null 2>&1 && echo "✅ Headless Chrome OK" \
    || echo "⚠️  Headless launch test failed — may still work inside Python/Selenium"

echo ""
echo "▶  Installing Python dependencies..."
pip install -r requirements.txt
echo "✅ Python packages installed"

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  All done! Run the app with:"
echo ""
echo "  streamlit run app.py --server.port 8501 --server.address 0.0.0.0"
echo ""
echo "════════════════════════════════════════════════════════════"
