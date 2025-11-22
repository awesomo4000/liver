#!/bin/bash

# Pool of cat posts (time|content)
POSTS=(
    "2 hours ago|Just discovered that if you stare at the hypercube long enough, it stares back at you through the fourth dimension 👁️✨ #DeepThoughts #HypercubeLife"
    "5 hours ago|Demanded breakfast at 5am. Humans said no. Demanded again at 5:15am. Got breakfast. Persistence is key. 🍽️😼"
    "Yesterday|Caught a glimpse of the red dot today. It got away again. Tomorrow is a new day. The hunt continues. 🔴🐾"
    "2 days ago|Sat in a box for 4 hours. Best decision ever. 10/10 would recommend. 📦😸"
    "3 days ago|Inspected the new web server implementation. Only 141KB! Very efficient. More time for naps. Approved. ✅💤"
    "1 hour ago|Found a sunbeam. Claimed it. This is my sunbeam. There are many like it but this one is mine. ☀️😺"
    "3 hours ago|Human tried to give me a bath. I have taken defensive positions on top of the refrigerator. Standoff continues. 🚿🙀"
    "6 hours ago|Knocked pen off desk 47 times today. New personal record. Training paying off. 🖊️💪"
    "12 hours ago|3am zoomies completed successfully. Household fully awakened. Mission accomplished. 🏃‍♂️💨"
    "Yesterday|Meowed at wall for 20 minutes. Wall did not respond. Will try again tomorrow. 🧱🗣️"
    "Yesterday|Successfully convinced human that 'second dinner' is a real thing. Innovation at its finest. 🍽️🧠"
    "2 days ago|Brought human a 'gift' (toy mouse). They screamed. Ungrateful. 🐭😾"
    "2 days ago|Sat on laptop keyboard during important Zoom call. Asserted dominance. Career counseling provided free of charge. 💻😼"
    "3 days ago|Found the forbidden cupboard (where treats are stored). This changes everything. 🚪✨"
    "3 days ago|Stretched. Yawned. Napped. Repeated. Productive day. 😴💯"
    "4 days ago|Tested gravity by pushing cup off counter. Gravity still works. Science is important. 🥤🔬"
    "4 days ago|Human installed new furniture. Assessed suitability for scratching. Highly suitable. 🛋️😈"
    "5 days ago|Participated in important meeting (napped on human's lap during video call). Morale boosted. 📹💤"
    "5 days ago|Chased tail for 10 minutes. It was my own tail. No regrets. 🌀😸"
    "6 days ago|Stared at bird outside window for 3 hours. Made chattering noises. Bird unimpressed. Tomorrow's problem. 🐦👀"
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HTML_FILE="$SCRIPT_DIR/index.html"

echo "🐱 Derpy's Post Rotator - Starting..."
echo "📝 Editing: $HTML_FILE"
echo "🔄 Press Ctrl+C to stop"
echo ""

while true; do
    # Pick random slot (0-4)
    SLOT=$((RANDOM % 5))

    # Pick random post from pool
    POST_INDEX=$((RANDOM % ${#POSTS[@]}))
    POST="${POSTS[$POST_INDEX]}"

    # Split post into time and content
    TIME="${POST%%|*}"
    CONTENT="${POST#*|}"

    # Build the post HTML and write to temp file
    POST_FILE="${HTML_FILE}.post"
    cat > "$POST_FILE" <<EOF
            <div class="post">
                <div class="post-header">
                    <img src="/derp.png" alt="Derpy" class="post-avatar">
                    <div class="post-meta">
                        <div class="post-author">Derpy</div>
                        <div class="post-time">$TIME</div>
                    </div>
                </div>
                <div class="post-content">
                    $CONTENT
                </div>
            </div>
EOF

    # Create temp file
    TMP_FILE="${HTML_FILE}.tmp"

    # Use awk to replace between markers, reading new post from file
    awk -v slot="$SLOT" -v post_file="$POST_FILE" '
        /<!-- POST_START_[0-9] -->/ {
            if ($0 ~ "POST_START_" slot) {
                print
                while ((getline line < post_file) > 0) {
                    print line
                }
                close(post_file)
                in_replace = 1
                next
            }
        }
        /<!-- POST_END_[0-9] -->/ {
            if (in_replace && $0 ~ "POST_END_" slot) {
                in_replace = 0
            }
        }
        !in_replace { print }
    ' "$HTML_FILE" > "$TMP_FILE"

    # Verify temp file is not empty before replacing
    if [ -s "$TMP_FILE" ]; then
        mv "$TMP_FILE" "$HTML_FILE"
        rm -f "$POST_FILE"
    else
        echo "ERROR: Generated file is empty, aborting!"
        rm -f "$TMP_FILE" "$POST_FILE"
        exit 1
    fi

    echo "$(date '+%H:%M:%S') - Updated slot $SLOT: ${TIME} - ${CONTENT:0:50}..."

    # Sleep 3-5 seconds
    sleep $((3 + RANDOM % 3))
done
