#!/bin/bash

# Carlink Flutter Project Cleanup Script
# This script removes build artifacts, caches, and temporary files
# Safe to run before committing to git or uploading to GitHub

echo "🧹 Starting Carlink project cleanup..."
echo ""

# Counter for tracking removals
removed_count=0

# Function to remove files/directories and count them
safe_remove() {
    local path="$1"
    local description="$2"

    if [ -e "$path" ]; then
        echo "Removing: $description"
        rm -rf "$path"
        removed_count=$((removed_count + 1))
    fi
}

# Get initial size
initial_size=$(du -sh . 2>/dev/null | cut -f1)
echo "Initial size: $initial_size"
echo ""

# Remove macOS metadata files
echo "📁 Removing macOS metadata files..."
find . -name ".DS_Store" -type f -delete 2>/dev/null
find . -name "._*" -type f -delete 2>/dev/null
echo ""

# Remove Gradle cache and build files
echo "🔧 Removing Gradle cache..."
safe_remove "example/android/.gradle" "Example Android Gradle cache"
safe_remove "android/.gradle" "Android Gradle cache"
safe_remove ".gradle" "Root Gradle cache"
echo ""

# Remove build directories
echo "🏗️  Removing build directories..."
safe_remove "build" "Root build directory"
safe_remove "example/build" "Example build directory"
safe_remove "example/android/app/build" "Example Android app build"
safe_remove "android/app/build" "Android app build"
echo ""

# Remove IDE files
echo "💻 Removing IDE files..."
safe_remove ".idea" "Root IntelliJ IDEA directory"
safe_remove "example/android/.idea" "Example Android Studio directory"
safe_remove "android/.idea" "Android Studio directory"
find . -name "*.iml" -type f -delete 2>/dev/null
echo ""

# Remove Dart/Flutter cache
echo "🎯 Removing Dart/Flutter cache..."
safe_remove ".dart_tool" "Dart tool cache"
safe_remove "example/.dart_tool" "Example Dart tool cache"
safe_remove ".flutter-plugins" "Flutter plugins"
safe_remove ".flutter-plugins-dependencies" "Flutter plugin dependencies"
safe_remove "example/.flutter-plugins" "Example Flutter plugins"
safe_remove "example/.flutter-plugins-dependencies" "Example Flutter plugin dependencies"
echo ""

# Remove release builds (APK/AAB files)
echo "📦 Removing release builds..."
safe_remove "example/android/app/release" "Example release builds"
safe_remove "android/app/release" "Release builds"
safe_remove "android/app/debug" "Debug builds"
safe_remove "android/app/profile" "Profile builds"
find . -name "*.apk" -type f -delete 2>/dev/null
find . -name "*.aab" -type f -delete 2>/dev/null
echo ""

# Remove log files
echo "📝 Removing log files..."
find . -name "*.log" -type f -delete 2>/dev/null
safe_remove "logs" "Logs directory"
echo ""

# Remove other temporary files
echo "🗑️  Removing temporary files..."
find . -name "*.tmp" -type f -delete 2>/dev/null
find . -name "*.temp" -type f -delete 2>/dev/null
find . -name "*.swp" -type f -delete 2>/dev/null
find . -name "*.swo" -type f -delete 2>/dev/null
find . -name "*~" -type f -delete 2>/dev/null
echo ""

# Remove captured files and NDK build artifacts
echo "🔨 Removing native build artifacts..."
safe_remove ".externalNativeBuild" "External native build"
safe_remove "android/.externalNativeBuild" "Android external native build"
safe_remove ".cxx" "C++ build artifacts"
safe_remove "android/.cxx" "Android C++ build artifacts"
safe_remove "obj" "Object files"
echo ""

# Get final size
final_size=$(du -sh . 2>/dev/null | cut -f1)

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "Summary:"
echo "  Initial size: $initial_size"
echo "  Final size:   $final_size"
echo "  Items removed: $removed_count directories/file types"
echo ""
echo "Your project is now ready for GitHub upload!"
