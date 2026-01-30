#!/bin/bash
# make-walkthrough.sh - Generate a scrolling walkthrough video from screenshots
# Usage: make-walkthrough.sh <run-dir> [viewport-height] [scroll-speed]
#
# For tall screenshots, pans top-to-bottom at viewport size.
# Short screenshots get held as a still frame.
# Overlays step annotation text + URL bar on each segment.
#
# URL bar: reads from <step-NN-name>.url sidecar files (one URL per line).
# If no .url file exists, the URL bar is omitted for that step.

set -euo pipefail

RUN_DIR="${1:?Usage: make-walkthrough.sh <run-dir>}"
VIEWPORT_W=1280
VIEWPORT_H="${2:-720}"
SCROLL_PX_PER_SEC="${3:-120}"    # pixels per second scroll speed
HOLD_SEC_BASE=4                   # minimum seconds to hold short images
HOLD_SEC_PER_CHAR=0.06            # extra hold time per character of label text

# URL bar dimensions
URL_BAR_H=40                      # height of the URL bar strip
CONTENT_H=$((VIEWPORT_H - URL_BAR_H))  # remaining height for page content

OUT="$RUN_DIR/walkthrough.mp4"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# --- Resolve step labels from the test definition ---
# Try to find the test JSON from the run dir name (slug is everything before the timestamp)
SLUG=$(basename "$RUN_DIR" | sed -E 's/-[0-9]{10,}$//' | sed -E 's/-[0-9]{8}-[0-9]{6}$//')
TEST_JSON="$HOME/.ui-tests/${SLUG}.json"
declare -a STEP_LABELS=()
TEST_NAME=""
TEST_DESC=""
TEST_SUCCESS=""
if [ -f "$TEST_JSON" ]; then
  # Read steps array from JSON
  while IFS= read -r line; do
    STEP_LABELS+=("$line")
  done < <(node -e "
    const t = require('$TEST_JSON');
    (t.steps||[]).forEach((s,i) => console.log(s));
  " 2>/dev/null || true)
  # Read name, description, successCriteria
  TEST_NAME=$(node -e "const t=require('$TEST_JSON'); console.log(t.name||'')" 2>/dev/null || true)
  TEST_DESC=$(node -e "const t=require('$TEST_JSON'); console.log(t.description||'')" 2>/dev/null || true)
  TEST_SUCCESS=$(node -e "const t=require('$TEST_JSON'); console.log(t.successCriteria||'')" 2>/dev/null || true)
  echo "Loaded ${#STEP_LABELS[@]} step labels from $TEST_JSON"
fi

# Collect step screenshots in order
mapfile -t IMGS < <(find "$RUN_DIR" -maxdepth 1 -name 'step-*.jpg' -o -name 'step-*.png' | sort)

if [ ${#IMGS[@]} -eq 0 ]; then
  echo "No step images found in $RUN_DIR"
  exit 1
fi

echo "Found ${#IMGS[@]} screenshots"
SEG_LIST="$TMPDIR/segments.txt"
> "$SEG_LIST"

# Text overlay settings
FONT="/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
if [ ! -f "$FONT" ]; then
  FONT="/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"
fi
FONT_REGULAR="/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
if [ ! -f "$FONT_REGULAR" ]; then
  FONT_REGULAR="$FONT"
fi
FONTSIZE=28
BOX_PAD=12
URL_FONTSIZE=16
MAX_LABEL_CHARS=70    # word-wrap threshold for step annotations
TITLE_FONTSIZE=36
TITLE_BODY_FONTSIZE=22
TITLE_HOLD_PER_CHAR=0.05
TITLE_HOLD_MIN=5
TITLE_HOLD_MAX=12

# Word-wrap function: wraps text at word boundaries to fit MAX_LABEL_CHARS per line
wordwrap() {
  local text="$1"
  local max="${2:-$MAX_LABEL_CHARS}"
  echo "$text" | fold -s -w "$max" | head -4  # cap at 4 lines max
}

# --- Generate title card if description exists ---
idx=0
if [ -n "$TEST_DESC" ] || [ -n "$TEST_SUCCESS" ]; then
  echo "Generating title card..."
  title_seg="$TMPDIR/seg-title.mp4"

  # Build drawtext filters for the title card
  TITLE_FILTERS=""
  y_cursor=60

  # Test name as heading
  if [ -n "$TEST_NAME" ]; then
    name_escaped=$(echo "$TEST_NAME" | sed "s/'/\\\\'/g" | sed 's/:/\\:/g')
    TITLE_FILTERS="drawtext=fontfile=${FONT}:text='${name_escaped}':fontcolor=#22C997:fontsize=${TITLE_FONTSIZE}:x=(w-text_w)/2:y=${y_cursor}"
    y_cursor=$(( y_cursor + TITLE_FONTSIZE + 30 ))
  fi

  # Horizontal rule
  if [ -n "$TITLE_FILTERS" ]; then
    TITLE_FILTERS="${TITLE_FILTERS},drawbox=x=200:y=${y_cursor}:w=880:h=2:color=#444444:t=fill"
    y_cursor=$(( y_cursor + 20 ))
  fi

  # Description block
  total_chars=0
  if [ -n "$TEST_DESC" ]; then
    y_cursor=$(( y_cursor + 10 ))
    # "Purpose:" label
    TITLE_FILTERS="${TITLE_FILTERS},drawtext=fontfile=${FONT}:text='Purpose':fontcolor=#AAAAAA:fontsize=${TITLE_BODY_FONTSIZE}:x=100:y=${y_cursor}"
    y_cursor=$(( y_cursor + TITLE_BODY_FONTSIZE + 12 ))

    # Word-wrap description
    mapfile -t DESC_LINES < <(echo "$TEST_DESC" | fold -s -w 60 | head -6)
    for dl in "${DESC_LINES[@]}"; do
      dl=$(echo "$dl" | sed 's/[[:space:]]*$//')
      dl_escaped=$(echo "$dl" | sed "s/'/\\\\'/g" | sed 's/:/\\:/g')
      TITLE_FILTERS="${TITLE_FILTERS},drawtext=fontfile=${FONT_REGULAR}:text='${dl_escaped}':fontcolor=white:fontsize=${TITLE_BODY_FONTSIZE}:x=100:y=${y_cursor}"
      y_cursor=$(( y_cursor + TITLE_BODY_FONTSIZE + 6 ))
      total_chars=$(( total_chars + ${#dl} ))
    done
    y_cursor=$(( y_cursor + 20 ))
  fi

  # Success criteria block
  if [ -n "$TEST_SUCCESS" ]; then
    # "Success Criteria:" label
    TITLE_FILTERS="${TITLE_FILTERS},drawtext=fontfile=${FONT}:text='Success Criteria':fontcolor=#AAAAAA:fontsize=${TITLE_BODY_FONTSIZE}:x=100:y=${y_cursor}"
    y_cursor=$(( y_cursor + TITLE_BODY_FONTSIZE + 12 ))

    # Word-wrap success criteria
    mapfile -t SC_LINES < <(echo "$TEST_SUCCESS" | fold -s -w 60 | head -6)
    for sl in "${SC_LINES[@]}"; do
      sl=$(echo "$sl" | sed 's/[[:space:]]*$//')
      sl_escaped=$(echo "$sl" | sed "s/'/\\\\'/g" | sed 's/:/\\:/g')
      TITLE_FILTERS="${TITLE_FILTERS},drawtext=fontfile=${FONT_REGULAR}:text='${sl_escaped}':fontcolor=#22C997:fontsize=${TITLE_BODY_FONTSIZE}:x=100:y=${y_cursor}"
      y_cursor=$(( y_cursor + TITLE_BODY_FONTSIZE + 6 ))
      total_chars=$(( total_chars + ${#sl} ))
    done
  fi

  # Dynamic hold time based on total text
  title_hold=$(echo "$TITLE_HOLD_PER_CHAR $total_chars $TITLE_HOLD_MIN $TITLE_HOLD_MAX" | awk '{d=$1*$2; if(d<$3) d=$3; if(d>$4) d=$4; printf "%.1f", d}')
  echo "  Title card: ${total_chars} chars, holding ${title_hold}s"

  ffmpeg -y -f lavfi -i "color=c=#1A1A2E:s=${VIEWPORT_W}x${VIEWPORT_H}:d=${title_hold}" \
    -vf "${TITLE_FILTERS}" \
    -r 30 -c:v libx264 -pix_fmt yuv420p -preset fast -crf 23 \
    "$title_seg" 2>/dev/null

  echo "file '$title_seg'" >> "$SEG_LIST"
  echo "  ✅ Title card generated"
fi
for img in "${IMGS[@]}"; do
  basename_img=$(basename "$img")
  echo "Processing: $basename_img"
  
  # Build annotation text
  file_label=$(echo "$basename_img" | sed -E 's/^step-[0-9]+-//' | sed -E 's/\.(jpg|png)$//' | tr '-' ' ' | sed -E 's/\b(.)/\u\1/g')
  
  step_num=$((10#$(echo "$basename_img" | grep -oP '(?<=step-)\d+')))
  if [ ${#STEP_LABELS[@]} -gt 0 ] && [ "$step_num" -gt 0 ] && [ "$step_num" -le "${#STEP_LABELS[@]}" ]; then
    label="Step ${step_num}: ${STEP_LABELS[$((step_num - 1))]}"
  else
    label="Step ${step_num}: ${file_label}"
  fi
  
  echo "  Label: $label"
  
  # --- Word-wrap long labels into multiple drawtext lines ---
  mapfile -t WRAPPED_LINES < <(wordwrap "$label" "$MAX_LABEL_CHARS")
  LINE_COUNT=${#WRAPPED_LINES[@]}
  LINE_HEIGHT=$(( FONTSIZE + 6 ))  # fontsize + spacing
  
  TEXT_FILTER=""
  for li in "${!WRAPPED_LINES[@]}"; do
    line="${WRAPPED_LINES[$li]}"
    # Trim trailing whitespace
    line=$(echo "$line" | sed 's/[[:space:]]*$//')
    line_escaped=$(echo "$line" | sed "s/'/\\\\'/g" | sed 's/:/\\:/g')
    y_pos=$(( URL_BAR_H + 10 + (li * LINE_HEIGHT) ))
    if [ -n "$TEXT_FILTER" ]; then
      TEXT_FILTER="${TEXT_FILTER},"
    fi
    TEXT_FILTER="${TEXT_FILTER}drawtext=fontfile=${FONT}:text='${line_escaped}':fontcolor=white:fontsize=${FONTSIZE}:box=1:boxcolor=black@0.65:boxborderw=${BOX_PAD}:x=20:y=${y_pos}:alpha='min(1,t/0.4)'"
  done
  
  # --- Read URL from sidecar file ---
  url_file="${img%.*}.url"
  step_url=""
  if [ -f "$url_file" ]; then
    step_url=$(head -1 "$url_file" | tr -d '\n\r')
    echo "  URL: $step_url"
  fi
  url_escaped=$(echo "$step_url" | sed "s/'/\\\\'/g" | sed 's/:/\\:/g')
  
  # URL bar: grey strip at top with URL text
  # Draw a filled rectangle for the bar background, then the URL text
  if [ -n "$step_url" ]; then
    # Lock icon (Unicode 🔒) for https, globe for http
    url_prefix=""
    if echo "$step_url" | grep -q '^https'; then
      url_prefix="🔒 "
    fi
    url_display="${url_prefix}${step_url}"
    url_display_escaped=$(echo "$url_display" | sed "s/'/\\\\'/g" | sed 's/:/\\:/g')
    
    URL_BAR_FILTER="drawbox=x=0:y=0:w=${VIEWPORT_W}:h=${URL_BAR_H}:color=#2B2B2B:t=fill,drawbox=x=0:y=$((URL_BAR_H - 1)):w=${VIEWPORT_W}:h=1:color=#444444:t=fill,drawtext=fontfile=${FONT_REGULAR}:text='${url_display_escaped}':fontcolor=#CCCCCC:fontsize=${URL_FONTSIZE}:x=16:y=$((( URL_BAR_H - URL_FONTSIZE ) / 2))"
  else
    # No URL — still draw bar but empty (consistent framing)
    URL_BAR_FILTER="drawbox=x=0:y=0:w=${VIEWPORT_W}:h=${URL_BAR_H}:color=#2B2B2B:t=fill,drawbox=x=0:y=$((URL_BAR_H - 1)):w=${VIEWPORT_W}:h=1:color=#444444:t=fill"
  fi
  
  # Get image dimensions
  dims=$(identify -format '%w %h' "$img")
  img_w=$(echo "$dims" | awk '{print $1}')
  img_h=$(echo "$dims" | awk '{print $2}')
  
  seg="$TMPDIR/seg-$(printf '%03d' $idx).mp4"
  
  # Resize so width = VIEWPORT_W (maintain aspect ratio)
  scaled_h=$(echo "$img_w $img_h $VIEWPORT_W" | awk '{printf "%d", ($3/$1)*$2}')
  scaled_h=$(( (scaled_h / 2) * 2 ))
  
  # Dynamic hold time: longer labels get more reading time
  label_len=${#label}
  hold_sec=$(echo "$HOLD_SEC_BASE $HOLD_SEC_PER_CHAR $label_len" | awk '{d=$1 + ($2 * $3); if(d<4) d=4; if(d>12) d=12; printf "%.1f", d}')
  
  if [ "$scaled_h" -le "$CONTENT_H" ]; then
    echo "  → Short image (${scaled_h}px), holding ${hold_sec}s (${label_len} chars)"
    # Pad to content area, then add URL bar on top
    ffmpeg -y -loop 1 -i "$img" \
      -vf "scale=${VIEWPORT_W}:-2,pad=${VIEWPORT_W}:${CONTENT_H}:(ow-iw)/2:(oh-ih)/2:black,pad=${VIEWPORT_W}:${VIEWPORT_H}:0:${URL_BAR_H}:black,${URL_BAR_FILTER},${TEXT_FILTER}" \
      -t "$hold_sec" -r 30 -c:v libx264 -pix_fmt yuv420p -preset fast -crf 23 \
      "$seg" 2>/dev/null
  else
    scroll_dist=$(( scaled_h - CONTENT_H ))
    dur_calc=$(echo "$scroll_dist $SCROLL_PX_PER_SEC" | awk '{d=$1/$2; if(d<2) d=2; printf "%.1f", d}')
    # Tall images also get extra time if label is long
    extra_hold=$(echo "$HOLD_SEC_PER_CHAR $label_len" | awk '{d=$1*$2; if(d>6) d=6; printf "%.1f", d}')
    total_dur=$(echo "$dur_calc $extra_hold" | awk '{printf "%.1f", $1 + 2 + $2}')
    
    echo "  → Tall image (${scaled_h}px), scrolling ${scroll_dist}px over ${dur_calc}s + ${extra_hold}s read time (total: ${total_dur}s)"
    
    # Scale, crop to scroll window (content area), pad to add URL bar space on top
    ffmpeg -y -loop 1 -i "$img" \
      -vf "scale=${VIEWPORT_W}:-2,crop=${VIEWPORT_W}:${CONTENT_H}:0:'min(${scroll_dist},max(0,(t-1)*${SCROLL_PX_PER_SEC}))',pad=${VIEWPORT_W}:${VIEWPORT_H}:0:${URL_BAR_H}:black,${URL_BAR_FILTER},${TEXT_FILTER}" \
      -t "$total_dur" -r 30 -c:v libx264 -pix_fmt yuv420p -preset fast -crf 23 \
      "$seg" 2>/dev/null
  fi
  
  echo "file '$seg'" >> "$SEG_LIST"
  idx=$((idx + 1))
done

echo "Concatenating ${idx} segments..."
ffmpeg -y -f concat -safe 0 -i "$SEG_LIST" \
  -c:v libx264 -pix_fmt yuv420p -preset fast -crf 23 \
  "$OUT" 2>/dev/null

dur=$(ffprobe -v quiet -print_format json -show_format "$OUT" | grep -o '"duration": "[^"]*"' | cut -d'"' -f4)
echo "✅ Walkthrough: $OUT (${dur}s)"
