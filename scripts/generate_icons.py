"""Generate crisp supersampled Moho Pro 14 toolbar icons for MohoStudioMCP_Poller.

Produces standard (24x20), HiDPI @2x (48x40), and _large (48x40) RGBA PNGs using
pure Python stdlib (zlib + struct) with 12x12 supersampled signed-distance fields.
"""

import math
import pathlib
import struct
import tempfile
import zlib


REPO = pathlib.Path(__file__).resolve().parents[1]
PLUGIN_DIR = REPO / "moho-plugin"


def clamp(v, lo=0.0, hi=1.0):
    return lo if v < lo else (hi if v > hi else v)


def smoothstep(edge0, edge1, x):
    t = clamp((x - edge0) / (edge1 - edge0))
    return t * t * (3.0 - 2.0 * t)


def sd_circle(px, py, cx, cy, r):
    return math.hypot(px - cx, py - cy) - r


def sd_segment(px, py, ax, ay, bx, by):
    pax, pay = px - ax, py - ay
    bax, bay = bx - ax, by - ay
    denom = bax * bax + bay * bay
    h = clamp((pax * bax + pay * bay) / denom) if denom > 1e-9 else 0.0
    return math.hypot(pax - bax * h, pay - bay * h)


def sd_diamond(px, py, cx, cy, rx, ry):
    dx = abs(px - cx) / rx
    dy = abs(py - cy) / ry
    # Exact scaled L1 distance approximation
    return (dx + dy - 1.0) * min(rx, ry) / math.sqrt(2.0)


def sd_star4(px, py, cx, cy, outer_r, inner_r):
    """Crisp 4-point spark / keyframe star (positive outside, negative inside)."""
    x = abs(px - cx)
    y = abs(py - cy)
    if y > x:
        x, y = y, x
    # Line from (outer_r, 0) to (inner_r, inner_r)
    ax, ay = outer_r, 0.0
    bx, by = inner_r, inner_r
    ex, ey = bx - ax, by - ay
    # Outward normal (pointing right/up away from origin)
    elen = math.hypot(ex, ey)
    nx, ny = ey / elen, -ex / elen
    # Signed distance to the edge segment with interior sign
    t = clamp(((x - ax) * ex + (y - ay) * ey) / (elen * elen))
    qx, qy = ax + t * ex, ay + t * ey
    dist = math.hypot(x - qx, y - qy)
    side = (x - ax) * nx + (y - ay) * ny
    return dist if side >= 0.0 else -dist


def blend_over(dst, src):
    """Porter-Duff src-over-dst in straight float RGBA [0..1]."""
    sr, sg, sb, sa = src
    dr, dg, db, da = dst
    out_a = sa + da * (1.0 - sa)
    if out_a <= 1e-6:
        return (0.0, 0.0, 0.0, 0.0)
    out_r = (sr * sa + dr * da * (1.0 - sa)) / out_a
    out_g = (sg * sa + dg * da * (1.0 - sa)) / out_a
    out_b = (sb * sa + db * da * (1.0 - sa)) / out_a
    return (out_r, out_g, out_b, out_a)


def sample_icon(u, v):
    """Evaluate icon RGBA at normalized pixel coords in 24x20 design space.

    Design concept: "MCP Live Bridge Hub"
      - Outer sleek dark-haloed pearl-silver studio link ring (broken gracefully
        at left & right by two live connection nodes: AI Agent <-> Moho Studio)
      - Central vivid cyan-teal 4-point AI spark / animation keyframe diamond
      - Two warm-mint live telemetry ping dots on the node pins
    """
    cx, cy = 12.0, 10.0

    # --- 1. Outer bridge arcs (top and bottom curved link arms between left/right nodes) ---
    # Elliptical ring centered at (12, 10), rx=8.0, ry=6.6, open around left/right node hubs
    dx = (u - cx) / 8.0
    dy = (v - cy) / 6.6
    r_ell = math.hypot(dx, dy)
    # Approximate Euclidean distance to ellipse perimeter
    d_ring = abs(r_ell - 1.0) * 7.2 - 0.85

    # Cut clean gaps at left (x < 6.4) and right (x > 17.6) near midline so nodes sit cleanly
    ang = math.atan2(v - cy, u - cx)
    # Keep top arc (ang in [-148..-32 deg]) and bottom arc (ang in [32..148 deg])
    abs_ang = abs(ang)
    # Smoothly mask angular ends near 0 and pi
    in_arc_deg = math.degrees(abs_ang)
    # Distance from the arc angular window [34 deg .. 146 deg]
    if in_arc_deg < 34.0:
        ang_excess = (34.0 - in_arc_deg) * (math.pi / 180.0) * 7.2
    elif in_arc_deg > 146.0:
        ang_excess = (in_arc_deg - 146.0) * (math.pi / 180.0) * 7.2
    else:
        ang_excess = 0.0
    d_arcs = math.hypot(max(d_ring, 0.0), ang_excess) if ang_excess > 0.0 else d_ring

    # Rounded endcaps at the 4 arc tips (at 34, 146, -34, -146 deg on ellipse)
    for deg in (34.0, 146.0, -34.0, -146.0):
        rad = math.radians(deg)
        tx = cx + 8.0 * math.cos(rad)
        ty = cy + 6.6 * math.sin(rad)
        d_arcs = min(d_arcs, sd_circle(u, v, tx, ty, 0.85))

    # --- 2. Left & Right MCP Bridge Node Pins (connected endpoints) ---
    lx, ly = 4.0, 10.0
    rx_p, ry_p = 20.0, 10.0
    d_node_l = sd_circle(u, v, lx, ly, 2.35)
    d_node_r = sd_circle(u, v, rx_p, ry_p, 2.35)
    d_nodes_outer = min(d_node_l, d_node_r)
    d_nodes_hole = min(sd_circle(u, v, lx, ly, 1.05), sd_circle(u, v, rx_p, ry_p, 1.05))
    d_nodes_ring = max(d_nodes_outer, -d_nodes_hole)

    # Short horizontal connector struts bridging inner nodes slightly toward core
    d_strut_l = sd_segment(u, v, 6.2, 10.0, 7.2, 10.0) - 0.65
    d_strut_r = sd_segment(u, v, 16.8, 10.0, 17.8, 10.0) - 0.65

    d_silver = min(d_arcs, d_nodes_ring, d_strut_l, d_strut_r)

    # --- 3. Central 4-point AI Spark / Animation Keyframe Core ---
    d_spark = sd_star4(u, v, cx, cy, outer_r=5.2, inner_r=1.65)
    # Inner bright highlight diamond
    d_spark_inner = sd_star4(u, v, cx, cy, outer_r=2.55, inner_r=0.80)

    # Small cyan core dots inside the left and right node rings
    d_pin_dots = min(sd_circle(u, v, lx, ly, 0.95), sd_circle(u, v, rx_p, ry_p, 0.95))

    # --- Compose layers with crisp dark contrast halo for light & dark Moho themes ---
    col = (0.0, 0.0, 0.0, 0.0)

    # Subtle dark backing shadow/halo behind entire emblem
    d_all = min(d_silver, d_spark, d_nodes_outer)
    halo_a = (1.0 - smoothstep(-0.08, 1.05, d_all)) * 0.62
    if halo_a > 0.001:
        col = blend_over(col, (0.05, 0.08, 0.11, halo_a))

    # Silver-white structural arcs & node rings with subtle top-to-bottom sheen
    silver_a = 1.0 - smoothstep(-0.24, 0.24, d_silver)
    if silver_a > 0.001:
        grad = clamp((v - 3.0) / 14.0)
        sr = 0.98 - 0.12 * grad
        sg = 0.99 - 0.10 * grad
        sb = 1.00 - 0.06 * grad
        col = blend_over(col, (sr, sg, sb, silver_a))

    # Teal/cyan glow fill inside left/right pin nodes
    pin_a = 1.0 - smoothstep(-0.24, 0.24, d_pin_dots)
    if pin_a > 0.001:
        col = blend_over(col, (0.18, 0.92, 0.88, pin_a))

    # Vivid Moho-teal 4-point spark / keyframe core with vertical luminance gradient
    spark_a = 1.0 - smoothstep(-0.24, 0.24, d_spark)
    if spark_a > 0.001:
        sg_t = clamp((v - 5.0) / 10.0)
        tr = 0.22 - 0.16 * sg_t
        tg = 0.96 - 0.22 * sg_t
        tb = 0.92 - 0.12 * sg_t
        col = blend_over(col, (tr, tg, tb, spark_a))

    # Bright icy-white center highlight star
    inner_a = (1.0 - smoothstep(-0.24, 0.24, d_spark_inner)) * 0.92
    if inner_a > 0.001:
        col = blend_over(col, (0.95, 1.00, 1.00, inner_a))

    return col


def render_rgba(width, height, ssaa=10):
    """Render width x height RGBA image with ssaa x ssaa supersampling."""
    buf = bytearray(width * height * 4)
    sx = 24.0 / width
    sy = 20.0 / height
    inv_n = 1.0 / (ssaa * ssaa)
    for y in range(height):
        for x in range(width):
            pr = pg = pb = pa = 0.0
            for j in range(ssaa):
                v = (y + (j + 0.5) / ssaa) * sy
                for i in range(ssaa):
                    u = (x + (i + 0.5) / ssaa) * sx
                    r, g, b, a = sample_icon(u, v)
                    pr += r * a
                    pg += g * a
                    pb += b * a
                    pa += a
            pa *= inv_n
            if pa > 1e-5:
                r = clamp((pr * inv_n) / pa)
                g = clamp((pg * inv_n) / pa)
                b = clamp((pb * inv_n) / pa)
            else:
                r = g = b = 0.0
            idx = (y * width + x) * 4
            buf[idx] = int(round(r * 255.0))
            buf[idx + 1] = int(round(g * 255.0))
            buf[idx + 2] = int(round(b * 255.0))
            buf[idx + 3] = int(round(clamp(pa) * 255.0))
    return bytes(buf)


def write_png_rgba(path, width, height, rgba_bytes):
    def chunk(tag, data):
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)  # filter type None
        raw.extend(rgba_bytes[y * stride : (y + 1) * stride])

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )
    pathlib.Path(path).write_bytes(png)


def render_preview_sheet(out_path, rgba_24, rgba_48):
    """Build a crisp preview sheet on dark (#323232), selected (#4E6E72), and light (#E2E4E6) Moho tiles."""
    pw, ph = 360, 140
    canvas = bytearray([30, 30, 30, 255] * (pw * ph))

    def fill_rect(x0, y0, w, h, rgb):
        for yy in range(max(0, y0), min(ph, y0 + h)):
            for xx in range(max(0, x0), min(pw, x0 + w)):
                i = (yy * pw + xx) * 4
                canvas[i : i + 4] = bytes([rgb[0], rgb[1], rgb[2], 255])

    def blit_scaled(src, sw, sh, ox, oy, scale):
        for sy in range(sh):
            for sx in range(sw):
                si = (sy * sw + sx) * 4
                sr, sg, sb, sa = src[si], src[si + 1], src[si + 2], src[si + 3]
                if sa == 0:
                    continue
                af = sa / 255.0
                for dy in range(scale):
                    for dx in range(scale):
                        tx, ty = ox + sx * scale + dx, oy + sy * scale + dy
                        if 0 <= tx < pw and 0 <= ty < ph:
                            di = (ty * pw + tx) * 4
                            canvas[di] = int(round(sr * af + canvas[di] * (1.0 - af)))
                            canvas[di + 1] = int(round(sg * af + canvas[di + 1] * (1.0 - af)))
                            canvas[di + 2] = int(round(sb * af + canvas[di + 2] * (1.0 - af)))

    tiles = [
        (16, 16, 104, 108, (50, 50, 50)),       # Moho dark toolbar
        (128, 16, 104, 108, (78, 110, 114)),    # Moho active/selected teal box
        (240, 16, 104, 108, (226, 228, 230)),   # Light theme check
    ]
    for tx, ty, tw, th, bg in tiles:
        fill_rect(tx, ty, tw, th, bg)
        # 2x magnified 48x40 on top (96x80)
        blit_scaled(rgba_48, 48, 40, tx + 4, ty + 4, 2)
        # Actual 1x 24x20 bottom-left and 1x 48x40 bottom-right? Just 24x20 centered at bottom
        blit_scaled(rgba_24, 24, 20, tx + 40, ty + 86, 1)

    write_png_rgba(out_path, pw, ph, bytes(canvas))


def main():
    rgba_24 = render_rgba(24, 20, ssaa=12)
    rgba_48 = render_rgba(48, 40, ssaa=10)

    out_1x = PLUGIN_DIR / "MohoStudioMCP_Poller.png"
    out_2x = PLUGIN_DIR / "MohoStudioMCP_Poller@2x.png"
    out_lg = PLUGIN_DIR / "MohoStudioMCP_Poller_large.png"

    write_png_rgba(out_1x, 24, 20, rgba_24)
    write_png_rgba(out_2x, 48, 40, rgba_48)
    write_png_rgba(out_lg, 48, 40, rgba_48)

    preview = pathlib.Path(tempfile.gettempdir()) / "moho_poller_icon_preview.png"
    render_preview_sheet(preview, rgba_24, rgba_48)
    print(f"Generated: {out_1x.name} ({out_1x.stat().st_size}B), {out_2x.name} ({out_2x.stat().st_size}B), {out_lg.name} ({out_lg.stat().st_size}B)")
    print(f"Preview: {preview}")


if __name__ == "__main__":
    main()
