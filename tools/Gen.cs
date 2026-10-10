// Image generator for LushfoilCraft (C# 5, compiled with the framework's csc.exe by tools/gen.ps1; needs no packages).
//   Gen.exe logo    <Source dir>   -> textures/lc_logo.png  (the title logo: lit, textured cubes with depth, shadows and bloom)
//   Gen.exe credits <Source dir>   -> textures/lc_credits.png (split credits screen: Lushfoil / Annapurna | Minecraft / Mojang)
//   Gen.exe title   <Source dir>   -> textures/lc_title.png   (the LushfoilCraft screen's backdrop)
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.IO;

static class Gen
{
    static string root;
    static Dictionary<char, string[]> G = new Dictionary<char, string[]>();
    static void Glyphs()
    {
        string[] src = {
            "A 01110 10001 10001 11111 10001 10001 10001", "B 11110 10001 10001 11110 10001 10001 11110",
            "C 01110 10001 10000 10000 10000 10001 01110", "D 11110 10001 10001 10001 10001 10001 11110",
            "E 11111 10000 10000 11110 10000 10000 11111", "F 11111 10000 10000 11110 10000 10000 10000",
            "G 01110 10001 10000 10111 10001 10001 01111", "H 10001 10001 10001 11111 10001 10001 10001",
            "I 11111 00100 00100 00100 00100 00100 11111", "J 00111 00010 00010 00010 10010 10010 01100",
            "K 10001 10010 10100 11000 10100 10010 10001", "L 10000 10000 10000 10000 10000 10000 11111",
            "M 10001 11011 10101 10101 10001 10001 10001", "N 10001 11001 10101 10011 10001 10001 10001",
            "O 01110 10001 10001 10001 10001 10001 01110", "P 11110 10001 10001 11110 10000 10000 10000",
            "Q 01110 10001 10001 10001 10101 10010 01101", "R 11110 10001 10001 11110 10100 10010 10001",
            "S 01111 10000 10000 01110 00001 00001 11110", "T 11111 00100 00100 00100 00100 00100 00100",
            "U 10001 10001 10001 10001 10001 10001 01110", "V 10001 10001 10001 10001 10001 01010 00100",
            "W 10001 10001 10001 10101 10101 11011 10001", "X 10001 10001 01010 00100 01010 10001 10001",
            "Y 10001 10001 01010 00100 00100 00100 00100", "Z 11111 00001 00010 00100 01000 10000 11111",
            "0 01110 10001 10011 10101 11001 10001 01110", "1 00100 01100 00100 00100 00100 00100 01110",
            "2 01110 10001 00001 00010 00100 01000 11111", "3 11110 00001 00001 01110 00001 00001 11110",
            "4 00010 00110 01010 10010 11111 00010 00010", "5 11111 10000 11110 00001 00001 10001 01110",
            "6 00110 01000 10000 11110 10001 10001 01110", "7 11111 00001 00010 00100 01000 01000 01000",
            "8 01110 10001 10001 01110 10001 10001 01110", "9 01110 10001 10001 01111 00001 00010 01100",
            ". 00000 00000 00000 00000 00000 01100 01100", ", 00000 00000 00000 00000 01100 00100 01000",
            "- 00000 00000 00000 11111 00000 00000 00000", "' 00100 00100 01000 00000 00000 00000 00000",
            "\" 01010 01010 00000 00000 00000 00000 00000", ": 00000 01100 01100 00000 01100 01100 00000",
            "! 00100 00100 00100 00100 00100 00000 00100", "/ 00001 00010 00010 00100 01000 01000 10000",
            "( 00010 00100 01000 01000 01000 00100 00010", ") 01000 00100 00010 00010 00010 00100 01000",
            "& 01100 10010 10100 01000 10101 10010 01101", "? 01110 10001 00001 00110 00100 00000 00100",
        };
        foreach (string s in src) { string[] p = s.Split(' '); string[] rows = new string[7]; Array.Copy(p, 1, rows, 0, 7); G[p[0][0]] = rows; }
        G[' '] = new string[] { "00000", "00000", "00000", "00000", "00000", "00000", "00000" };
    }

    // ---- bitmaps as flat float arrays
    class Img
    {
        public int W, H; public float[] r, g, b, a;
        public Img(int w, int h) { W = w; H = h; r = new float[w * h]; g = new float[w * h]; b = new float[w * h]; a = new float[w * h]; }
        public void Fill(float R, float G_, float B, float A) { for (int i = 0; i < W * H; i++) { r[i] = R; g[i] = G_; b[i] = B; a[i] = A; } }
        // straight-alpha "over" of one colour
        public void Over(int x, int y, float R, float G_, float B, float A)
        {
            if (x < 0 || y < 0 || x >= W || y >= H || A <= 0) return;
            int i = y * W + x; float oa = a[i]; float na = A + oa * (1 - A);
            if (na <= 0) return;
            r[i] = (R * A + r[i] * oa * (1 - A)) / na; g[i] = (G_ * A + g[i] * oa * (1 - A)) / na; b[i] = (B * A + b[i] * oa * (1 - A)) / na; a[i] = na;
        }
        public Bitmap ToBitmap()
        {
            Bitmap bm = new Bitmap(W, H, PixelFormat.Format32bppArgb);
            BitmapData d = bm.LockBits(new Rectangle(0, 0, W, H), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
            byte[] buf = new byte[W * H * 4];
            for (int i = 0; i < W * H; i++)
            {
                buf[i * 4 + 0] = C(b[i]); buf[i * 4 + 1] = C(g[i]); buf[i * 4 + 2] = C(r[i]); buf[i * 4 + 3] = C(a[i]);
            }
            System.Runtime.InteropServices.Marshal.Copy(buf, 0, d.Scan0, buf.Length);
            bm.UnlockBits(d);
            return bm;
        }
        public static Img FromBitmap(Bitmap bm)
        {
            Img im = new Img(bm.Width, bm.Height);
            BitmapData d = bm.LockBits(new Rectangle(0, 0, bm.Width, bm.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            byte[] buf = new byte[bm.Width * bm.Height * 4];
            System.Runtime.InteropServices.Marshal.Copy(d.Scan0, buf, 0, buf.Length);
            bm.UnlockBits(d);
            for (int i = 0; i < im.W * im.H; i++) { im.b[i] = buf[i * 4] / 255f; im.g[i] = buf[i * 4 + 1] / 255f; im.r[i] = buf[i * 4 + 2] / 255f; im.a[i] = buf[i * 4 + 3] / 255f; }
            return im;
        }
        static byte C(float v) { if (v < 0) v = 0; if (v > 1) v = 1; return (byte)(v * 255f + 0.5f); }
    }

    static Dictionary<string, Img> texCache = new Dictionary<string, Img>();
    static Img Tex(string name)
    {
        Img t;
        if (texCache.TryGetValue(name, out t)) return t;
        string p = Path.Combine(root, "textures", name + ".png");
        if (!File.Exists(p)) { texCache[name] = null; return null; }
        using (Bitmap bm = new Bitmap(p)) t = Img.FromBitmap(bm);
        texCache[name] = t; return t;
    }
    static void Sample(Img t, double u, double v, out float r, out float g, out float b)
    {
        u = u - Math.Floor(u); v = v - Math.Floor(v);
        double x = u * t.W - 0.5, y = v * t.H - 0.5;
        int x0 = (int)Math.Floor(x), y0 = (int)Math.Floor(y); double fx = x - x0, fy = y - y0;
        r = g = b = 0;
        for (int j = 0; j < 2; j++) for (int i = 0; i < 2; i++)
            {
                int xx = ((x0 + i) % t.W + t.W) % t.W, yy = ((y0 + j) % t.H + t.H) % t.H; double w = (i == 0 ? 1 - fx : fx) * (j == 0 ? 1 - fy : fy); int k = yy * t.W + xx;
                r += (float)(t.r[k] * w); g += (float)(t.g[k] * w); b += (float)(t.b[k] * w);
            }
    }

    // ---- noise
    static uint Hash(int x, int y, int s) { uint h = (uint)(x * 374761393 + y * 668265263 + s * 2147483647); h = (h ^ (h >> 13)) * 1274126177u; return h ^ (h >> 16); }
    static double H01(int x, int y, int s) { return (Hash(x, y, s) & 0xFFFFFF) / (double)0x1000000; }
    static double VNoise(double x, double y, int s)
    {
        int xi = (int)Math.Floor(x), yi = (int)Math.Floor(y); double fx = x - xi, fy = y - yi;
        fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy);
        double a = H01(xi, yi, s), b = H01(xi + 1, yi, s), c = H01(xi, yi + 1, s), d = H01(xi + 1, yi + 1, s);
        return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy;
    }
    static double Fbm(double x, double y, int s) { return VNoise(x, y, s) * 0.5 + VNoise(x * 2.1, y * 2.1, s + 1) * 0.3 + VNoise(x * 4.3, y * 4.3, s + 2) * 0.2; }
    static double Smooth(double a, double b, double x) { double t = Math.Max(0, Math.Min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t); }

    static void Blur(float[] a, int w, int h, int rad, int passes)
    {
        float[] tmp = new float[a.Length];
        for (int p = 0; p < passes; p++)
        {
            for (int y = 0; y < h; y++)
            {
                double sum = 0; int n = 2 * rad + 1;
                for (int x = -rad; x <= rad; x++) sum += a[y * w + Math.Max(0, Math.Min(w - 1, x))];
                for (int x = 0; x < w; x++)
                {
                    tmp[y * w + x] = (float)(sum / n);
                    sum += a[y * w + Math.Min(w - 1, x + rad + 1)] - a[y * w + Math.Max(0, x - rad)];
                }
            }
            for (int x = 0; x < w; x++)
            {
                double sum = 0; int n = 2 * rad + 1;
                for (int y = -rad; y <= rad; y++) sum += tmp[Math.Max(0, Math.Min(h - 1, y)) * w + x];
                for (int y = 0; y < h; y++)
                {
                    a[y * w + x] = (float)(sum / n);
                    sum += tmp[Math.Min(h - 1, y + rad + 1) * w + x] - tmp[Math.Max(0, y - rad) * w + x];
                }
            }
        }
    }

    static Img Downsample(Img s, int f)
    {
        Img o = new Img(s.W / f, s.H / f);
        for (int y = 0; y < o.H; y++) for (int x = 0; x < o.W; x++)
            {
                double ar = 0, ag = 0, ab = 0, aa = 0;
                for (int j = 0; j < f; j++) for (int i = 0; i < f; i++)
                    {
                        int k = (y * f + j) * s.W + x * f + i; double al = s.a[k]; ar += s.r[k] * al; ag += s.g[k] * al; ab += s.b[k] * al; aa += al;
                    }
                int q = y * o.W + x;
                if (aa > 0) { o.r[q] = (float)(ar / aa); o.g[q] = (float)(ag / aa); o.b[q] = (float)(ab / aa); }
                o.a[q] = (float)(aa / (f * f));
            }
        return o;
    }

    // ---------------------------------------------------------------- the logo
    class Cell { public int c, r; public string word; }

    // a lit, textured face of a cube in oblique projection
    delegate void Shader(double u, double v, out float R, out float G_, out float B);

    static void Face(Img im, double ox, double oy, double ux, double uy, double vx, double vy, Shader sh)
    {
        double det = ux * vy - uy * vx;
        double minx = Math.Min(Math.Min(ox, ox + ux), Math.Min(ox + vx, ox + ux + vx)), maxx = Math.Max(Math.Max(ox, ox + ux), Math.Max(ox + vx, ox + ux + vx));
        double miny = Math.Min(Math.Min(oy, oy + uy), Math.Min(oy + vy, oy + uy + vy)), maxy = Math.Max(Math.Max(oy, oy + uy), Math.Max(oy + vy, oy + uy + vy));
        for (int y = (int)Math.Floor(miny); y <= (int)Math.Ceiling(maxy); y++)
            for (int x = (int)Math.Floor(minx); x <= (int)Math.Ceiling(maxx); x++)
            {
                if (x < 0 || y < 0 || x >= im.W || y >= im.H) continue;
                double px = x + 0.5 - ox, py = y + 0.5 - oy;
                double u = (px * vy - py * vx) / det, v = (ux * py - uy * px) / det;
                if (u < 0 || u >= 1 || v < 0 || v >= 1) continue;
                float R, G_, B; sh(u, v, out R, out G_, out B);
                int i = y * im.W + x; im.r[i] = R; im.g[i] = G_; im.b[i] = B; im.a[i] = 1f;
            }
    }

    static void Blade(Img im, double bx, double by, double len, double lean, double w0, float r0, float g0, float b0, float r1, float g1, float b1)
    {
        int steps = (int)(len * 2);
        for (int i = 0; i <= steps; i++)
        {
            double t = i / (double)steps; double x = bx + lean * t * t * len, y = by - len * t; double w = Math.Max(0.6, w0 * (1 - t * 0.85));
            float cr = (float)(r0 + (r1 - r0) * t), cg = (float)(g0 + (g1 - g0) * t), cb = (float)(b0 + (b1 - b0) * t);
            for (double ox = -w / 2; ox <= w / 2; ox += 0.5) im.Over((int)Math.Round(x + ox), (int)Math.Round(y), cr, cg, cb, 1f);
        }
    }

    static void Crack(Img im, double x, double y, double len, int seed, double ang)
    {
        double a = ang;
        for (int i = 0; i < (int)len; i++)
        {
            a += (H01(seed, i, 5) - 0.5) * 0.9;
            x += Math.Cos(a) * 1.0; y += Math.Sin(a) * 1.0;
            im.Over((int)x, (int)y, 0.02f, 0.02f, 0.02f, 0.55f); im.Over((int)x + 1, (int)y, 0.02f, 0.02f, 0.02f, 0.25f);
            im.Over((int)x, (int)y - 1, 1f, 1f, 1f, 0.07f);
            if (i == (int)len / 2 && H01(seed, 99, 3) > 0.4) Crack(im, x, y, len * 0.5, seed + 31, a + (H01(seed, 7, 1) > 0.5 ? 0.8 : -0.8));
        }
    }

    static void LogoWord(Img im, string word, double x0, double y0, double s, string topTex, string sideTex, string frontTex, string mossTex, int seed, bool grass)
    {
        HashSet<long> cells = new HashSet<long>();
        List<int[]> list = new List<int[]>();
        int col = 0;
        foreach (char ch in word)
        {
            string[] rows; if (!G.TryGetValue(ch, out rows)) rows = G[' '];
            for (int gy = 0; gy < 7; gy++) for (int gx = 0; gx < 5; gx++) if (rows[gy][gx] == '1') { cells.Add(((long)(col + gx) << 8) | (uint)gy); list.Add(new int[] { col + gx, gy }); }
            col += 6;
        }
        double dd = s * 0.62;                       // depth vector (up and to the right)
        double dx = dd * 0.78, dy = -dd * 0.62;
        Img top = Tex(topTex), side = Tex(sideTex), front = Tex(frontTex), moss = mossTex != null ? Tex(mossTex) : null;
        double totalW = col * s, totalH = 7 * s;
        Func<int, int, bool> has = delegate(int c, int r) { return cells.Contains(((long)c << 8) | (uint)r); };
        // side faces first (right then top), then all the front faces
        foreach (int[] cr in list)
        {
            int c = cr[0], r = cr[1]; int cs = seed + c * 7 + r * 13;
            double cx = x0 + c * s, cy = y0 + r * s;
            if (!has(c + 1, r))
                Face(im, cx + s, cy, dx, dy, 0, s, delegate(double u, double v, out float R, out float G_, out float B)
                { Shade(side, u * 0.5 + 0.0, v, 0.46, u, v, cs + 3, 2, x0 + (c + 1) * s + dx * u, cy + v * s + dy * u, totalW, totalH, moss, out R, out G_, out B); });
            if (!has(c, r - 1))
                Face(im, cx, cy, s, 0, dx, dy, delegate(double u, double v, out float R, out float G_, out float B)
                { Shade(top, u, v, 1.0, u, v, cs + 5, 1, cx + u * s + dx * v, cy + dy * v, totalW, totalH, moss, out R, out G_, out B); });
        }
        foreach (int[] cr in list)
        {
            int c = cr[0], r = cr[1]; int cs = seed + c * 7 + r * 13;
            double cx = x0 + c * s, cy = y0 + r * s;
            Img ft = has(c, r - 1) ? front : (side ?? front);
            Face(im, cx, cy, s, 0, 0, s, delegate(double u, double v, out float R, out float G_, out float B)
            { Shade(ft, u, v, 0.82, u, v, cs + 1, 0, cx + u * s, cy + v * s, totalW, totalH, moss, out R, out G_, out B); });
            if (!grass && H01(c, r, seed) > 0.62) Crack(im, cx + s * (0.2 + 0.6 * H01(c, r, seed + 1)), cy + s * (0.15 + 0.2 * H01(c, r, seed + 2)), s * 0.55, cs, 1.2 + H01(c, r, 8));
        }
        if (grass)
        {
            // blades of grass rising off every exposed top, back to front
            foreach (int[] cr in list)
            {
                int c = cr[0], r = cr[1]; if (has(c, r - 1)) continue;
                double cx = x0 + c * s, cy = y0 + r * s;
                int n = (int)(s * 1.6);
                for (int k = 0; k < n; k++)
                {
                    double u = H01(c * 97 + k, r, seed + 11), v = H01(c, r * 89 + k, seed + 12);
                    double bx = cx + u * s + dx * v, by = cy + dy * v + 1;
                    double len = s * (0.10 + 0.34 * H01(k, c + r, seed + 13) * (0.5 + 0.5 * v)), lean = (H01(k, r, seed + 14) - 0.5) * 0.9;
                    double lum = 0.55 + 0.45 * v;
                    Blade(im, bx, by, len, lean, 2.4 * (s / 72.0), (float)(0.07 * lum), (float)(0.22 * lum), (float)(0.04 * lum), (float)(0.36 + 0.22 * H01(k, c, seed + 15)), (float)(0.62 + 0.2 * H01(k, r, seed + 16)), 0.14f);
                }
            }
        }
    }

    // colour, lighting, bevel, seams and weathering of one face pixel
    static void Shade(Img tex, double tu, double tv, double lit, double u, double v, int cellSeed, int kind, double wx, double wy, double totalW, double totalH, Img moss, out float R, out float G_, out float B)
    {
        double rot = Hash(cellSeed, 1, 9) % 4;
        double su = tu, sv = tv;
        if (rot == 1) { su = 1 - tv; sv = tu; } else if (rot == 2) { su = 1 - tu; sv = 1 - tv; } else if (rot == 3) { su = tv; sv = 1 - tu; }
        if (kind == 0 && tex != null && rot != 0 && false) { su = tu; sv = tv; }
        float r = 0.5f, g = 0.5f, b = 0.5f;
        if (tex != null) Sample(tex, su, sv, out r, out g, out b);
        // large soft weathering and fine grain
        double wn = Fbm(wx * 0.012, wy * 0.012, 41), grain = H01((int)(wx * 1.3), (int)(wy * 1.3), 77);
        double k = 0.82 + 0.34 * wn + 0.06 * (grain - 0.5);
        if (moss != null)
        {
            double m = Smooth(0.52, 0.66, Fbm(wx * 0.02 + 5, wy * 0.02 - 3, 5) + (1 - v) * 0.08 * (kind == 1 ? 1 : 0.4));
            float mr, mg, mb; Sample(moss, tu * 2 + cellSeed * 0.31, tv * 2 + cellSeed * 0.17, out mr, out mg, out mb);
            r = (float)(r * (1 - m) + mr * m); g = (float)(g * (1 - m) + mg * m); b = (float)(b * (1 - m) + mb * m);
        }
        // bevel: normals tilt at the edges of each cube
        double e = Math.Min(Math.Min(u, 1 - u), Math.Min(v, 1 - v));
        double bev = 0.085, seam = 0.018;
        double edge = 1.0;
        if (e < bev)
        {
            double t = 1 - e / bev; t = t * t;
            double nx = 0, ny = 0;
            if (u == e) nx = -1; else if (1 - u == e) nx = 1; else if (v == e) ny = -1; else ny = 1;
            double facing = (kind == 1) ? (ny < 0 ? 0.0 : (ny > 0 ? 0.0 : 0)) : 0;
            double l = -nx * 0.55 - ny * 0.75;           // light comes from the upper left
            edge = 1.0 + l * 0.55 * t;
        }
        double ao = 0.62 + 0.38 * Smooth(0.0, seam * 2.2, e);
        double shade = lit * edge * ao;
        // sky light falls off down the lettering, with a warm key light and a cool fill
        double grad = 1.12 - 0.26 * (wy / Math.Max(1.0, totalH + 200));
        double warm = Smooth(0.1, 1.0, shade) * 0.07;
        double rr = r * k * shade * grad * (1 + warm), gg = g * k * shade * grad * (1 + warm * 0.4), bb = b * k * shade * grad * (1 - warm * 0.6 + (1 - Math.Min(1, lit)) * 0.1);
        // specular glint on the lit bevels
        if (e < bev * 0.9 && edge > 1.05) { double sp = (edge - 1.05) * 0.9; rr += sp * 0.45; gg += sp * 0.45; bb += sp * 0.42; }
        R = (float)Math.Min(1.2, rr); G_ = (float)Math.Min(1.2, gg); B = (float)Math.Min(1.2, bb);
    }

    static void MakeLogo()
    {
        const int SS = 2;
        int W = 1920, H = 992;
        Img im = new Img(W * SS, H * SS);
        double s = 36 * SS;
        // LUSHFOIL: 8 letters = 47 columns; CRAFT: 5 letters = 29 columns
        double w1 = 47 * s, w2 = 29 * s;
        double y1 = 118 * SS, y2 = y1 + 7 * s + 34 * SS;
        double x1 = (W * SS - w1) / 2 - s * 0.4, x2 = (W * SS - w2) / 2 - s * 0.4;
        LogoWord(im, "LUSHFOIL", x1, y1, s, "grass_block_top", "grass_block_side", "dirt_all", "moss_block_all", 11, true);
        LogoWord(im, "CRAFT", x2, y2, s, "stone_bricks_all", "stone_all", "stone_all", "mossy_stone_bricks_all", 29, false);
        // silhouette -> soft contact shadow and a light bloom
        int n = im.W * im.H;
        float[] sil = new float[n]; for (int i = 0; i < n; i++) sil[i] = im.a[i];
        float[] shadow = new float[n];
        int offx = (int)(s * 0.22), offy = (int)(s * 0.42);
        for (int y = 0; y < im.H; y++) for (int x = 0; x < im.W; x++) { int sx = x - offx, sy = y - offy; if (sx >= 0 && sy >= 0 && sx < im.W && sy < im.H) shadow[y * im.W + x] = sil[sy * im.W + sx]; }
        Blur(shadow, im.W, im.H, (int)(s * 0.18), 3);
        float[] glow = new float[n];
        for (int i = 0; i < n; i++) { float l = (im.r[i] + im.g[i] + im.b[i]) / 3f; glow[i] = im.a[i] > 0 && l > 0.62f ? (l - 0.62f) * im.a[i] : 0; }
        Blur(glow, im.W, im.H, (int)(s * 0.35), 3);
        float[] halo = new float[n]; for (int i = 0; i < n; i++) halo[i] = sil[i];
        Blur(halo, im.W, im.H, (int)(s * 0.9), 2);
        Img outp = new Img(im.W, im.H);
        for (int i = 0; i < n; i++)
        {
            // ground shadow behind, soft warm halo behind that
            float sa = Math.Min(0.78f, shadow[i] * 0.95f);
            outp.r[i] = 0.02f; outp.g[i] = 0.03f; outp.b[i] = 0.025f; outp.a[i] = sa;
            float la = im.a[i];
            if (la > 0)
            {
                float oa = la + sa * (1 - la);
                outp.r[i] = (im.r[i] * la + outp.r[i] * sa * (1 - la)) / oa; outp.g[i] = (im.g[i] * la + outp.g[i] * sa * (1 - la)) / oa; outp.b[i] = (im.b[i] * la + outp.b[i] * sa * (1 - la)) / oa; outp.a[i] = oa;
            }
            // bloom on top
            float gl = glow[i] * 1.6f;
            if (gl > 0) { outp.r[i] += gl * 0.9f; outp.g[i] += gl * 0.95f; outp.b[i] += gl * 0.8f; outp.a[i] = Math.Max(outp.a[i], Math.Min(1f, gl * 1.3f)); }
        }
        Img fin = Downsample(outp, SS);
        // credit lines under the logo (big: the game shows this image at a quarter of its size on the loading scene)
        using (Bitmap bm = fin.ToBitmap())
        using (Graphics gr = Graphics.FromImage(bm))
        {
            gr.TextRenderingHint = TextRenderingHint.AntiAliasGridFit; gr.SmoothingMode = SmoothingMode.HighQuality;
            float yb = (float)(y2 / SS + 7 * s / SS + 52);
            Color white = Color.FromArgb(250, 248, 248, 242), shade = Color.FromArgb(190, 0, 0, 0);
            using (Font big = new Font("Segoe UI Semibold", 84f, FontStyle.Regular, GraphicsUnit.Pixel))
            using (Font mid = new Font("Segoe UI Semibold", 50f, FontStyle.Regular, GraphicsUnit.Pixel))
            using (Font small = new Font("Segoe UI", 46f, FontStyle.Regular, GraphicsUnit.Pixel))
            {
                string name = "created by Shivin Singh";
                string with = "(& Claude Sonnet 5.5";
                SizeF sb = gr.MeasureString(name, big, 100000, StringFormat.GenericTypographic), sw = gr.MeasureString(with + " ", mid, 100000, StringFormat.GenericTypographic);
                float markR = 28f, gap = 14f, total = sb.Width + 22f + sw.Width + markR * 2 + gap + 22f;
                float x0 = (W - total) / 2f;
                gr.DrawString(name, big, new SolidBrush(shade), x0 + 3, yb + 3, StringFormat.GenericTypographic);
                gr.DrawString(name, big, new SolidBrush(white), x0, yb, StringFormat.GenericTypographic);
                float xn1 = x0 + sb.Width + 22f, yb2 = yb + 30f;
                gr.DrawString(with, mid, new SolidBrush(shade), xn1 + 2, yb2 + 2, StringFormat.GenericTypographic);
                gr.DrawString(with, mid, new SolidBrush(white), xn1, yb2, StringFormat.GenericTypographic);
                float mx = xn1 + sw.Width + gap + markR - 6f, my = yb2 + 34f;
                Claude(gr, mx, my, markR);
                gr.DrawString(")", mid, new SolidBrush(shade), mx + markR + 8 + 2, yb2 + 2, StringFormat.GenericTypographic);
                gr.DrawString(")", mid, new SolidBrush(white), mx + markR + 8, yb2, StringFormat.GenericTypographic);
                string built = "built from Lushfoil Photography Sim and Minecraft Java 1.21.1";
                SizeF sbt = gr.MeasureString(built, small, 100000, StringFormat.GenericTypographic);
                float bx = (W - sbt.Width) / 2f, by = yb + 108f;
                gr.DrawString(built, small, new SolidBrush(shade), bx + 2, by + 2, StringFormat.GenericTypographic);
                gr.DrawString(built, small, new SolidBrush(Color.FromArgb(235, 226, 232, 226)), bx, by, StringFormat.GenericTypographic);
            }
            bm.Save(Path.Combine(root, "textures", "lc_logo.png"), ImageFormat.Png);
        }
        Console.WriteLine("logo written");
    }

    static void Claude(Graphics g, float cx, float cy, float r)
    {
        float[] len = { 1.0f, 0.72f, 0.94f, 0.66f, 1.0f, 0.78f, 0.92f, 0.7f, 1.0f, 0.74f, 0.9f, 0.68f };
        using (Pen pen = new Pen(Color.FromArgb(255, 217, 119, 87), r * 0.30f))
        {
            pen.StartCap = LineCap.Round; pen.EndCap = LineCap.Round;
            for (int i = 0; i < 12; i++)
            {
                double a = (i * 30 + 8) * Math.PI / 180.0;
                g.DrawLine(pen, cx + (float)Math.Cos(a) * r * 0.16f, cy + (float)Math.Sin(a) * r * 0.16f, cx + (float)Math.Cos(a) * r * len[i], cy + (float)Math.Sin(a) * r * len[i]);
            }
        }
    }

    // ---------------------------------------------------------------- shared text helpers
    static void Text(Graphics g, string t, string font, float px, FontStyle st, Color c, float cx, float y, float spacing)
    {
        using (Font f = new Font(font, px, st, GraphicsUnit.Pixel))
        {
            if (spacing > 0) { StringBuilder_(ref t, spacing); }
            SizeF sz = g.MeasureString(t, f, 100000, StringFormat.GenericTypographic);
            using (Brush b = new SolidBrush(c)) g.DrawString(t, f, b, cx - sz.Width / 2f, y, StringFormat.GenericTypographic);
        }
    }
    static void StringBuilder_(ref string t, float spacing)
    {
        System.Text.StringBuilder sb = new System.Text.StringBuilder();
        string gap = spacing >= 2 ? "  " : "  ";
        for (int i = 0; i < t.Length; i++) { sb.Append(t[i]); if (i < t.Length - 1 && t[i] != ' ') sb.Append(gap); }
        t = sb.ToString();
    }

    // chunky pixel text (Minecraft style), drawn into an Img with a drop shadow; scale = pixel size on screen
    static void PixelText(Img im, string text, double cx, double y, int scale, float R, float G_, float B, bool shadow)
    {
        text = text.ToUpperInvariant();
        int cols = 0; foreach (char ch in text) cols += 6; cols -= 1;
        double x = cx - cols * scale / 2.0;
        for (int pass = shadow ? 0 : 1; pass < 2; pass++)
        {
            double xx = x; int off = pass == 0 ? scale : 0;
            foreach (char ch in text)
            {
                string[] rows; if (!G.TryGetValue(ch, out rows)) rows = G[' '];
                for (int gy = 0; gy < 7; gy++) for (int gx = 0; gx < 5; gx++) if (rows[gy][gx] == '1')
                        {
                            int px = (int)Math.Round(xx + gx * scale) + off, py = (int)Math.Round(y + gy * scale) + off;
                            for (int j = 0; j < scale; j++) for (int i = 0; i < scale; i++)
                                    if (pass == 0) im.Over(px + i, py + j, 0.36f, 0.06f, 0.09f, 1f); else im.Over(px + i, py + j, R, G_, B, 1f);
                        }
                xx += 6 * scale;
            }
        }
    }

    // ---------------------------------------------------------------- credits: left Lushfoil / Annapurna, right Minecraft / Mojang
    static void MakeCredits()
    {
        int W = 1920, H = 1080;
        Img im = new Img(W, H);
        int half = W / 2;
        // LEFT: Lushfoil's own look -- misty pine forest in dawn light, and its menu style: black boxes, white lowercase type, cyan outline
        for (int y = 0; y < H; y++)
        {
            double t = y / (double)H;
            for (int x = 0; x < half; x++)
            {
                double n = Fbm(x * 0.004, y * 0.004, 3) * 0.06;
                double r = 0.80 - 0.50 * t + n, g = 0.86 - 0.42 * t + n, b = 0.84 - 0.46 * t + n;
                int i = y * W + x; im.r[i] = (float)r; im.g[i] = (float)g; im.b[i] = (float)b; im.a[i] = 1;
            }
        }
        // layered ridges in haze, each darker and clearer than the one behind
        for (int li = 0; li < 5; li++)
        {
            double baseY = H * (0.60 + li * 0.075); double amp = 130 - li * 14; double fog = 0.70 - li * 0.14;
            float cr = 0.40f - li * 0.065f, cg = 0.46f - li * 0.075f, cb = 0.47f - li * 0.075f;
            for (int x = 0; x < half; x++)
            {
                double ridge = baseY - (Fbm(x * 0.0032 + li * 10, li * 3.0, 20 + li) - 0.4) * amp * 2.2 - Math.Abs(Math.Sin(x * 0.0028 + li)) * 50;
                for (int y = (int)ridge; y < H; y++)
                {
                    if (y < 0) continue; int i = y * W + x;
                    double mist = Smooth(ridge, ridge + 240, y);
                    double f2 = fog + (1 - fog) * 0.55 * mist;
                    im.r[i] = (float)(im.r[i] * f2 + cr * (1 - f2)); im.g[i] = (float)(im.g[i] * f2 + cg * (1 - f2)); im.b[i] = (float)(im.b[i] * f2 + cb * (1 - f2));
                }
            }
        }
        // darken for legibility
        for (int y = 0; y < H; y++) for (int x = 0; x < half; x++) { int i = y * W + x; double d = 0.62 + 0.38 * Math.Min(1.0, Math.Abs(x - half / 2.0) / (half / 2.0) + 0.1); im.r[i] *= (float)d; im.g[i] *= (float)d; im.b[i] *= (float)d; }
        // RIGHT: Minecraft's loading screen red with its own pixel lettering, over the dirt texture's grid
        Img dirt = Tex("dirt_all");
        for (int y = 0; y < H; y++) for (int x = half; x < W; x++)
            {
                int i = y * W + x; im.a[i] = 1;
                im.r[i] = 0.937f; im.g[i] = 0.196f; im.b[i] = 0.239f;
            }
        Img overlay = new Img(W, H);
        // fine pixel grid like the game's panorama dither
        for (int y = 0; y < H; y += 8) for (int x = half; x < W; x += 8)
            {
                double v = H01(x / 8, y / 8, 4); float d = (float)((v - 0.5) * 0.045);
                for (int j = 0; j < 8; j++) for (int i2 = 0; i2 < 8; i2++) { int k = (y + j) * W + x + i2; im.r[k] += d; im.g[k] += d * 0.4f; im.b[k] += d * 0.4f; }
            }
        // divider
        for (int y = 0; y < H; y++) for (int x = half - 2; x < half + 2; x++) { int i = y * W + x; im.r[i] = 1f; im.g[i] = 1f; im.b[i] = 1f; im.a[i] = 1f; }
        for (int y = 0; y < H; y++) for (int x = 0; x < half - 2; x++) im.a[y * W + x] = 0f;
        Bitmap bm = im.ToBitmap();
        using (Graphics gr = Graphics.FromImage(bm))
        {
            gr.SmoothingMode = SmoothingMode.HighQuality; gr.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
        }
        Img fin = Img.FromBitmap(bm); bm.Dispose();
        // right typography in pixel letters
        int rcx = half + half / 2;
        PixelText(fin, "Minecraft", rcx, 230, 12, 1f, 1f, 1f, true);
        PixelText(fin, "Java Edition 1.21.1", rcx, 365, 4, 1f, 0.92f, 0.92f, true);
        PixelText(fin, "created by", rcx, 470, 5, 1f, 0.85f, 0.86f, true);
        PixelText(fin, "Markus Notch Persson", rcx, 530, 6, 1f, 1f, 1f, true);
        PixelText(fin, "developed by", rcx, 640, 5, 1f, 0.85f, 0.86f, true);
        PixelText(fin, "Mojang Studios", rcx, 700, 9, 1f, 1f, 1f, true);
        PixelText(fin, "Microsoft", rcx, 820, 4, 1f, 0.85f, 0.86f, true);
        using (Bitmap o = fin.ToBitmap()) o.Save(Path.Combine(root, "textures", "lc_credits.png"), ImageFormat.Png);
        Console.WriteLine("credits written");
    }

    // ---------------------------------------------------------------- the program icon: a dusk mountain scene with a grass block
    static void MakeIcon()
    {
        int W = 512, H = 512;
        Img im = new Img(W, H);
        for (int y = 0; y < H; y++)
        {
            double t = y / (double)H;
            for (int x = 0; x < W; x++)
            {
                double r = 0.30 + 0.62 * t, g = 0.30 + 0.45 * t, b = 0.55 + 0.20 * t;     // violet dusk to a warm horizon
                double glow = Math.Max(0, 1 - Math.Sqrt((x - 330) * (x - 330) + (y - 330) * (y - 330)) / 260.0);
                r += glow * 0.35; g += glow * 0.18;
                int i = y * W + x; im.r[i] = (float)r; im.g[i] = (float)g; im.b[i] = (float)b; im.a[i] = 1f;
            }
        }
        for (int li = 0; li < 3; li++)
        {
            double baseY = H * (0.50 + li * 0.13); double fog = 0.45 - li * 0.14;
            float cr = 0.20f - li * 0.05f, cg = 0.22f - li * 0.05f, cb = 0.34f - li * 0.07f;
            for (int x = 0; x < W; x++)
            {
                double ridge = baseY - (Fbm(x * 0.012 + li * 7, li * 2.0, 30 + li) - 0.35) * 190 - Math.Abs(Math.Sin(x * 0.011 + li * 2)) * 36;
                for (int y = (int)Math.Max(0, ridge); y < H; y++)
                {
                    int i = y * W + x; double snow = (li == 0 && y < ridge + 34) ? 0.55 : 0;
                    im.r[i] = (float)(im.r[i] * fog + (cr + snow) * (1 - fog)); im.g[i] = (float)(im.g[i] * fog + (cg + snow) * (1 - fog)); im.b[i] = (float)(im.b[i] * fog + (cb + snow * 1.1) * (1 - fog));
                }
            }
        }
        // the block: front, top and right faces lit like the logo
        Img top = Tex("grass_block_top"), side = Tex("grass_block_side");
        double s = 232, x0 = 112, y0 = 232, dx = s * 0.62, dy = -s * 0.46;
        Face(im, x0 + s, y0, dx, dy, 0, s, delegate(double u, double v, out float R, out float G_, out float B)
        { Shade(side, u, v, 0.50, u, v, 3, 2, x0 + s + dx * u, y0 + dy * u + v * s, 600, 600, null, out R, out G_, out B); });
        Face(im, x0, y0, s, 0, dx, dy, delegate(double u, double v, out float R, out float G_, out float B)
        { Shade(top, u, v, 1.0, u, v, 5, 1, x0 + u * s + dx * v, y0 + dy * v, 600, 600, null, out R, out G_, out B); });
        Face(im, x0, y0, s, 0, 0, s, delegate(double u, double v, out float R, out float G_, out float B)
        { Shade(side, u, v, 0.84, u, v, 1, 0, x0 + u * s, y0 + v * s, 600, 600, null, out R, out G_, out B); });
        // soft shadow under the block, then rounded corners
        for (int y = (int)(y0 + s); y < (int)(y0 + s) + 26 && y < H; y++)
            for (int x = (int)x0; x < (int)(x0 + s + dx); x++)
            {
                double k = (1 - (y - (y0 + s)) / 26.0) * 0.45; int i = y * W + x; im.r[i] *= (float)(1 - k); im.g[i] *= (float)(1 - k); im.b[i] *= (float)(1 - k);
            }
        double rad = 84;
        for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
            {
                double cx = Math.Min(x, W - 1 - x), cy = Math.Min(y, H - 1 - y), a = 1;
                if (cx < rad && cy < rad) { double d = Math.Sqrt((rad - cx) * (rad - cx) + (rad - cy) * (rad - cy)); a = Math.Max(0, Math.Min(1, rad - d + 0.5)); }
                im.a[y * W + x] = (float)a;
            }
        using (Bitmap big = im.ToBitmap())
        {
            big.Save(Path.Combine(root, "textures", "lc_icon.png"), ImageFormat.Png);
            int[] sizes = { 256, 64, 48, 32, 24, 16 };
            List<byte[]> pngs = new List<byte[]>();
            foreach (int sz in sizes)
                using (Bitmap sm = new Bitmap(sz, sz, PixelFormat.Format32bppArgb))
                {
                    using (Graphics g = Graphics.FromImage(sm)) { g.InterpolationMode = InterpolationMode.HighQualityBicubic; g.SmoothingMode = SmoothingMode.HighQuality; g.PixelOffsetMode = PixelOffsetMode.HighQuality; g.Clear(Color.Transparent); g.DrawImage(big, 0, 0, sz, sz); }
                    using (MemoryStream ms = new MemoryStream()) { sm.Save(ms, ImageFormat.Png); pngs.Add(ms.ToArray()); }
                }
            using (FileStream fs = new FileStream(Path.Combine(root, "textures", "lc_icon.ico"), FileMode.Create))
            using (BinaryWriter bw = new BinaryWriter(fs))
            {
                bw.Write((short)0); bw.Write((short)1); bw.Write((short)sizes.Length);
                int off = 6 + 16 * sizes.Length;
                for (int i = 0; i < sizes.Length; i++)
                {
                    bw.Write((byte)(sizes[i] >= 256 ? 0 : sizes[i])); bw.Write((byte)(sizes[i] >= 256 ? 0 : sizes[i])); bw.Write((byte)0); bw.Write((byte)0);
                    bw.Write((short)1); bw.Write((short)32); bw.Write(pngs[i].Length); bw.Write(off); off += pngs[i].Length;
                }
                for (int i = 0; i < sizes.Length; i++) bw.Write(pngs[i]);
            }
        }
        Console.WriteLine("icon written");
    }

    static void Main(string[] args)
    {
        string mode = args.Length > 0 ? args[0] : "logo";
        root = args.Length > 1 ? args[1] : ".";
        Glyphs();
        if (mode == "logo") MakeLogo();
        else if (mode == "credits") MakeCredits();
        else if (mode == "icon") MakeIcon();
        else Console.WriteLine("modes: logo, credits");
    }
}
