#!/usr/bin/env python3
"""
Flutter Icon Generator
Generates all required icons for Flutter apps across all platforms from a single PNG/JPG image.
"""

import os
import sys
from PIL import Image
import argparse

# Icon configurations for different platforms
ICON_CONFIGS = {
    # Android Icons
    'android': {
        'base_path': 'android/app/src/main/res',
        'icons': [
            ('mipmap-mdpi/ic_launcher.png', 48),
            ('mipmap-hdpi/ic_launcher.png', 72),
            ('mipmap-xhdpi/ic_launcher.png', 96),
            ('mipmap-xxhdpi/ic_launcher.png', 144),
            ('mipmap-xxxhdpi/ic_launcher.png', 192),
            # Foreground icons for adaptive icons
            ('mipmap-mdpi/ic_launcher_foreground.png', 108),
            ('mipmap-hdpi/ic_launcher_foreground.png', 162),
            ('mipmap-xhdpi/ic_launcher_foreground.png', 216),
            ('mipmap-xxhdpi/ic_launcher_foreground.png', 324),
            ('mipmap-xxxhdpi/ic_launcher_foreground.png', 432),
        ]
    },
    
    # iOS Icons
    'ios': {
        'base_path': 'ios/Runner/Assets.xcassets/AppIcon.appiconset',
        'icons': [
            ('Icon-App-20x20@1x.png', 20),
            ('Icon-App-20x20@2x.png', 40),
            ('Icon-App-20x20@3x.png', 60),
            ('Icon-App-29x29@1x.png', 29),
            ('Icon-App-29x29@2x.png', 58),
            ('Icon-App-29x29@3x.png', 87),
            ('Icon-App-40x40@1x.png', 40),
            ('Icon-App-40x40@2x.png', 80),
            ('Icon-App-40x40@3x.png', 120),
            ('Icon-App-60x60@2x.png', 120),
            ('Icon-App-60x60@3x.png', 180),
            ('Icon-App-76x76@1x.png', 76),
            ('Icon-App-76x76@2x.png', 152),
            ('Icon-App-83.5x83.5@2x.png', 167),
            ('Icon-App-1024x1024@1x.png', 1024),
        ]
    },
    
    # Web Icons
    'web': {
        'base_path': 'web/icons',
        'icons': [
            ('Icon-192.png', 192),
            ('Icon-512.png', 512),
            ('Icon-maskable-192.png', 192),
            ('Icon-maskable-512.png', 512),
            ('favicon.png', 16),
        ]
    },
    
    # Windows Icons
    'windows': {
        'base_path': 'windows/runner/resources',
        'icons': [
            ('app_icon.ico', [16, 32, 48, 64, 128, 256]),  # ICO file with multiple sizes
        ]
    },
    
    # macOS Icons
    'macos': {
        'base_path': 'macos/Runner/Assets.xcassets/AppIcon.appiconset',
        'icons': [
            ('app_icon_16.png', 16),
            ('app_icon_32.png', 32),
            ('app_icon_64.png', 64),
            ('app_icon_128.png', 128),
            ('app_icon_256.png', 256),
            ('app_icon_512.png', 512),
            ('app_icon_1024.png', 1024),
        ]
    },
    
    # Linux Icons
    'linux': {
        'base_path': 'linux',
        'icons': [
            ('app_icon.png', 128),
        ]
    }
}

def ensure_directory(path):
    """Create directory if it doesn't exist."""
    os.makedirs(path, exist_ok=True)

def resize_image(image, size, maintain_aspect=True):
    """Resize image to specified size."""
    if maintain_aspect:
        # Calculate size maintaining aspect ratio
        original_width, original_height = image.size
        if original_width > original_height:
            new_width = size
            new_height = int((size * original_height) / original_width)
        else:
            new_height = size
            new_width = int((size * original_width) / original_height)
        
        # Resize and center on transparent background
        resized = image.resize((new_width, new_height), Image.Resampling.LANCZOS)
        
        # Create new image with transparent background
        new_image = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        
        # Center the resized image
        x_offset = (size - new_width) // 2
        y_offset = (size - new_height) // 2
        new_image.paste(resized, (x_offset, y_offset))
        
        return new_image
    else:
        return image.resize((size, size), Image.Resampling.LANCZOS)

def create_ico_file(image, sizes, output_path):
    """Create ICO file with multiple sizes."""
    icons = []
    for size in sizes:
        resized = resize_image(image, size, maintain_aspect=False)
        icons.append(resized)
    
    # Save as ICO
    icons[0].save(output_path, format='ICO', sizes=[(icon.width, icon.height) for icon in icons])

def generate_icons(input_path, output_base_path='.', platforms=None):
    """Generate icons for specified platforms."""
    
    # Load and validate input image
    try:
        with Image.open(input_path) as img:
            # Convert to RGBA if not already
            if img.mode != 'RGBA':
                img = img.convert('RGBA')
            
            print(f"Loaded image: {input_path} ({img.size[0]}x{img.size[1]})")
            
            # Use all platforms if none specified
            if platforms is None:
                platforms = ICON_CONFIGS.keys()
            
            total_icons = 0
            
            for platform in platforms:
                if platform not in ICON_CONFIGS:
                    print(f"Warning: Unknown platform '{platform}', skipping...")
                    continue
                
                config = ICON_CONFIGS[platform]
                platform_base = os.path.join(output_base_path, config['base_path'])
                
                print(f"\nGenerating {platform} icons...")
                
                for icon_config in config['icons']:
                    icon_path, size_info = icon_config
                    full_icon_path = os.path.join(platform_base, icon_path)
                    
                    # Ensure directory exists
                    ensure_directory(os.path.dirname(full_icon_path))
                    
                    if platform == 'windows' and icon_path.endswith('.ico'):
                        # Special handling for ICO files
                        create_ico_file(img, size_info, full_icon_path)
                        print(f"  Created: {full_icon_path} (ICO with multiple sizes)")
                    else:
                        # Regular PNG icons
                        size = size_info
                        resized_img = resize_image(img, size)
                        resized_img.save(full_icon_path, 'PNG')
                        print(f"  Created: {full_icon_path} ({size}x{size})")
                    
                    total_icons += 1
            
            print(f"\n✅ Successfully generated {total_icons} icons across {len(platforms)} platforms!")
            
    except Exception as e:
        print(f"Error processing image: {e}")
        sys.exit(1)

def create_ios_contents_json(base_path):
    """Create Contents.json file for iOS icons."""
    contents = {
        "images": [
            {"size": "20x20", "idiom": "iphone", "filename": "Icon-App-20x20@2x.png", "scale": "2x"},
            {"size": "20x20", "idiom": "iphone", "filename": "Icon-App-20x20@3x.png", "scale": "3x"},
            {"size": "29x29", "idiom": "iphone", "filename": "Icon-App-29x29@1x.png", "scale": "1x"},
            {"size": "29x29", "idiom": "iphone", "filename": "Icon-App-29x29@2x.png", "scale": "2x"},
            {"size": "29x29", "idiom": "iphone", "filename": "Icon-App-29x29@3x.png", "scale": "3x"},
            {"size": "40x40", "idiom": "iphone", "filename": "Icon-App-40x40@2x.png", "scale": "2x"},
            {"size": "40x40", "idiom": "iphone", "filename": "Icon-App-40x40@3x.png", "scale": "3x"},
            {"size": "60x60", "idiom": "iphone", "filename": "Icon-App-60x60@2x.png", "scale": "2x"},
            {"size": "60x60", "idiom": "iphone", "filename": "Icon-App-60x60@3x.png", "scale": "3x"},
            {"size": "20x20", "idiom": "ipad", "filename": "Icon-App-20x20@1x.png", "scale": "1x"},
            {"size": "20x20", "idiom": "ipad", "filename": "Icon-App-20x20@2x.png", "scale": "2x"},
            {"size": "29x29", "idiom": "ipad", "filename": "Icon-App-29x29@1x.png", "scale": "1x"},
            {"size": "29x29", "idiom": "ipad", "filename": "Icon-App-29x29@2x.png", "scale": "2x"},
            {"size": "40x40", "idiom": "ipad", "filename": "Icon-App-40x40@1x.png", "scale": "1x"},
            {"size": "40x40", "idiom": "ipad", "filename": "Icon-App-40x40@2x.png", "scale": "2x"},
            {"size": "76x76", "idiom": "ipad", "filename": "Icon-App-76x76@1x.png", "scale": "1x"},
            {"size": "76x76", "idiom": "ipad", "filename": "Icon-App-76x76@2x.png", "scale": "2x"},
            {"size": "83.5x83.5", "idiom": "ipad", "filename": "Icon-App-83.5x83.5@2x.png", "scale": "2x"},
            {"size": "1024x1024", "idiom": "ios-marketing", "filename": "Icon-App-1024x1024@1x.png", "scale": "1x"}
        ],
        "info": {"version": 1, "author": "xcode"}
    }
    
    import json
    contents_path = os.path.join(base_path, 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json')
    ensure_directory(os.path.dirname(contents_path))
    
    with open(contents_path, 'w') as f:
        json.dump(contents, f, indent=2)
    
    print(f"  Created: {contents_path}")

def create_macos_contents_json(base_path):
    """Create Contents.json file for macOS icons."""
    contents = {
        "images": [
            {"size": "16x16", "idiom": "mac", "filename": "app_icon_16.png", "scale": "1x"},
            {"size": "16x16", "idiom": "mac", "filename": "app_icon_32.png", "scale": "2x"},
            {"size": "32x32", "idiom": "mac", "filename": "app_icon_32.png", "scale": "1x"},
            {"size": "32x32", "idiom": "mac", "filename": "app_icon_64.png", "scale": "2x"},
            {"size": "128x128", "idiom": "mac", "filename": "app_icon_128.png", "scale": "1x"},
            {"size": "128x128", "idiom": "mac", "filename": "app_icon_256.png", "scale": "2x"},
            {"size": "256x256", "idiom": "mac", "filename": "app_icon_256.png", "scale": "1x"},
            {"size": "256x256", "idiom": "mac", "filename": "app_icon_512.png", "scale": "2x"},
            {"size": "512x512", "idiom": "mac", "filename": "app_icon_512.png", "scale": "1x"},
            {"size": "512x512", "idiom": "mac", "filename": "app_icon_1024.png", "scale": "2x"}
        ],
        "info": {"version": 1, "author": "xcode"}
    }
    
    import json
    contents_path = os.path.join(base_path, 'macos/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json')
    ensure_directory(os.path.dirname(contents_path))
    
    with open(contents_path, 'w') as f:
        json.dump(contents, f, indent=2)
    
    print(f"  Created: {contents_path}")

def find_flutter_project(start_path):
    """Find Flutter project root by looking for pubspec.yaml."""
    current = os.path.abspath(start_path)
    while current != os.path.dirname(current):  # Not at filesystem root
        if os.path.exists(os.path.join(current, 'pubspec.yaml')):
            return current
        current = os.path.dirname(current)
    return None

def update_web_manifest(project_root):
    """Update web/manifest.json to reference the new icons."""
    manifest_path = os.path.join(project_root, 'web', 'manifest.json')
    
    if not os.path.exists(manifest_path):
        print(f"  Web manifest not found at {manifest_path}, skipping...")
        return
    
    try:
        import json
        import shutil
        from datetime import datetime
        
        # Create backup first
        backup_path = manifest_path + f".backup_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        shutil.copy2(manifest_path, backup_path)
        print(f"  Created backup: {backup_path}")
        
        with open(manifest_path, 'r') as f:
            manifest = json.load(f)
        
        # Update icons array
        manifest['icons'] = [
            {
                "src": "icons/Icon-192.png",
                "sizes": "192x192",
                "type": "image/png"
            },
            {
                "src": "icons/Icon-512.png",
                "sizes": "512x512",
                "type": "image/png"
            },
            {
                "src": "icons/Icon-maskable-192.png",
                "sizes": "192x192",
                "type": "image/png",
                "purpose": "maskable"
            },
            {
                "src": "icons/Icon-maskable-512.png",
                "sizes": "512x512",
                "type": "image/png",
                "purpose": "maskable"
            }
        ]
        
        with open(manifest_path, 'w') as f:
            json.dump(manifest, f, indent=2)
        
        print(f"  Updated: {manifest_path}")
        
    except Exception as e:
        print(f"  Warning: Could not update web manifest: {e}")

def update_android_gradle(project_root):
    """Check and suggest Android gradle updates if needed."""
    gradle_path = os.path.join(project_root, 'android', 'app', 'build.gradle')
    
    if not os.path.exists(gradle_path):
        print(f"  Android build.gradle not found, skipping...")
        return
    
    try:
        with open(gradle_path, 'r') as f:
            content = f.read()
        
        # Check if adaptive icon is configured
        if 'android:icon="@mipmap/ic_launcher"' in content:
            if '@mipmap/ic_launcher_foreground' not in content:
                print(f"  Note: Consider updating {gradle_path} to use adaptive icons")
                print(f"        Add android:foreground=\"@mipmap/ic_launcher_foreground\" to application tag")
        
    except Exception as e:
        print(f"  Warning: Could not check Android gradle: {e}")

def run_flutter_clean(project_root):
    """Run flutter clean if Flutter is available."""
    try:
        import subprocess
        
        # Check if flutter command is available
        result = subprocess.run(['flutter', '--version'], 
                              capture_output=True, 
                              text=True, 
                              cwd=project_root,
                              timeout=10)
        
        if result.returncode == 0:
            print("  Running 'flutter clean'...")
            clean_result = subprocess.run(['flutter', 'clean'], 
                                        capture_output=True, 
                                        text=True, 
                                        cwd=project_root,
                                        timeout=30)
            
            if clean_result.returncode == 0:
                print("  ✅ Flutter clean completed successfully")
            else:
                print(f"  ⚠️  Flutter clean failed: {clean_result.stderr}")
        else:
            print("  Flutter command not found, skipping flutter clean")
            
    except (subprocess.TimeoutExpired, FileNotFoundError, Exception) as e:
        print(f"  Could not run flutter clean: {e}")

def integrate_with_flutter_project(base_path, platforms):
    """Automatically integrate generated icons with Flutter project."""
    
    # Try to find Flutter project
    flutter_project = find_flutter_project(base_path)
    
    if not flutter_project:
        print("\n⚠️  Flutter project not detected (no pubspec.yaml found)")
        print("   Generated icons are in current directory - copy them to your Flutter project manually")
        return
    
    print(f"\n🔍 Found Flutter project at: {flutter_project}")
    print("🔧 Integrating with Flutter project...")
    
    # Update web manifest
    if 'web' in platforms:
        print("\n📱 Updating web manifest...")
        update_web_manifest(flutter_project)
    
    # Check Android configuration
    if 'android' in platforms:
        print("\n🤖 Checking Android configuration...")
        update_android_gradle(flutter_project)
    
    # iOS and macOS Contents.json files are already created
    if 'ios' in platforms:
        print("\n🍎 iOS Contents.json already created")
    
    if 'macos' in platforms:
        print("\n💻 macOS Contents.json already created")
    
    # Run flutter clean
    print("\n🧹 Cleaning Flutter build cache...")
    run_flutter_clean(flutter_project)

def main():
    parser = argparse.ArgumentParser(description='Generate Flutter app icons for all platforms')
    parser.add_argument('input_image', help='Path to input PNG or JPG image')
    parser.add_argument('-o', '--output', default='.', help='Output directory (default: current directory)')
    parser.add_argument('-p', '--platforms', nargs='+', 
                       choices=list(ICON_CONFIGS.keys()) + ['all'],
                       default=['all'], 
                       help='Platforms to generate icons for (default: all)')
    
    args = parser.parse_args()
    
    # Validate input file
    if not os.path.exists(args.input_image):
        print(f"Error: Input file '{args.input_image}' not found!")
        sys.exit(1)
    
    # Check file extension
    ext = os.path.splitext(args.input_image)[1].lower()
    if ext not in ['.png', '.jpg', '.jpeg']:
        print(f"Error: Unsupported file format '{ext}'. Please use PNG or JPG.")
        sys.exit(1)
    
    # Handle 'all' platform selection
    platforms = args.platforms
    if 'all' in platforms:
        platforms = list(ICON_CONFIGS.keys())
    
    print(f"Flutter Icon Generator")
    print(f"Input: {args.input_image}")
    print(f"Output: {args.output}")
    print(f"Platforms: {', '.join(platforms)}")
    print("-" * 50)
    
    # Generate icons
    generate_icons(args.input_image, args.output, platforms)
    
    # Create metadata files for iOS and macOS
    if 'ios' in platforms:
        create_ios_contents_json(args.output)
    
    if 'macos' in platforms:
        create_macos_contents_json(args.output)
    
    # Automatically integrate with Flutter project
    integrate_with_flutter_project(args.output, platforms)
    
    print("\n🎉 Icon generation and integration complete!")
    print("\n✅ What was done automatically:")
    print("   • Generated all platform-specific icons")
    print("   • Created proper folder structure")
    print("   • Updated web/manifest.json (if web platform selected)")
    print("   • Created iOS/macOS Contents.json files")
    print("   • Ran 'flutter clean' (if Flutter CLI available)")
    print("\n🚀 Your app is ready to build with new icons!")

if __name__ == '__main__':
    main()