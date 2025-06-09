#!/bin/bash

# Safe script to comment out IO.puts statements in lib/ and test/ directories
# This approach only comments lines that start with IO.puts (with optional whitespace)
# to avoid breaking multi-line expressions

echo "Commenting out IO.puts statements in lib/ and test/ directories..."

# Find all .ex and .exs files in lib/ and test/ directories
find lib/ test/ -name "*.ex" -o -name "*.exs" | while read -r file; do
    if grep -q "IO\.puts" "$file"; then
        echo "Processing: $file"
        # Use sed to comment out lines that start with optional whitespace followed by IO.puts
        # This avoids commenting lines where IO.puts is in the middle of an expression
        sed -i '' 's/^[[:space:]]*IO\.puts/# &/' "$file"
    fi
done

echo "✅ Completed commenting out standalone IO.puts statements!"
echo "To undo this change, run: git checkout -- lib/ test/"
