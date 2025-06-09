#!/bin/bash

# Smart script to comment out IO.puts statements in Elixir files
# This handles case expressions by replacing IO.puts with :ok
# Only processes files in lib/ and test/ directories

# Function to process a single file
process_file() {
    local file="$1"
    echo "Processing: $file"
    
    # Use sed with multiple patterns to handle different IO.puts scenarios
    sed -i '' \
        -e 's/^[[:space:]]*IO\.puts.*$/# &/' \
        -e 's/\([[:space:]]*\)IO\.puts.*$/\1:ok # &/' \
        "$file"
}

# Find all .ex and .exs files in lib/ and test/ directories only
find /Users/mcotner/Documents/elixir/snmp_sim/lib /Users/mcotner/Documents/elixir/snmp_sim/test -name "*.ex" -o -name "*.exs" | while read -r file; do
    # Check if file contains IO.puts before processing
    if grep -q "IO\.puts" "$file"; then
        process_file "$file"
    fi
done

echo "✅ All IO.puts statements in lib/ and test/ have been commented out!"
echo "To undo this change, run: git checkout -- lib/ test/"
