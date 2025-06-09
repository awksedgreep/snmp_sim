#!/bin/bash

# Replace IO.puts with Logger.debug in lib/ and test/ directories
# This approach is safe for all contexts including case clauses

echo "Replacing IO.puts with Logger.debug in lib/ and test/ directories..."

# Find all .ex and .exs files in lib/ and test/ directories
find lib/ test/ -name "*.ex" -o -name "*.exs" | while read -r file; do
    if grep -q "IO\.puts" "$file"; then
        echo "Processing: $file"
        # Replace IO.puts with Logger.debug
        sed -i '' 's/IO\.puts/Logger.debug/g' "$file"
    fi
done

echo "✅ Completed replacing IO.puts with Logger.debug!"
echo "Note: You may need to add 'require Logger' to files that don't already have it."
echo "To undo this change, run: git checkout -- lib/ test/"
