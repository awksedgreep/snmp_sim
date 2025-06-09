#!/bin/bash

# Sed script to comment out IO.puts statements in Elixir files
# This will find lines containing IO.puts and prefix them with "# "

# Function to process a single file
process_file() {
    local file="$1"
    echo "Processing: $file"
    
    # Use sed to comment out IO.puts lines
    # This handles various indentation patterns and preserves the original formatting
    sed -i '' 's/^[[:space:]]*IO\.puts/# &/' "$file"
}

# Find all .ex and .exs files and process them
find /Users/mcotner/Documents/elixir/snmp_sim -name "*.ex" -o -name "*.exs" | while read -r file; do
    # Check if file contains IO.puts before processing
    if grep -q "IO\.puts" "$file"; then
        process_file "$file"
    fi
done

echo "✅ All IO.puts statements have been commented out!"
echo "To undo this change, run: git checkout -- ."
