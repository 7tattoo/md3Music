path = r'C:\Users\32732\Desktop\TRAE SOLO\md3Music\.github\workflows\debug-build.yml'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add build_type input
old_inputs = """    inputs:
      notes:
        description: '构建说明（可选）'
        required: false
        type: string
        default: ''"""

new_inputs = """    inputs:
      build_type:
        description: '构建类型'
        required: true
        type: choice
        options:
          - debug
          - release
        default: 'debug'
      notes:
        description: '构建说明（可选）'
        required: false
        type: string
        default: ''"""

content = content.replace(old_inputs, new_inputs)

# 2. Update job name
content = content.replace(
    'name: Build Android Debug APK',
    "name: Build Android ${{ inputs.build_type == 'release' && 'Release' || 'Debug' }} APK"
)

# 3. Update build command
content = content.replace(
    "      - name: Flutter build debug APK\n        run: flutter build apk --debug",
    "      - name: Flutter build APK\n        run: flutter build apk --${{ inputs.build_type }}"
)

# 4. Update artifact name and path
content = content.replace(
    """      - name: Upload debug APK
        uses: actions/upload-artifact@v4
        with:
          name: app-debug
          path: build/app/outputs/flutter-apk/app-debug.apk""",
    """      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: app-${{ inputs.build_type }}
          path: build/app/outputs/flutter-apk/app-${{ inputs.build_type }}.apk"""
)

# 5. Update comment
content = content.replace(
    '# Flutter 构建 debug APK（不分 ABI，单文件方便安装）',
    '# Flutter 构建 APK'
)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print('Done. build_type input added:', 'build_type' in content)
print('Release option:', 'release' in content)
