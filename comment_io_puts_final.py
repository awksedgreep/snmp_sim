#!/usr/bin/env python3
"""
Safe IO.puts commenting script for Elixir files.
This script handles multi-line IO.puts statements including heredocs.
"""

import os
import re
import sys

def process_file(filepath):
    """Process a single file to comment out IO.puts statements."""
    with open(filepath, 'r') as f:
        lines = f.readlines()
    
    modified = False
    new_lines = []
    i = 0
    
    while i < len(lines):
        line = lines[i]
        
        # Check if this line starts an IO.puts statement
        if re.match(r'^\s*IO\.puts\s*\(', line.strip()):
            # Found IO.puts, now we need to find where it ends
            modified = True
            indent = len(line) - len(line.lstrip())
            
            # Comment out the first line
            new_lines.append('# ' + line)
            i += 1
            
            # Track parentheses and heredocs to find the end
            paren_count = line.count('(') - line.count(')')
            in_heredoc = '"""' in line and line.count('"""') % 2 == 1
            
            # Continue until we find the end of the IO.puts statement
            while i < len(lines) and (paren_count > 0 or in_heredoc):
                line = lines[i]
                
                # Comment out continuation lines
                new_lines.append('# ' + line)
                
                # Update parentheses count
                paren_count += line.count('(') - line.count(')')
                
                # Check for heredoc end
                if '"""' in line:
                    if line.count('"""') % 2 == 1:
                        in_heredoc = not in_heredoc
                
                i += 1
        else:
            # Regular line, keep as is
            new_lines.append(line)
            i += 1
    
    if modified:
        with open(filepath, 'w') as f:
            f.writelines(new_lines)
        return True
    return False

def main():
    """Main function to process all Elixir files in lib/ and test/ directories."""
    processed_count = 0
    
    # Find all .ex and .exs files in lib/ and test/
    for root in ['lib', 'test']:
        if not os.path.exists(root):
            continue
            
        for dirpath, dirnames, filenames in os.walk(root):
            for filename in filenames:
                if filename.endswith(('.ex', '.exs')):
                    filepath = os.path.join(dirpath, filename)
                    
                    # Check if file contains IO.puts
                    with open(filepath, 'r') as f:
                        content = f.read()
                        if 'IO.puts' in content:
                            print(f"Processing: {filepath}")
                            if process_file(filepath):
                                processed_count += 1
    
    print(f"✅ Processed {processed_count} files with IO.puts statements!")
    print("To undo this change, run: git checkout -- lib/ test/")

if __name__ == "__main__":
    main()
