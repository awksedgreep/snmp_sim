#!/usr/bin/env python3

import os
import re
import glob

def process_file(filepath):
    """Process a single Elixir file to comment out IO.puts statements intelligently."""
    print(f"Processing: {filepath}")
    
    with open(filepath, 'r') as f:
        lines = f.readlines()
    
    modified_lines = []
    i = 0
    
    while i < len(lines):
        line = lines[i]
        
        # Check if this line contains IO.puts
        if 'IO.puts' in line:
            # Check if this is a standalone IO.puts line (starts with whitespace + IO.puts)
            if re.match(r'^\s*IO\.puts', line):
                # Comment out the entire line
                modified_lines.append(re.sub(r'^(\s*)IO\.puts', r'\1# IO.puts', line))
            else:
                # This is likely part of a case expression or similar
                # Replace IO.puts(...) with :ok
                modified_line = re.sub(r'IO\.puts\([^)]*\)', ':ok', line)
                # If the line still has IO.puts (multi-line call), comment it out
                if 'IO.puts' in modified_line:
                    modified_line = re.sub(r'^(\s*)', r'\1# ', modified_line)
                modified_lines.append(modified_line)
        else:
            modified_lines.append(line)
        
        i += 1
    
    # Write the modified content back to the file
    with open(filepath, 'w') as f:
        f.writelines(modified_lines)

def main():
    """Main function to process all Elixir files in lib/ and test/ directories."""
    base_dir = "/Users/mcotner/Documents/elixir/snmp_sim"
    
    # Find all .ex and .exs files in lib/ and test/ directories
    patterns = [
        os.path.join(base_dir, "lib", "**", "*.ex"),
        os.path.join(base_dir, "lib", "**", "*.exs"),
        os.path.join(base_dir, "test", "**", "*.ex"),
        os.path.join(base_dir, "test", "**", "*.exs")
    ]
    
    files_processed = 0
    
    for pattern in patterns:
        for filepath in glob.glob(pattern, recursive=True):
            # Check if file contains IO.puts before processing
            with open(filepath, 'r') as f:
                content = f.read()
                if 'IO.puts' in content:
                    process_file(filepath)
                    files_processed += 1
    
    print(f"✅ Processed {files_processed} files with IO.puts statements!")
    print("To undo this change, run: git checkout -- lib/ test/")

if __name__ == "__main__":
    main()
