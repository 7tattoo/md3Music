path = r'C:\Users\32732\Desktop\TRAE SOLO\md3Music\lib\services\kugou_api\kugou_api_client.dart'
with open(path, 'r', encoding='utf-8') as f:
    src = f.read()

pairs = {'{': '}', '(': ')', '[': ']'}
stack = []
in_str = None
escape = False
mismatch = None
i = 0
for ch in src:
    if in_str:
        if escape:
            escape = False
        elif ch == '\\':
            escape = True
        elif ch == in_str:
            in_str = None
        continue
    if ch in ("'", '"'):
        in_str = ch
        continue
    if ch in pairs:
        stack.append(ch)
    elif ch in pairs.values():
        if not stack or pairs[stack.pop()] != ch:
            mismatch = (i, ch)
            break
    i += 1

print('Braces balanced:', len(stack) == 0 and mismatch is None)
if mismatch:
    print('Mismatch at offset', mismatch[0], 'char:', mismatch[1])
print('Stack remainder:', len(stack))
print('Lines:', src.count('\n') + 1)
