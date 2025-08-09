#!/usr/bin/env python3
"""
Check tables in Mathpix MMD files
"""

import re
from pathlib import Path

def find_tables(mmd_file):
    """Find and extract tables from MMD file"""
    
    with open(mmd_file, 'r', encoding='utf-8') as f:
        content = f.read()
    
    tables = []
    
    # Method 1: Look for pipe-delimited tables (Markdown style)
    # Pattern: lines with | characters
    lines = content.split('\n')
    in_table = False
    current_table = []
    
    for i, line in enumerate(lines):
        # Check if line looks like a table row
        if '|' in line and line.count('|') >= 2:
            if not in_table:
                in_table = True
                current_table = []
            current_table.append(line)
        elif in_table:
            # Check if this might be a separator line
            if set(line.strip()) <= set('-|: ') and line.strip():
                current_table.append(line)
            else:
                # End of table
                if len(current_table) > 2:  # At least header + separator + 1 row
                    tables.append({
                        'type': 'markdown',
                        'line_start': i - len(current_table),
                        'content': current_table
                    })
                in_table = False
                current_table = []
    
    # Method 2: Look for LaTeX tables
    latex_tables = re.findall(r'\\begin\{(?:table|tabular)[^}]*\}(.*?)\\end\{(?:table|tabular)\}', 
                              content, re.DOTALL)
    for lt in latex_tables:
        tables.append({
            'type': 'latex',
            'content': lt[:500] + '...' if len(lt) > 500 else lt
        })
    
    # Method 3: Look for HTML tables
    html_tables = re.findall(r'<table[^>]*>(.*?)</table>', content, re.DOTALL | re.IGNORECASE)
    for ht in html_tables:
        tables.append({
            'type': 'html',
            'content': ht[:500] + '...' if len(ht) > 500 else ht
        })
    
    return tables

def analyze_all_tables():
    """Check all MMD files for tables"""
    
    mmd_dir = Path("Papers/mmd")
    mmd_files = sorted(mmd_dir.glob("*.mmd"))
    
    print("🔍 Scanning for tables in converted papers...\n")
    print("="*70)
    
    total_tables = 0
    papers_with_tables = []
    
    for mmd_file in mmd_files:
        tables = find_tables(mmd_file)
        
        if tables:
            papers_with_tables.append(mmd_file.name)
            total_tables += len(tables)
            
            print(f"\n📄 {mmd_file.name}")
            print(f"   Found {len(tables)} table(s)")
            
            for i, table in enumerate(tables, 1):
                print(f"\n   Table {i} ({table['type']} format):")
                print("   " + "-"*50)
                
                if table['type'] == 'markdown':
                    # Show first few rows
                    for row in table['content'][:5]:
                        print(f"   {row}")
                    if len(table['content']) > 5:
                        print(f"   ... ({len(table['content'])} total rows)")
                else:
                    # Show snippet for other formats
                    snippet = str(table['content'])[:200]
                    print(f"   {snippet}...")
    
    # Summary
    print("\n" + "="*70)
    print("📊 TABLE EXTRACTION SUMMARY")
    print("="*70)
    print(f"Total tables found: {total_tables}")
    print(f"Papers with tables: {len(papers_with_tables)}/{len(mmd_files)}")
    
    if not papers_with_tables:
        print("\n⚠️  No tables detected! Let me check the raw content...")
        # Sample check
        sample_file = mmd_files[0] if mmd_files else None
        if sample_file:
            print(f"\nSampling from {sample_file.name}:")
            with open(sample_file, 'r') as f:
                content = f.read()
                # Look for common table indicators
                indicators = ['Table', 'TABLE', '|', '\\begin{tabular}', '<table>']
                for ind in indicators:
                    count = content.count(ind)
                    if count > 0:
                        print(f"  Found '{ind}': {count} times")
                        # Show context
                        idx = content.find(ind)
                        if idx != -1:
                            snippet = content[max(0,idx-50):min(len(content),idx+200)]
                            print(f"    Context: ...{snippet}...")
                            break

if __name__ == "__main__":
    analyze_all_tables()