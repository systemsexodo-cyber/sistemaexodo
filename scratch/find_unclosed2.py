content = open('lib/services/data_service.dart', encoding='utf-8').read()
lines = content.split('\n')

class_start = 57  # line 58 = index 57 (the class declaration)

# Find the LAST line at depth 1 before 5957 (class member level)
# Then find what opens AFTER that line that stays open until 5957+
brace_count = 0
problem_open = -1

for i in range(class_start, 5960):  # Stop before line 5957 (index 5956)
    old = brace_count
    brace_count += lines[i].count('{') - lines[i].count('}')
    
    # Track when we go from 1 to 2 (opening a function body)
    if old == 1 and brace_count == 2:
        problem_open = i  # This is the line that opens a function

# Now, was there a corresponding close before line 5957?
# Let's simulate from the last problem_open forward
if problem_open >= 0:
    print(f'The unclosed function opened at L{problem_open+1}:')
    print(f'  {lines[problem_open][:100]}')
    
    # Simulate forward from problem_open
    depth_from_there = 0
    for i in range(problem_open, 5960):
        depth_from_there += lines[i].count('{') - lines[i].count('}')
        if depth_from_there == 0 and i > problem_open:
            print(f'  Closed at L{i+1}: {lines[i][:80]}')
            break
    else:
        print(f'  NEVER CLOSED before line 5957!')

# Now find the ACTUAL last time we hit depth 1 (end of a class member) before 5957
brace_count = 0
depth_1_spots = []
for i in range(class_start, 5960):
    brace_count += lines[i].count('{') - lines[i].count('}')
    if brace_count == 1 and lines[i].strip():
        depth_1_spots.append(i)

if depth_1_spots:
    last_1 = depth_1_spots[-1]
    print(f'\nLast depth=1 line before 5957: L{last_1+1}: {lines[last_1][:80]}')
    
    # Show what comes after
    print('\nLines after last_1 up to 5957:')
    for i in range(last_1, min(last_1+30, 5960)):
        brace_count2 = 0
        for j in range(class_start, i+1):
            brace_count2 += lines[j].count('{') - lines[j].count('}')
        if lines[i].strip():
            print(f'L{i+1} [d={brace_count2}]: {lines[i][:100]}')
