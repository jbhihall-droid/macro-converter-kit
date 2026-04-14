#!/usr/bin/env bash
# ============================================================
# MacroKit — Stripe checkout setup (run once, checkout is live)
# Usage: ./setup-stripe.sh <YOUR_STRIPE_SECRET_KEY>
#   Live:  ./setup-stripe.sh sk_live_[your-key-here]
#   Test:  ./setup-stripe.sh sk_test_[your-key-here]
#
# What this does (all via Stripe API, no browser needed):
#   1. Creates the product: "Macro-Safe Converter Launch Kit"
#   2. Creates two prices: $9 one-time + $9/mo subscription
#   3. Creates a Stripe Payment Link for each
#   4. Patches index.html with the real checkout URLs
#   5. Git commits and pushes to GitHub Pages
#
# Requires: curl, jq, git (all already installed)
# Takes ~30 seconds total.
# ============================================================

set -euo pipefail

STRIPE_KEY="${1:-}"
if [[ -z "$STRIPE_KEY" ]]; then
  echo "Usage: ./setup-stripe.sh <YOUR_STRIPE_SECRET_KEY>"
  echo "  Get your key at: https://dashboard.stripe.com/apikeys"
  exit 1
fi

if [[ "$STRIPE_KEY" != sk_* ]]; then
  echo "ERROR: Key must start with sk_live_ or sk_test_"
  exit 1
fi

MODE="LIVE"
[[ "$STRIPE_KEY" == sk_test_* ]] && MODE="TEST"

echo ""
echo "MacroKit Stripe Setup — $MODE mode"
echo "======================================="

API="https://api.stripe.com/v1"
AUTH="Authorization: Bearer $STRIPE_KEY"

# ---- 1. Create Product ----
echo "[1/5] Creating Stripe product..."
PRODUCT=$(curl -s -X POST "$API/products" \
  -H "$AUTH" \
  -d name="Macro-Safe Converter Launch Kit" \
  -d description="127-keyword matrix, pricing model, landing page copy, 48-hour launch checklist, and niche opportunity guide for the macro-safe file conversion SaaS niche." \
  -d "url=https://jbhihall-droid.github.io/macro-converter-kit/" \
  -d "metadata[product]=macrokit-launch-kit")

PRODUCT_ID=$(echo "$PRODUCT" | jq -r '.id')
if [[ "$PRODUCT_ID" == "null" || -z "$PRODUCT_ID" ]]; then
  echo "ERROR creating product:"
  echo "$PRODUCT" | jq '.error'
  exit 1
fi
echo "   Product ID: $PRODUCT_ID"

# ---- 2. Create one-time price ($9) ----
echo "[2/5] Creating one-time price ($9)..."
PRICE_ONETIME=$(curl -s -X POST "$API/prices" \
  -H "$AUTH" \
  -d product="$PRODUCT_ID" \
  -d unit_amount=900 \
  -d currency=usd \
  -d "nickname=One-time — $9" \
  -d "metadata[type]=one_time")

PRICE_ONETIME_ID=$(echo "$PRICE_ONETIME" | jq -r '.id')
echo "   One-time price ID: $PRICE_ONETIME_ID"

# ---- 3. Create recurring price ($9/mo membership) ----
echo "[3/5] Creating $9/mo membership price..."
PRICE_SUB=$(curl -s -X POST "$API/prices" \
  -H "$AUTH" \
  -d product="$PRODUCT_ID" \
  -d unit_amount=900 \
  -d currency=usd \
  -d "recurring[interval]=month" \
  -d "nickname=Membership — $9/mo" \
  -d "metadata[type]=subscription")

PRICE_SUB_ID=$(echo "$PRICE_SUB" | jq -r '.id')
echo "   Subscription price ID: $PRICE_SUB_ID"

# ---- 4. Create Payment Links ----
echo "[4/5] Creating payment links..."

LINK_ONETIME=$(curl -s -X POST "$API/payment_links" \
  -H "$AUTH" \
  -d "line_items[0][price]=$PRICE_ONETIME_ID" \
  -d "line_items[0][quantity]=1" \
  -d "after_completion[type]=redirect" \
  -d "after_completion[redirect][url]=https://jbhihall-droid.github.io/macro-converter-kit/checkout-success.html" \
  -d "metadata[product]=macrokit-one-time")

LINK_ONETIME_URL=$(echo "$LINK_ONETIME" | jq -r '.url')
LINK_ONETIME_ID=$(echo "$LINK_ONETIME" | jq -r '.id')

LINK_SUB=$(curl -s -X POST "$API/payment_links" \
  -H "$AUTH" \
  -d "line_items[0][price]=$PRICE_SUB_ID" \
  -d "line_items[0][quantity]=1" \
  -d "after_completion[type]=redirect" \
  -d "after_completion[redirect][url]=https://jbhihall-droid.github.io/macro-converter-kit/checkout-success.html" \
  -d "metadata[product]=macrokit-membership")

LINK_SUB_URL=$(echo "$LINK_SUB" | jq -r '.url')
LINK_SUB_ID=$(echo "$LINK_SUB" | jq -r '.id')

echo "   One-time checkout URL: $LINK_ONETIME_URL"
echo "   Membership checkout URL: $LINK_SUB_URL"

# ---- 5. Patch index.html with real URLs ----
echo "[5/5] Patching index.html with live checkout URLs..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Update checkout.html if it exists
if [[ -f "$SCRIPT_DIR/checkout.html" ]]; then
  sed -i "s|STRIPE_ONETIME_URL|$LINK_ONETIME_URL|g" "$SCRIPT_DIR/checkout.html"
  sed -i "s|STRIPE_SUB_URL|$LINK_SUB_URL|g" "$SCRIPT_DIR/checkout.html"
fi

# Replace waitlist section in index.html with live buy buttons
python3 - <<PYEOF
import re

with open("$SCRIPT_DIR/index.html", "r") as f:
    html = f.read()

# Replace urgency bar text
html = html.replace(
    'Checkout opens in <strong>48 hours</strong> — early access pricing locks in at <strong>\$9</strong> (goes to \$19 at launch). Join the waitlist to get the link the moment it\'s live.',
    'Checkout is <strong>LIVE</strong> — founding price is <strong>\$9</strong> (increases to \$19 after the first 50 buyers).'
)

# Replace the waitlist-wrap section with live buy buttons
old_section = '''      <div class="waitlist-wrap">
        <div class="recommended-badge" style="margin-bottom:16px;">Early Access — \$9 (locks your price)</div>
        <h3>Join the Waitlist</h3>
        <p>Drop your email. You'll get the checkout link the moment the store opens — at the founding price of \$9. Price increases to \$19 after launch day.</p>
        <form class="waitlist-form" id="waitlist-form" onsubmit="submitWaitlist(event)">
          <input type="email" name="email" id="waitlist-email" placeholder="your@email.com" required>
          <button type="submit" id="cta-waitlist">Notify Me →</button>
        </form>
        <p id="waitlist-msg" style="font-size:13px;color:#00b894;margin-top:14px;display:none;font-weight:600;">You're on the list! We'll email you the moment checkout opens.</p>
        <p style="font-size:12px;color:#94a3b8;margin-top:14px;">No spam. One email when the store opens. Unsubscribe any time.</p>'''

new_section = '''      <div class="waitlist-wrap">
        <div class="recommended-badge" style="margin-bottom:16px;">Founding Price — \$9 (50 buyers only)</div>
        <h3>Get the Kit — \$9</h3>
        <p>Instant download. Everything you need to validate and launch in the macro-safe file conversion niche. Price locks at \$9 for the first 50 buyers.</p>
        <div style="display:flex;flex-direction:column;gap:12px;margin-bottom:8px;">
          <a href="$LINK_ONETIME_URL" class="btn-membership-primary" id="cta-buy-onetime" style="text-align:center;padding:16px;font-size:17px;">
            Buy the Kit — \$9 one-time →
          </a>
          <a href="$LINK_SUB_URL" style="display:block;text-align:center;background:#1a1d27;border:1px solid #6c5ce7;color:#c4b5fd;font-weight:600;font-size:14px;padding:12px;border-radius:8px;" id="cta-buy-sub">
            Or get Membership — \$9/mo (kit + monthly keyword updates)
          </a>
        </div>
        <p style="font-size:12px;color:#94a3b8;margin-top:8px;text-align:center;">Stripe checkout · 7-day refund if not useful · Instant download</p>'''

html = html.replace(old_section, new_section, 1)

# Update hero CTA
html = html.replace(
    'href="#get" id="cta-hero"',
    'href="$LINK_ONETIME_URL" id="cta-hero"'
)

with open("$SCRIPT_DIR/index.html", "w") as f:
    f.write(html)

print("   index.html patched.")
PYEOF

# ---- Save config ----
cat > "$SCRIPT_DIR/.stripe-config.json" <<JSONEOF
{
  "mode": "$MODE",
  "product_id": "$PRODUCT_ID",
  "price_onetime_id": "$PRICE_ONETIME_ID",
  "price_sub_id": "$PRICE_SUB_ID",
  "payment_link_onetime_id": "$LINK_ONETIME_ID",
  "payment_link_sub_id": "$LINK_SUB_ID",
  "checkout_url_onetime": "$LINK_ONETIME_URL",
  "checkout_url_sub": "$LINK_SUB_URL",
  "setup_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSONEOF

# ---- Git push ----
echo ""
echo "Pushing to GitHub Pages..."
cd "$SCRIPT_DIR"
git add index.html checkout.html checkout-success.html .stripe-config.json 2>/dev/null || true
git add -u
git commit -m "feat: live Stripe checkout — $MODE mode (setup-stripe.sh)"
git push origin main

echo ""
echo "======================================="
echo "DONE. Checkout is LIVE."
echo ""
echo "One-time (\$9):  $LINK_ONETIME_URL"
echo "Membership (\$9/mo): $LINK_SUB_URL"
echo ""
echo "Landing page: https://jbhihall-droid.github.io/macro-converter-kit/"
echo "======================================="
echo ""
echo "NEXT: Post these 3 community links (copy from ~/research/revenue-engine/ENG-059-community-drop-pack.md):"
echo "  1. IndieHackers: https://www.indiehackers.com/post/new"
echo "  2. r/microsaas: https://www.reddit.com/r/microsaas/submit"
echo "  3. r/SideProject: https://www.reddit.com/r/SideProject/submit"
