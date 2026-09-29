import os
import json
import zlib
import struct

def make_png(width, height, color):
    # Minimal PNG generator
    def chunk(type, data):
        return struct.pack('>I', len(data)) + type + data + struct.pack('>I', zlib.crc32(type + data) & 0xffffffff)

    png = b'\x89PNG\r\n\x1a\n'
    ihdr = struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)
    png += chunk(b'IHDR', ihdr)
    
    # Raw pixel data: filter byte (0) + RGB pixels
    row = b'\x00' + bytes(color) * width
    raw_data = row * height
    idat = zlib.compress(raw_data)
    
    png += chunk(b'IDAT', idat)
    png += chunk(b'IEND', b'')
    return png

os.makedirs("App/Assets.xcassets/AppIcon.appiconset", exist_ok=True)
png_data = make_png(1024, 1024, [0, 122, 255]) # blue

with open("App/Assets.xcassets/AppIcon.appiconset/icon-1024.png", "wb") as f:
    f.write(png_data)

contents = {
  "images" : [
    {
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024",
      "filename" : "icon-1024.png"
    }
  ],
  "info" : {
    "version" : 1,
    "author" : "xcode"
  }
}

with open("App/Assets.xcassets/AppIcon.appiconset/Contents.json", "w") as f:
    json.dump(contents, f, indent=2)

print("Icon generated successfully.")
