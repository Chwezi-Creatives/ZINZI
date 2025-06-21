import os
import sys
from PIL import Image
from pathlib import Path

# Android icon sizes and their corresponding directories
ANDROID_ICON_SIZES = {
    "mipmap-hdpi": 72,
    "mipmap-mdpi": 48,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

def create_android_icons(input_image_path, flutter_project_root="."):
    try:
        # Open the input image
        with Image.open(input_image_path) as img:
            # Convert to RGBA if not already (for PNG transparency)
            if img.mode != 'RGBA':
                img = img.convert('RGBA')
                
            # Check if we're in a Flutter project by looking for android/app/src/main/res
            android_res_dir = os.path.join(flutter_project_root, "android", "app", "src", "main", "res")
            
            if os.path.exists(android_res_dir):
                output_base = android_res_dir
                print(f"Found Android resource directory at: {android_res_dir}")
            else:
                # Create fallback directory
                output_base = os.path.join(flutter_project_root, "my_custom_android_icons")
                os.makedirs(output_base, exist_ok=True)
                print(f"Android resource directory not found. Creating icons in: {output_base}")
            
            # Generate icons for each size
            for directory, size in ANDROID_ICON_SIZES.items():
                # Create directory if it doesn't exist
                output_dir = os.path.join(output_base, directory)
                os.makedirs(output_dir, exist_ok=True)
                
                # Resize the image
                resized_img = img.resize((size, size), Image.Resampling.LANCZOS)
                
                # Save as ic_launcher.png in the appropriate directory
                output_path = os.path.join(output_dir, "ic_launcher.png")
                resized_img.save(output_path, "PNG")
                print(f"Created icon: {output_path}")
                
            print("Android icons generated successfully!")
            
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python generate_android_icons.py <input_image> [flutter_project_root]")
        print("Example: python generate_android_icons.py my_icon.png")
        sys.exit(1)
        
    input_image = sys.argv[1]
    project_root = sys.argv[2] if len(sys.argv) > 2 else "."
    
    if not os.path.exists(input_image):
        print(f"Error: Input image '{input_image}' not found!")
        sys.exit(1)
        
    create_android_icons(input_image, project_root)