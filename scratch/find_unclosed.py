content = open('lib/services/data_service.dart', encoding='utf-8').read()
lines = content.split('\n')

class_start = 57  # line 58 = index 57 (the class declaration)

# Track depth from class start and find where depth transitions happen
# We want to find where depth goes from 1 to 2 and stays at 2 (i.e., a method opens but never closes)
brace_count = 0
depth_history = []
for i in range(class_start, len(lines)):
    old = brace_count
    brace_count += lines[i].count('{') - lines[i].count('}')
    depth_history.append((i, old, brace_count, lines[i]))

# Find where depth becomes 2 and stays there (looking for the point where we "entered" an extra level)
# Scan for depth 1 -> 2 transitions
last_depth_1_line = -1
last_depth_2_open = -1
for idx, (line_i, old_d, new_d, line_content) in enumerate(depth_history):
    if old_d == 1 and new_d == 2:
        last_depth_2_open = line_i
    if new_d == 1 and line_i < 5900:
        last_depth_1_line = line_i

print(f'Last time we were at depth 1 before line 5957: L{last_depth_1_line+1}')
print(f'Last time depth opened to 2 (before 5957): L{last_depth_2_open+1}')

# Show context around last_depth_2_open
print()
print('Context around the last depth 1->2 transition before problem area:')
for i in range(max(class_start, last_depth_2_open-3), min(len(lines), last_depth_2_open+10)):
    d = depth_history[i - class_start][2]
    print(f'L{i+1} [d={d}]: {lines[i][:100]}')
