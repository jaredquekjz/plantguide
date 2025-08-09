#!/usr/bin/env python3
"""
Check and preview equations from Mathpix MMD files
"""

import re
import sys
from pathlib import Path

def extract_equations(mmd_file):
    """Extract all math equations from an MMD file"""
    
    with open(mmd_file, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Find inline math $...$
    inline_math = re.findall(r'\$([^$]+)\$', content)
    
    # Find display math $$...$$
    display_math = re.findall(r'\$\$([^$]+)\$\$', content, re.DOTALL)
    
    # Find \[...\] style
    bracket_math = re.findall(r'\\\[(.*?)\\\]', content, re.DOTALL)
    
    # Find \(...\) style  
    paren_math = re.findall(r'\\\((.*?)\\\)', content)
    
    return {
        'inline': inline_math,
        'display': display_math + bracket_math,
        'inline_alt': paren_math
    }

def show_equations(mmd_file):
    """Display equations from an MMD file"""
    
    equations = extract_equations(mmd_file)
    total = len(equations['inline']) + len(equations['display']) + len(equations['inline_alt'])
    
    print(f"\n📄 {Path(mmd_file).name}")
    print(f"Found {total} equations total")
    print("="*60)
    
    if equations['display']:
        print(f"\n🔢 Display Equations ({len(equations['display'])})")
        print("-"*40)
        for i, eq in enumerate(equations['display'][:5], 1):  # Show first 5
            eq_clean = eq.strip()
            if len(eq_clean) > 100:
                eq_clean = eq_clean[:100] + "..."
            print(f"{i}. {eq_clean}")
        if len(equations['display']) > 5:
            print(f"   ... and {len(equations['display'])-5} more")
    
    if equations['inline']:
        print(f"\n📐 Inline Equations ({len(equations['inline'])})")
        print("-"*40)
        for i, eq in enumerate(equations['inline'][:10], 1):  # Show first 10
            eq_clean = eq.strip()
            if len(eq_clean) > 60:
                eq_clean = eq_clean[:60] + "..."
            print(f"{i}. ${eq_clean}$")
        if len(equations['inline']) > 10:
            print(f"   ... and {len(equations['inline'])-10} more")
    
    return equations

def validate_latex(equation):
    """Basic validation of LaTeX syntax"""
    issues = []
    
    # Check for balanced braces
    if equation.count('{') != equation.count('}'):
        issues.append("Unbalanced braces {}")
    
    # Check for balanced brackets
    if equation.count('[') != equation.count(']'):
        issues.append("Unbalanced brackets []")
    
    # Check for balanced parentheses in \left( \right)
    if equation.count(r'\left(') != equation.count(r'\right)'):
        issues.append("Unbalanced \\left( \\right)")
    
    # Check for common LaTeX commands
    common_issues = [
        (r'\frac' in equation and '{' not in equation, "\\frac without arguments"),
        (r'\sqrt' in equation and '{' not in equation, "\\sqrt without arguments"),
        ('_' in equation and '{' not in equation[equation.index('_'):equation.index('_')+3], "Subscript without braces"),
        ('^' in equation and '{' not in equation[equation.index('^'):equation.index('^')+3], "Superscript without braces"),
    ]
    
    for condition, message in common_issues:
        if condition:
            issues.append(message)
    
    return issues

def check_all_papers():
    """Check equations in all converted papers"""
    mmd_dir = Path("Papers/mmd")
    mmd_files = sorted(mmd_dir.glob("*.mmd"))
    
    print(f"\n🔍 Checking {len(mmd_files)} MMD files for equations...\n")
    
    stats = {
        'total_files': len(mmd_files),
        'total_equations': 0,
        'files_with_equations': 0,
        'potential_issues': []
    }
    
    for mmd_file in mmd_files:
        equations = show_equations(mmd_file)
        
        total_eqs = len(equations['inline']) + len(equations['display']) + len(equations['inline_alt'])
        if total_eqs > 0:
            stats['files_with_equations'] += 1
            stats['total_equations'] += total_eqs
            
            # Check a sample for issues
            sample = equations['display'][:3] + equations['inline'][:5]
            for eq in sample:
                issues = validate_latex(eq)
                if issues:
                    stats['potential_issues'].append({
                        'file': mmd_file.name,
                        'equation': eq[:50] + "..." if len(eq) > 50 else eq,
                        'issues': issues
                    })
    
    # Summary
    print("\n" + "="*60)
    print("📊 OVERALL SUMMARY")
    print("="*60)
    print(f"Total files processed: {stats['total_files']}")
    print(f"Files with equations: {stats['files_with_equations']}")
    print(f"Total equations found: {stats['total_equations']}")
    
    if stats['potential_issues']:
        print(f"\n⚠️  Potential issues found: {len(stats['potential_issues'])}")
        for issue in stats['potential_issues'][:5]:
            print(f"\nFile: {issue['file']}")
            print(f"Equation: {issue['equation']}")
            print(f"Issues: {', '.join(issue['issues'])}")
    else:
        print("\n✅ No obvious LaTeX syntax issues detected!")
    
    print("\n💡 To render equations properly:")
    print("1. Use a Markdown viewer with LaTeX support (Obsidian, Typora, etc.)")
    print("2. Convert to HTML with MathJax/KaTeX")
    print("3. Use pandoc to convert to PDF with proper equation rendering")
    print("4. Import into LaTeX document for native rendering")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        # Check specific file
        show_equations(sys.argv[1])
    else:
        # Check all papers
        check_all_papers()