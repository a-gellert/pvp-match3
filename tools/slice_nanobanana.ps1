param(
    [string]$ArtDir = "main/assets/art"
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $ArtDir | Out-Null

Add-Type -AssemblyName System.Drawing
$code = @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class SpriteProcessor {
    static int Clamp255(double v) { return v < 0 ? 0 : (v > 255 ? 255 : (int)Math.Round(v)); }

    public static Bitmap LoadCrop(string path, double rx0, double ry0, double rx1, double ry1) {
        using (var src = new Bitmap(path)) {
            int x0 = Math.Max(0, (int)Math.Floor(src.Width * rx0));
            int y0 = Math.Max(0, (int)Math.Floor(src.Height * ry0));
            int x1 = Math.Min(src.Width, (int)Math.Ceiling(src.Width * rx1));
            int y1 = Math.Min(src.Height, (int)Math.Ceiling(src.Height * ry1));
            var rect = new Rectangle(x0, y0, Math.Max(1, x1 - x0), Math.Max(1, y1 - y0));
            return src.Clone(rect, PixelFormat.Format32bppArgb);
        }
    }

    public static int[] FindVerticalValleys(string path, int expectedCols) {
        using (var bmp = new Bitmap(path)) {
            int w = bmp.Width, h = bmp.Height;
            var bd = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            byte[] buf = new byte[Math.Abs(bd.Stride) * h];
            Marshal.Copy(bd.Scan0, buf, 0, buf.Length);
            int stride = bd.Stride;
            bmp.UnlockBits(bd);

            bool[] colEmpty = new bool[w];
            for (int x = 0; x < w; x++) {
                bool empty = true;
                for (int y = 0; y < h; y++) {
                    int idx = y * stride + x * 4;
                    int b = buf[idx], g = buf[idx + 1], r = buf[idx + 2];
                    int minC = Math.Min(r, Math.Min(g, b));
                    int maxC = Math.Max(r, Math.Max(g, b));
                    if (minC < 228 || (maxC - minC) > 22) { empty = false; break; }
                }
                colEmpty[x] = empty;
            }

            var cuts = new int[expectedCols + 1];
            cuts[0] = 0;
            cuts[expectedCols] = w;
            for (int c = 1; c < expectedCols; c++) {
                int nominal = (int)(w * (c / (double)expectedCols));
                int lo = Math.Max(0, nominal - (int)(w * 0.14));
                int hi = Math.Min(w - 1, nominal + (int)(w * 0.14));
                int bestStart = -1, bestLen = 0, curStart = -1;
                for (int x = lo; x <= hi; x++) {
                    if (colEmpty[x]) {
                        if (curStart < 0) curStart = x;
                        int len = x - curStart + 1;
                        if (len > bestLen) { bestLen = len; bestStart = curStart; }
                    } else {
                        curStart = -1;
                    }
                }
                cuts[c] = bestLen > 0 ? (bestStart + bestLen / 2) : nominal;
            }
            return cuts;
        }
    }

    public static void KeyWhite(Bitmap bmp, bool softGlow, bool removeEnclosedWhitePockets) {
        int w = bmp.Width, h = bmp.Height;
        var bd = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
        int stride = bd.Stride;
        byte[] px = new byte[stride * h];
        Marshal.Copy(bd.Scan0, px, 0, px.Length);

        bool[] bg = new bool[w * h];
        var q = new Queue<int>();

        Func<int, int, bool> isOuterWhite = (x, y) => {
            int i = y * stride + x * 4;
            int b = px[i], g = px[i + 1], r = px[i + 2];
            int minC = Math.Min(r, Math.Min(g, b));
            int maxC = Math.Max(r, Math.Max(g, b));
            double luma = 0.299 * r + 0.587 * g + 0.114 * b;
            return luma >= 232 && (maxC - minC) <= 22 && minC >= 216;
        };

        for (int x = 0; x < w; x++) {
            if (isOuterWhite(x, 0)) { bg[x] = true; q.Enqueue(x); }
            int btm = (h - 1) * w + x;
            if (!bg[btm] && isOuterWhite(x, h - 1)) { bg[btm] = true; q.Enqueue(btm); }
        }
        for (int y = 0; y < h; y++) {
            int l = y * w;
            if (!bg[l] && isOuterWhite(0, y)) { bg[l] = true; q.Enqueue(l); }
            int rIdx = y * w + (w - 1);
            if (!bg[rIdx] && isOuterWhite(w - 1, y)) { bg[rIdx] = true; q.Enqueue(rIdx); }
        }

        int[] dx = { 1, -1, 0, 0 };
        int[] dy = { 0, 0, 1, -1 };
        while (q.Count > 0) {
            int cur = q.Dequeue();
            int cx = cur % w, cy = cur / w;
            for (int k = 0; k < 4; k++) {
                int nx = cx + dx[k], ny = cy + dy[k];
                if (nx >= 0 && nx < w && ny >= 0 && ny < h) {
                    int ni = ny * w + nx;
                    if (!bg[ni] && isOuterWhite(nx, ny)) {
                        bg[ni] = true;
                        q.Enqueue(ni);
                    }
                }
            }
        }

        // Remove enclosed pure flat white holes (e.g. inside bow loops, between arms/legs of squads)
        if (removeEnclosedWhitePockets) {
            bool[] seen = new bool[w * h];
            for (int y = 1; y < h - 1; y++) {
                for (int x = 1; x < w - 1; x++) {
                    int sIdx = y * w + x;
                    if (bg[sIdx] || seen[sIdx]) continue;
                    int si = y * stride + x * 4;
                    int sb = px[si], sg = px[si + 1], sr = px[si + 2];
                    int sMin = Math.Min(sr, Math.Min(sg, sb)), sMax = Math.Max(sr, Math.Max(sg, sb));
                    if (sMin < 245 || (sMax - sMin) > 10) continue;

                    var comp = new List<int>();
                    var pq = new Queue<int>();
                    seen[sIdx] = true;
                    pq.Enqueue(sIdx);
                    while (pq.Count > 0) {
                        int cur = pq.Dequeue();
                        comp.Add(cur);
                        int cx = cur % w, cy = cur / w;
                        for (int k = 0; k < 4; k++) {
                            int nx = cx + dx[k], ny = cy + dy[k];
                            if (nx >= 0 && nx < w && ny >= 0 && ny < h) {
                                int ni = ny * w + nx;
                                if (!bg[ni] && !seen[ni]) {
                                    int pi = ny * stride + nx * 4;
                                    int pb = px[pi], pg = px[pi + 1], pr = px[pi + 2];
                                    int pMin = Math.Min(pr, Math.Min(pg, pb)), pMax = Math.Max(pr, Math.Max(pg, pb));
                                    if (pMin >= 238 && (pMax - pMin) <= 15) {
                                        seen[ni] = true;
                                        pq.Enqueue(ni);
                                    }
                                }
                            }
                        }
                    }
                    if (comp.Count >= 18) {
                        foreach (int idx in comp) bg[idx] = true;
                    }
                }
            }
        }

        // Compute distance-to-bg <= 3 for anti-aliased fringe un-premultiply
        int[] dist = new int[w * h];
        for (int i = 0; i < w * h; i++) dist[i] = bg[i] ? 0 : 99;
        for (int pass = 1; pass <= (softGlow ? 10 : 3); pass++) {
            for (int y = 0; y < h; y++) {
                for (int x = 0; x < w; x++) {
                    int idx = y * w + x;
                    if (dist[idx] != 99) continue;
                    bool adj = (x > 0 && dist[idx - 1] == pass - 1) ||
                               (x < w - 1 && dist[idx + 1] == pass - 1) ||
                               (y > 0 && dist[idx - w] == pass - 1) ||
                               (y < h - 1 && dist[idx + w] == pass - 1);
                    if (adj) dist[idx] = pass;
                }
            }
        }

        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                int pIdx = y * w + x;
                int i = y * stride + x * 4;
                if (bg[pIdx]) {
                    px[i] = 0; px[i + 1] = 0; px[i + 2] = 0; px[i + 3] = 0;
                    continue;
                }
                int b = px[i], g = px[i + 1], r = px[i + 2];
                int minC = Math.Min(r, Math.Min(g, b));
                int maxC = Math.Max(r, Math.Max(g, b));
                double luma = 0.299 * r + 0.587 * g + 0.114 * b;
                int chroma = maxC - minC;
                if (dist[pIdx] <= (softGlow ? 8 : 2) && (luma > 135 || (softGlow && minC > 180))) {
                    // Recover foreground mixed with #FFFFFF background
                    double alphaNeutral = (242.0 - luma) / 115.0;
                    double alphaColor = softGlow ? (255.0 - minC) / 145.0 : alphaNeutral;
                    double a = Math.Max(0.0, Math.Min(1.0, Math.Max(alphaNeutral, chroma > 24 ? alphaColor : alphaNeutral)));
                    if (a < 0.04) {
                        px[i] = 0; px[i + 1] = 0; px[i + 2] = 0; px[i + 3] = 0;
                    } else if (a < 0.99) {
                        double ur = (r - 255.0 * (1.0 - a)) / a;
                        double ug = (g - 255.0 * (1.0 - a)) / a;
                        double ub = (b - 255.0 * (1.0 - a)) / a;
                        px[i] = (byte)Clamp255(ub);
                        px[i + 1] = (byte)Clamp255(ug);
                        px[i + 2] = (byte)Clamp255(ur);
                        px[i + 3] = (byte)Clamp255(a * 255.0);
                    }
                }
            }
        }

        Marshal.Copy(px, 0, bd.Scan0, px.Length);
        bmp.UnlockBits(bd);
    }

    public static void KeyBlack(Bitmap bmp) {
        int w = bmp.Width, h = bmp.Height;
        var bd = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
        int stride = bd.Stride;
        byte[] px = new byte[stride * h];
        Marshal.Copy(bd.Scan0, px, 0, px.Length);

        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                int i = y * stride + x * 4;
                int b = px[i], g = px[i + 1], r = px[i + 2];
                int maxC = Math.Max(r, Math.Max(g, b));
                if (maxC <= 12) {
                    px[i] = 0; px[i + 1] = 0; px[i + 2] = 0; px[i + 3] = 0;
                } else {
                    double a = Math.Min(1.0, (maxC - 12) / 155.0);
                    px[i] = (byte)Clamp255(b / a);
                    px[i + 1] = (byte)Clamp255(g / a);
                    px[i + 2] = (byte)Clamp255(r / a);
                    px[i + 3] = (byte)Clamp255(a * 255.0);
                }
            }
        }

        Marshal.Copy(px, 0, bd.Scan0, px.Length);
        bmp.UnlockBits(bd);
    }

    public static void SaveTight(Bitmap bmp, string outPath, int maxW, int maxH, bool forceSquare) {
        int w = bmp.Width, h = bmp.Height;
        var bd = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        int stride = bd.Stride;
        byte[] px = new byte[stride * h];
        Marshal.Copy(bd.Scan0, px, 0, px.Length);
        bmp.UnlockBits(bd);

        int minX = w, minY = h, maxX = -1, maxY = -1;
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                if (px[y * stride + x * 4 + 3] > 14) {
                    if (x < minX) minX = x;
                    if (x > maxX) maxX = x;
                    if (y < minY) minY = y;
                    if (y > maxY) maxY = y;
                }
            }
        }
        if (maxX < minX) { minX = 0; minY = 0; maxX = w - 1; maxY = h - 1; }
        int pad = 6;
        minX = Math.Max(0, minX - pad); minY = Math.Max(0, minY - pad);
        maxX = Math.Min(w - 1, maxX + pad); maxY = Math.Min(h - 1, maxY + pad);
        int cw = maxX - minX + 1, ch = maxY - minY + 1;

        int tw, th, dx = 0, dy = 0, dw, dh;
        if (forceSquare) {
            tw = maxW; th = maxH;
            double s = Math.Min((maxW - 4.0) / cw, (maxH - 4.0) / ch);
            dw = Math.Max(1, (int)Math.Round(cw * s));
            dh = Math.Max(1, (int)Math.Round(ch * s));
            dx = (tw - dw) / 2;
            dy = (th - dh) / 2;
        } else {
            double s = Math.Min((double)maxW / cw, (double)maxH / ch);
            tw = Math.Max(1, (int)Math.Round(cw * s));
            th = Math.Max(1, (int)Math.Round(ch * s));
            dw = tw; dh = th;
        }

        using (var dst = new Bitmap(tw, th, PixelFormat.Format32bppArgb))
        using (var g = Graphics.FromImage(dst)) {
            g.Clear(Color.Transparent);
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.SmoothingMode = SmoothingMode.HighQuality;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            using (var ia = new ImageAttributes()) {
                ia.SetWrapMode(WrapMode.TileFlipXY);
                g.DrawImage(bmp, new Rectangle(dx, dy, dw, dh), minX, minY, cw, ch, GraphicsUnit.Pixel, ia);
            }
            dst.Save(outPath, ImageFormat.Png);
        }
    }

    public static void SaveResizedOpaque(string srcPath, string outPath, int w, int h) {
        using (var src = new Bitmap(srcPath))
        using (var dst = new Bitmap(w, h, PixelFormat.Format32bppArgb))
        using (var g = Graphics.FromImage(dst)) {
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.SmoothingMode = SmoothingMode.HighQuality;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            using (var ia = new ImageAttributes()) {
                ia.SetWrapMode(WrapMode.TileFlipXY);
                g.DrawImage(src, new Rectangle(0, 0, w, h), 0, 0, src.Width, src.Height, GraphicsUnit.Pixel, ia);
            }
            dst.Save(outPath, ImageFormat.Png);
        }
    }
}
"@
Add-Type -TypeDefinition $code -ReferencedAssemblies System.Drawing

function Slice-GridWhite($path, $cols, $rows, $names, $maxW, $maxH, $square, $softGlow) {
    $idx = 0
    for ($r = 0; $r -lt $rows; $r++) {
        for ($c = 0; $c -lt $cols; $c++) {
            $name = $names[$idx++]
            if (-not $name) { continue }
            $bmp = [SpriteProcessor]::LoadCrop($path, $c / $cols, $r / $rows, ($c + 1) / $cols, ($r + 1) / $rows)
            [SpriteProcessor]::KeyWhite($bmp, $softGlow, $false)
            [SpriteProcessor]::SaveTight($bmp, "$ArtDir/$name.png", $maxW, $maxH, $square)
            $bmp.Dispose()
            Write-Host "Saved $name.png"
        }
    }
}

function Slice-RowAuto($path, $names, $maxW, $maxH, $square = $false, $removePockets = $true) {
    $cuts = [SpriteProcessor]::FindVerticalValleys($path, $names.Count)
    $bmpFull = New-Object System.Drawing.Bitmap($path)
    $w = $bmpFull.Width
    $bmpFull.Dispose()
    for ($i = 0; $i -lt $names.Count; $i++) {
        $rx0 = $cuts[$i] / [double]$w
        $rx1 = $cuts[$i + 1] / [double]$w
        $bmp = [SpriteProcessor]::LoadCrop($path, $rx0, 0.0, $rx1, 1.0)
        [SpriteProcessor]::KeyWhite($bmp, $true, $removePockets)
        [SpriteProcessor]::SaveTight($bmp, "$ArtDir/$($names[$i]).png", $maxW, $maxH, $square)
        $bmp.Dispose()
        Write-Host "Saved $($names[$i]).png (cuts $($cuts[$i])..$($cuts[$i+1]))"
    }
}

function Slice-GridBlack($path, $cols, $rows, $names, $maxW, $maxH, $square = $false) {
    $idx = 0
    $pad = 0.03
    for ($r = 0; $r -lt $rows; $r++) {
        for ($c = 0; $c -lt $cols; $c++) {
            $name = $names[$idx++]
            $bmp = [SpriteProcessor]::LoadCrop($path, $c / $cols + $pad, $r / $rows + $pad, ($c + 1) / $cols - $pad, ($r + 1) / $rows - $pad)
            [SpriteProcessor]::KeyBlack($bmp)
            [SpriteProcessor]::SaveTight($bmp, "$ArtDir/$name.png", $maxW, $maxH, $square)
            $bmp.Dispose()
            Write-Host "Saved $name.png"
        }
    }
}

$brain = "C:\Users\gellert.alexandr\.gemini\antigravity\brain\88367b99-92d2-4980-b442-d3f33b7ab303"
function Latest($pattern) {
    return (Get-ChildItem $brain -Filter $pattern | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}

$gems = Latest "match3_crystals_*.jpg"
if ($gems) { Slice-GridWhite $gems 3 2 @("gem_red","gem_yellow","gem_purple","gem_green","gem_blue","gem_prism") 104 104 $true $true }

$meds = Latest "fantasy_character_medallions_*.jpg"
if ($meds) { Slice-GridWhite $meds 3 2 @("face_hero","face_goblin","face_skeleton","face_orc","face_necromancer","face_dragon") 128 128 $true $false }

$chests = Latest "fantasy_chests_*.jpg"
if ($chests) { Slice-GridWhite $chests 3 1 @("chest_wood","chest_silver","chest_royal") 128 128 $true $false }

$amber = Latest "amber_squads_*.jpg"
if ($amber) { Slice-RowAuto $amber @("squad_yellow_archers","squad_yellow_crossbow","squad_yellow_paladin") 156 136 }

$amber2 = Latest "amber_gold_squads_*.jpg"
if ($amber2) { Slice-RowAuto $amber2 @("squad_yellow_falconer","squad_yellow_assassins","squad_yellow_thunder") 156 136 }

$arcane = Latest "arcane_squads_*.jpg"
if ($arcane) { Slice-RowAuto $arcane @("squad_purple_cultists","squad_purple_necro","squad_purple_golem") 156 136 }

$cultists = Latest "shadow_cultists_squad_*.jpg"
if ($cultists) {
    $bmp = [SpriteProcessor]::LoadCrop($cultists, 0.0, 0.0, 1.0, 1.0)
    [SpriteProcessor]::KeyWhite($bmp, $true, $true)
    [SpriteProcessor]::SaveTight($bmp, "$ArtDir/squad_purple_cultists.png", 156, 136, $false)
    $bmp.Dispose()
    Write-Host "Saved squad_purple_cultists.png (dedicated 2x2 squad)"
}

$arcane2 = Latest "arcane_purple_squads_*.jpg"
if ($arcane2) { Slice-RowAuto $arcane2 @("squad_purple_imps","squad_purple_banshee","squad_purple_reaper") 156 136 }

$crimson = Latest "crimson_squads_spritesheet_final_*.jpg"
if ($crimson) { Slice-RowAuto $crimson @("squad_red_militia","squad_red_wolves","squad_red_berserk") 156 136 }

$crimson2 = Latest "crimson_squads_spritesheet_1794401163654.jpg"
if (-not $crimson2) { $crimson2 = (Get-ChildItem $brain -Filter "crimson_squads_spritesheet_*.jpg" | Where-Object { $_.Name -notlike "*final*" -and $_.Name -notlike "*exact*" } | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName }
if ($crimson2) { Slice-RowAuto $crimson2 @("squad_red_spearmen","squad_red_pyromancer","squad_red_drake") 156 136 }

$vfx = Latest "combat_vfx_*.jpg"
if ($vfx) { Slice-GridBlack $vfx 2 2 @("proj_arrow","proj_bolt","proj_spell","fx_slash") 112 112 }

$vfx2 = Latest "elemental_spells_vfx_*.jpg"
if ($vfx2) { Slice-GridBlack $vfx2 2 2 @("proj_fire","proj_lightning","proj_venom","fx_reap") 112 112 }

$arena = Latest "arena_backdrop_*.jpg"
if ($arena) {
    [SpriteProcessor]::SaveResizedOpaque($arena, "$ArtDir/arena_bg.png", 512, 256)
    Write-Host "Saved arena_bg.png"
}

$arenaLava = Latest "volcanic_arena_backdrop_*.jpg"
if ($arenaLava) {
    [SpriteProcessor]::SaveResizedOpaque($arenaLava, "$ArtDir/arena_bg_lava.png", 512, 256)
    Write-Host "Saved arena_bg_lava.png"
}

$arenaVoid = Latest "astral_void_crypt_arena_*.jpg"
if ($arenaVoid) {
    [SpriteProcessor]::SaveResizedOpaque($arenaVoid, "$ArtDir/arena_bg_void.png", 512, 256)
    Write-Host "Saved arena_bg_void.png"
}

$sq3 = Latest "fantasy_squads_spritesheet_*.jpg"
if ($sq3) {
    $sq3Cfg = @(
        @("squad_red_templar",     0.000, 0.348),
        @("squad_yellow_valkyrie", 0.348, 0.678),
        @("squad_purple_witch",    0.678, 1.000)
    )
    foreach ($s in $sq3Cfg) {
        $bmp = [SpriteProcessor]::LoadCrop($sq3, $s[1], 0.0, $s[2], 1.0)
        [SpriteProcessor]::KeyWhite($bmp, $true, $true)
        [SpriteProcessor]::SaveTight($bmp, "$ArtDir/$($s[0]).png", 156, 136, $false)
        $bmp.Dispose()
        Write-Host "Saved $($s[0]).png"
    }
}

$boosts = Latest "booster_icons_spritesheet_*.jpg"
if ($boosts) { Slice-RowAuto $boosts @("boost_shuffle","boost_hammer","boost_moves") 96 96 $true $false }

$vfx3 = Latest "match3_vfx_overlays_2x2_*.jpg"
if ($vfx3) { Slice-GridBlack $vfx3 2 2 @("spec_line_h","spec_line_v","spec_bomb","obs_ice") 128 128 $true }

$obs = Latest "dark_fantasy_match3_tiles_obstacles_*.jpg"
if ($obs) {
    $obsCfg = @(
        @("obs_hole",      0.0, 0.0, 0.5, 0.5, $false, $false),
        @("obs_stone",     0.5, 0.0, 1.0, 0.5, $false, $false),
        @("obs_empowered", 0.0, 0.5, 0.5, 1.0, $true,  $true),
        @("obs_curse",     0.5, 0.5, 1.0, 1.0, $true,  $false)
    )
    foreach ($o in $obsCfg) {
        $bmp = [SpriteProcessor]::LoadCrop($obs, $o[1], $o[2], $o[3], $o[4])
        [SpriteProcessor]::KeyWhite($bmp, $o[5], $o[6])
        [SpriteProcessor]::SaveTight($bmp, "$ArtDir/$($o[0]).png", 128, 128, $true)
        $bmp.Dispose()
        Write-Host "Saved $($o[0]).png"
    }
}

# Build dark-slate preview contact sheet of all extracted art
$previewPath = "$brain\scratch\nb_preview.png"
New-Item -ItemType Directory -Force -Path "$brain\scratch" | Out-Null
$pngs = Get-ChildItem $ArtDir -Filter "*.png" | Sort-Object Name
$cols = 6
$cell = 190
$rows = [Math]::Ceiling($pngs.Count / $cols)
$pw = $cols * $cell
$ph = $rows * $cell
$sheet = New-Object System.Drawing.Bitmap($pw, $ph, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($sheet)
$g.Clear([System.Drawing.Color]::FromArgb(255, 17, 21, 33))
$font = New-Object System.Drawing.Font("Consolas", 11)
$brush = [System.Drawing.Brushes]::LightGray
for ($i = 0; $i -lt $pngs.Count; $i++) {
    $c = $i % $cols
    $r = [Math]::Floor($i / $cols)
    $x = $c * $cell + 10
    $y = $r * $cell + 10
    $img = [System.Drawing.Image]::FromFile($pngs[$i].FullName)
    $s = [Math]::Min(164.0 / $img.Width, 145.0 / $img.Height)
    $dw = [int]($img.Width * $s)
    $dh = [int]($img.Height * $s)
    $g.DrawImage($img, $x + (170 - $dw) / 2, $y + (150 - $dh) / 2, $dw, $dh)
    $g.DrawString([System.IO.Path]::GetFileNameWithoutExtension($pngs[$i].Name), $font, $brush, $x, $y + 154)
    $img.Dispose()
}
$g.Dispose()
$sheet.Save($previewPath, [System.Drawing.Imaging.ImageFormat]::Png)
$sheet.Dispose()
Write-Host "Contact sheet written to $previewPath"
