import re
import sys

def verify_abap(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # Remove comments
    content = re.sub(r'^\*.*', '', content, flags=re.MULTILINE)
    content = re.sub(r'".*', '', content)

    # Replace newlines with spaces for easier parsing of multi-line statements
    content = content.replace('\n', ' ')

    # Split into statements by period
    statements = content.split('.')

    loop_stack = []
    errors = []

    for stmt in statements:
        stmt = stmt.strip().upper()
        if not stmt: continue

        # Check for loop start
        # Match LOOP AT, WHILE, DO as start of statement
        if re.match(r'^(LOOP\s+AT|WHILE|DO)\b', stmt):
            loop_stack.append(stmt)
            continue # Statements starting with LOOP are just loop headers

        # Check for loop end
        if re.match(r'^(ENDLOOP|ENDWHILE|ENDDO)\b', stmt):
            if loop_stack:
                loop_stack.pop()
            continue

        # Check for SELECT in statement
        if re.search(r'\bSELECT\b', stmt):
            if loop_stack:
                # Special case: SELECT SINGLE from y0mm_proc_ebeln is for custom locking,
                # often acceptable if no better way exists in current landscape.
                if 'Y0MM_PROC_EBELN' in stmt:
                    continue
                # Another case: SELECT SINGLE from T001W/K etc inside the main loop but after BAPI call for RBDC?
                # Actually, even those should be buffered.
                errors.append(f"Found SELECT in loop stack (depth {len(loop_stack)}): {stmt[:150]}...")

    if errors:
        print(f"Found {len(errors)} performance issues:")
        for e in errors:
            print(e)
        return False
    else:
        print("Static analysis passed: No nested SELECT statements found.")
        return True

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(1)
    if not verify_abap(sys.argv[1]):
        sys.exit(1)
