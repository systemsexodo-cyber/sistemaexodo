import sys

content = open('lib/services/data_service.dart', encoding='utf-8').read()

# Simple parser that ignores strings and comments
depth = 0
in_single_string = False
in_double_string = False
in_triple_single = False
in_triple_double = False
in_block_comment = False
i = 0

class_started_at = -1
class_closed_at = -1
depth_at_interesting = {}

while i < len(content):
    c = content[i]
    
    # Handle line comment
    if not in_single_string and not in_double_string and not in_triple_single and not in_triple_double and not in_block_comment:
        if c == '/' and i+1 < len(content) and content[i+1] == '/':
            # Skip to end of line
            while i < len(content) and content[i] != '\n':
                i += 1
            i += 1
            continue
        
        # Handle block comment
        if c == '/' and i+1 < len(content) and content[i+1] == '*':
            in_block_comment = True
            i += 2
            continue
        
        # Triple strings
        if c == "'" and content[i:i+3] == "'''":
            in_triple_single = True
            i += 3
            continue
        if c == '"' and content[i:i+3] == '"""':
            in_triple_double = True
            i += 3
            continue
        
        # Single/double strings
        if c == "'":
            in_single_string = True
            i += 1
            continue
        if c == '"':
            in_double_string = True
            i += 1
            continue
        
        # Braces
        if c == '{':
            depth += 1
            if depth == 1 and class_started_at == -1:
                line_num = content[:i].count('\n') + 1
                class_started_at = line_num
                print(f'Class opened at line {line_num} (depth now {depth})')
        elif c == '}':
            depth -= 1
            if class_started_at != -1 and depth == 0:
                line_num = content[:i].count('\n') + 1
                class_closed_at = line_num
                print(f'Class CLOSED at line {line_num} (depth now {depth})')
                # Show some content after
                remaining = content[i:i+200]
                print(f'  Content after closing brace: {repr(remaining[:100])}')
                break
    else:
        # Handle block comment end
        if in_block_comment:
            if c == '*' and i+1 < len(content) and content[i+1] == '/':
                in_block_comment = False
                i += 2
            else:
                i += 1
            continue
        
        # Handle triple strings
        if in_triple_single:
            if content[i:i+3] == "'''":
                in_triple_single = False
                i += 3
            elif c == '\\':
                i += 2
            else:
                i += 1
            continue
        
        if in_triple_double:
            if content[i:i+3] == '"""':
                in_triple_double = False
                i += 3
            elif c == '\\':
                i += 2
            else:
                i += 1
            continue
        
        # Handle single-line strings
        if in_single_string:
            if c == "\\":
                i += 2
            elif c == "'":
                in_single_string = False
                i += 1
            else:
                i += 1
            continue
        
        if in_double_string:
            if c == "\\":
                i += 2
            elif c == '"':
                in_double_string = False
                i += 1
            else:
                i += 1
            continue
    
    i += 1

print(f'\nClass started at line: {class_started_at}')
print(f'Class closed at line: {class_closed_at}')
total_lines = content.count('\n') + 1
print(f'Total lines: {total_lines}')
if class_closed_at < total_lines - 5:
    print(f'!! PROBLEM: Class closes at {class_closed_at} but file has {total_lines} lines!')
    print(f'Methods after line {class_closed_at} are OUTSIDE the class!')
