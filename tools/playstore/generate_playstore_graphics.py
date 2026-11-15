"""Generate Play Store graphics for MacroSnap"""
from PIL import Image, ImageDraw, ImageFont
import math
import os

OUTPUT_DIR = os.path.dirname(os.path.abspath(__file__))

def create_app_icon(size=512):
    """Create the 512x512 app icon"""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Create rounded rectangle background
    corner_radius = int(size * 0.21)  # ~108px for 512
    # Draw the rounded rectangle
    mask = Image.new('L', (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle([(0, 0), (size-1, size-1)], corner_radius, fill=255)
    
    # Gradient background (simulate with solid + overlay)
    for y in range(size):
        for x in range(size):
            # Diagonal gradient
            t = (x + y) / (2 * size)
            r = int(4 + t * (16 - 4))
            g = int(120 + t * (185 - 120))
            b = int(87 + t * (129 - 87))
            img.putpixel((x, y), (r, g, b, 255))
    
    # Apply mask for rounded corners
    img.putalpha(mask)
    
    draw = ImageDraw.Draw(img)
    
    # Inner lighter circle
    cx, cy = size // 2, size // 2
    circle_r = int(size * 0.3125)  # 160 for 512
    circle_mask = Image.new('L', (size, size), 0)
    circle_draw = ImageDraw.Draw(circle_mask)
    circle_draw.ellipse(
        [cx - circle_r, cy - circle_r, cx + circle_r, cy + circle_r],
        fill=80  # ~30% opacity
    )
    
    # Overlay the inner circle
    circle_overlay = Image.new('RGBA', (size, size), (52, 211, 153, 0))
    for y in range(size):
        for x in range(size):
            alpha = circle_mask.getpixel((x, y))
            if alpha > 0:
                orig = img.getpixel((x, y))
                new_a = int(alpha * 0.25)
                img.putpixel((x, y), (
                    orig[0], 
                    min(255, orig[1] + 10),
                    min(255, orig[2] + 5),
                    orig[3]
                ))
    
    draw = ImageDraw.Draw(img)
    
    # White dot / leaf (top-right area)
    dot_r = int(size * 0.039)  # 20 for 512
    dot_cx = int(size * 0.723)  # 370
    dot_cy = int(size * 0.273)  # 140
    draw.ellipse(
        [dot_cx - dot_r - 20, dot_cy - dot_r - 20, dot_cx + dot_r + 20, dot_cy + dot_r + 20],
        fill=(167, 243, 208, 255)  # #A7F3D0
    )
    draw.ellipse(
        [dot_cx - dot_r, dot_cy - dot_r, dot_cx + dot_r, dot_cy + dot_r],
        fill=(255, 255, 255, 255)
    )
    
    # Letter M
    try:
        font = ImageFont.truetype("arial.ttf", int(size * 0.43))
    except:
        try:
            font = ImageFont.truetype("segoeui.ttf", int(size * 0.43))
        except:
            font = ImageFont.load_default()
    
    bbox = draw.textbbox((0, 0), "M", font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    tx = (size - tw) // 2 - 10
    ty = (size - th) // 2 + 15
    
    # Shadow
    draw.text((tx + 3, ty + 5), "M", fill=(0, 80, 50, 60), font=font)
    draw.text((tx, ty), "M", fill=(255, 255, 255, 255), font=font)
    
    path = os.path.join(OUTPUT_DIR, "playstore_icon_512.png")
    img.save(path, "PNG")
    print(f"App icon saved: {path} ({img.size[0]}x{img.size[1]})")
    return path


def create_feature_graphic(width=1024, height=500):
    """Create the 1024x500 feature graphic"""
    img = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Gradient background
    for y in range(height):
        for x in range(width):
            t = (x * 0.6 + y * 0.4) / (width * 0.6 + height * 0.4)
            r = int(6 + t * (52 - 6))
            g = int(78 + t * (185 - 78))
            b = int(59 + t * (153 - 59))
            img.putpixel((x, y), (r, g, b, 255))
    
    draw = ImageDraw.Draw(img)
    
    # Decorative circles (translucent)
    circle_overlay = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    circle_draw = ImageDraw.Draw(circle_overlay)
    
    # Large circle top-right
    circle_draw.ellipse([width-200, -100, width+100, 200], fill=(255, 255, 255, 12))
    # Medium circle bottom
    circle_draw.ellipse([width//2-100, height-120, width//2+100, height+80], fill=(255, 255, 255, 20))
    # Small accent circle
    circle_draw.ellipse([width//2+100, 30, width//2+250, 180], fill=(167, 243, 208, 38))
    
    img = Image.alpha_composite(img, circle_overlay)
    draw = ImageDraw.Draw(img)
    
    # Text area
    left_margin = 80
    
    # App name
    try:
        name_font = ImageFont.truetype("arialbd.ttf", 72)
    except:
        try:
            name_font = ImageFont.truetype("arial.ttf", 72)
        except:
            name_font = ImageFont.load_default()
    
    draw.text((left_margin, 80), "MacroSnap", fill=(255, 255, 255, 255), font=name_font)
    
    # Tagline
    try:
        tag_font = ImageFont.truetype("arial.ttf", 28)
    except:
        tag_font = ImageFont.load_default()
    
    draw.text((left_margin, 170), "AI-Powered Nutrition Tracker", fill=(255, 255, 255, 230), font=tag_font)
    draw.text((left_margin, 208), "for Indian Food", fill=(255, 255, 255, 230), font=tag_font)
    
    # Feature items
    try:
        feat_font = ImageFont.truetype("arial.ttf", 20)
        icon_font = ImageFont.truetype("arial.ttf", 22)
    except:
        feat_font = ImageFont.load_default()
        icon_font = feat_font
    
    features = [("📸", "AI Food Scan"), ("📊", "Macro Tracking"), ("🔥", "Streak System")]
    y_start = 280
    for i, (icon, label) in enumerate(features):
        x_pos = left_margin + i * 180
        # Icon background
        draw.rounded_rectangle([x_pos, y_start, x_pos + 40, y_start + 40], 8, fill=(255, 255, 255, 38))
        draw.text((x_pos + 8, y_start + 5), icon, fill=(255, 255, 255, 200), font=icon_font)
        draw.text((x_pos + 50, y_start + 8), label, fill=(255, 255, 255, 220), font=feat_font)
    
    # Phone mockup (right side)
    phone_x = width - 320
    phone_y = 50
    phone_w = 240
    phone_h = 400
    corner = 24
    
    # Phone body
    draw.rounded_rectangle(
        [phone_x, phone_y, phone_x + phone_w, phone_y + phone_h],
        corner, fill=(26, 26, 46, 255), outline=(255, 255, 255, 50), width=2
    )
    
    # Phone screen area
    sx, sy = phone_x + 10, phone_y + 10
    sw, sh = phone_w - 20, phone_h - 20
    draw.rounded_rectangle([sx, sy, sx + sw, sy + sh], 18, fill=(15, 23, 42, 255))
    
    # "Today's Macros" title
    try:
        small_font = ImageFont.truetype("arial.ttf", 14)
        ring_font = ImageFont.truetype("arial.ttf", 22)
        bar_font = ImageFont.truetype("arial.ttf", 10)
    except:
        small_font = ImageFont.load_default()
        ring_font = small_font
        bar_font = small_font
    
    title_y = sy + 30
    draw.text((sx + sw//2 - 50, title_y), "Today's Macros", fill=(255, 255, 255, 230), font=small_font)
    
    # Macro ring
    ring_cx = sx + sw // 2
    ring_cy = title_y + 80
    ring_r = 55
    
    # Colored ring segments
    colors = [(5, 150, 105), (251, 191, 36), (239, 68, 68), (37, 99, 235)]
    angles = [100, 80, 60, 120]
    start = -90
    for color, angle in zip(colors, angles):
        draw.arc(
            [ring_cx - ring_r, ring_cy - ring_r, ring_cx + ring_r, ring_cy + ring_r],
            start, start + angle, fill=color, width=10
        )
        start += angle + 2
    
    draw.text((ring_cx - 25, ring_cy - 10), "1,850", fill=(255, 255, 255, 255), font=ring_font)
    
    # Macro bars
    bar_data = [
        ("Protein", "68g", 0.75, (5, 150, 105)),
        ("Carbs", "220g", 0.60, (217, 119, 6)),
        ("Fats", "52g", 0.45, (220, 38, 38)),
        ("Fiber", "28g", 0.85, (37, 99, 235)),
    ]
    bar_y = ring_cy + ring_r + 25
    bar_w = sw - 40
    for label, val, pct, color in bar_data:
        draw.text((sx + 20, bar_y), f"{label}", fill=(255, 255, 255, 120), font=bar_font)
        draw.text((sx + 20 + bar_w - 30, bar_y), val, fill=(255, 255, 255, 120), font=bar_font)
        bar_y += 14
        draw.rounded_rectangle([sx + 20, bar_y, sx + 20 + bar_w, bar_y + 8], 4, fill=(255, 255, 255, 25))
        draw.rounded_rectangle([sx + 20, bar_y, sx + 20 + int(bar_w * pct), bar_y + 8], 4, fill=color)
        bar_y += 22
    
    path = os.path.join(OUTPUT_DIR, "playstore_feature_1024x500.png")
    img = img.convert('RGB')
    img.save(path, "PNG")
    print(f"Feature graphic saved: {path} ({img.size[0]}x{img.size[1]})")
    return path


def create_screenshot_template(width=1080, height=1920):
    """Create a phone screenshot template"""
    img = Image.new('RGB', (width, height), (15, 23, 42))
    draw = ImageDraw.Draw(img)
    
    try:
        title_font = ImageFont.truetype("arialbd.ttf", 48)
        body_font = ImageFont.truetype("arial.ttf", 32)
        small_font = ImageFont.truetype("arial.ttf", 24)
    except:
        title_font = ImageFont.load_default()
        body_font = title_font
        small_font = title_font
    
    # Status bar area
    draw.rectangle([0, 0, width, 100], fill=(5, 150, 105))
    draw.text((width//2 - 120, 35), "MacroSnap", fill=(255, 255, 255), font=body_font)
    
    # Macro ring
    ring_cx, ring_cy = width // 2, 500
    ring_r = 180
    colors = [(5, 150, 105), (251, 191, 36), (239, 68, 68), (37, 99, 235)]
    angles = [100, 80, 60, 120]
    start = -90
    for color, angle in zip(colors, angles):
        draw.arc(
            [ring_cx - ring_r, ring_cy - ring_r, ring_cx + ring_r, ring_cy + ring_r],
            start, start + angle, fill=color, width=24
        )
        start += angle + 2
    draw.text((ring_cx - 70, ring_cy - 25), "1,850", fill=(255, 255, 255), font=title_font)
    draw.text((ring_cx - 50, ring_cy + 30), "calories", fill=(255, 255, 255, 150), font=small_font)
    
    # Bars
    bar_data = [
        ("Protein", "68g / 120g", 0.57, (5, 150, 105)),
        ("Carbs", "220g / 250g", 0.88, (217, 119, 6)),
        ("Fats", "52g / 65g", 0.80, (220, 38, 38)),
        ("Fiber", "28g / 30g", 0.93, (37, 99, 235)),
    ]
    bar_y = ring_cy + ring_r + 80
    bar_w = width - 160
    for label, val, pct, color in bar_data:
        draw.text((80, bar_y), f"{label}  {val}", fill=(255, 255, 255, 200), font=body_font)
        bar_y += 45
        draw.rounded_rectangle([80, bar_y, 80 + bar_w, bar_y + 16], 8, fill=(255, 255, 255, 25))
        draw.rounded_rectangle([80, bar_y, 80 + int(bar_w * pct), bar_y + 16], 8, fill=color)
        bar_y += 40
    
    path = os.path.join(OUTPUT_DIR, "playstore_screenshot_macros.png")
    img.save(path, "PNG")
    print(f"Screenshot saved: {path} ({img.size[0]}x{img.size[1]})")
    return path


def create_screenshot_scan(width=1080, height=1920):
    """Create a food scan screenshot"""
    img = Image.new('RGB', (width, height), (15, 23, 42))
    draw = ImageDraw.Draw(img)
    
    try:
        title_font = ImageFont.truetype("arialbd.ttf", 48)
        body_font = ImageFont.truetype("arial.ttf", 32)
        small_font = ImageFont.truetype("arial.ttf", 24)
    except:
        title_font = ImageFont.load_default()
        body_font = title_font
        small_font = title_font
    
    # Green header
    draw.rectangle([0, 0, width, 100], fill=(5, 150, 105))
    draw.text((width//2 - 100, 35), "AI Food Scan", fill=(255, 255, 255), font=body_font)
    
    # Camera viewfinder area
    draw.rectangle([60, 140, width-60, 700], outline=(255, 255, 255, 100), width=3)
    draw.text((width//2 - 120, 400), "📸 Point & Scan", fill=(255, 255, 255, 150), font=body_font)
    
    # Corner brackets
    bracket_len = 40
    bw = 4
    # Top-left
    draw.line([(60, 180), (60, 180+bracket_len)], fill=(5, 150, 105), width=bw)
    draw.line([(60, 180), (60+bracket_len, 180)], fill=(5, 150, 105), width=bw)
    # Top-right
    draw.line([(width-60, 180), (width-60, 180+bracket_len)], fill=(5, 150, 105), width=bw)
    draw.line([(width-60, 180), (width-60-bracket_len, 180)], fill=(5, 150, 105), width=bw)
    # Bottom-left
    draw.line([(60, 700), (60, 700-bracket_len)], fill=(5, 150, 105), width=bw)
    draw.line([(60, 700), (60+bracket_len, 700)], fill=(5, 150, 105), width=bw)
    # Bottom-right
    draw.line([(width-60, 700), (width-60, 700-bracket_len)], fill=(5, 150, 105), width=bw)
    draw.line([(width-60, 700), (width-60-bracket_len, 700)], fill=(5, 150, 105), width=bw)
    
    # Results card
    card_y = 740
    draw.rounded_rectangle([60, card_y, width-60, card_y+500], 20, fill=(30, 41, 59))
    draw.text((100, card_y + 20), "🍛 Chicken Biryani", fill=(255, 255, 255), font=title_font)
    
    macros = [
        ("Calories", "350 kcal", (255, 255, 255)),
        ("Protein", "28g", (52, 211, 153)),
        ("Carbs", "45g", (251, 191, 36)),
        ("Fats", "12g", (239, 68, 68)),
    ]
    my = card_y + 90
    for label, val, color in macros:
        draw.text((100, my), label, fill=(150, 150, 150), font=body_font)
        draw.text((width - 200, my), val, fill=color, font=body_font)
        my += 55
    
    # Bottom nav hints
    nav_y = height - 120
    nav_items = ["🏠 Home", "📷 Scan", "📊 Track"]
    nav_width = width // len(nav_items)
    for i, item in enumerate(nav_items):
        nx = i * nav_width + nav_width // 2 - 40
        color = (5, 150, 105) if i == 1 else (150, 150, 150)
        draw.text((nx, nav_y), item, fill=color, font=small_font)
    
    path = os.path.join(OUTPUT_DIR, "playstore_screenshot_scan.png")
    img.save(path, "PNG")
    print(f"Screenshot saved: {path} ({img.size[0]}x{img.size[1]})")
    return path


if __name__ == "__main__":
    print("Generating Play Store graphics...")
    create_app_icon()
    create_feature_graphic()
    create_screenshot_template()
    create_screenshot_scan()
    print("\nAll graphics generated! Files:")
    for f in os.listdir(OUTPUT_DIR):
        if f.startswith("playstore_") and f.endswith(".png"):
            fpath = os.path.join(OUTPUT_DIR, f)
            sz = os.path.getsize(fpath)
            print(f"  {f} ({sz // 1024} KB)")
