// Replaces the icon of a Windows program with an .ico file (resource update only; the program's code is untouched).
//   IconPatch.exe list  <exe>          -> shows the exe's icon groups
//   IconPatch.exe apply <exe> <ico>    -> writes the .ico as the exe's icon
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;

static class IconPatch
{
    delegate bool EnumNames(IntPtr hModule, IntPtr type, IntPtr name, IntPtr param);
    delegate bool EnumLangs(IntPtr hModule, IntPtr type, IntPtr name, ushort lang, IntPtr param);
    [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)] static extern IntPtr LoadLibraryEx(string f, IntPtr h, uint flags);
    [DllImport("kernel32", SetLastError = true)] static extern bool FreeLibrary(IntPtr h);
    [DllImport("kernel32", SetLastError = true)] static extern bool EnumResourceNames(IntPtr h, IntPtr type, EnumNames cb, IntPtr p);
    [DllImport("kernel32", SetLastError = true)] static extern bool EnumResourceLanguages(IntPtr h, IntPtr type, IntPtr name, EnumLangs cb, IntPtr p);
    [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)] static extern IntPtr BeginUpdateResource(string f, bool del);
    [DllImport("kernel32", SetLastError = true)] static extern bool UpdateResource(IntPtr h, IntPtr type, IntPtr name, ushort lang, byte[] data, uint size);
    [DllImport("kernel32", SetLastError = true)] static extern bool EndUpdateResource(IntPtr h, bool discard);

    static IntPtr RT_ICON = (IntPtr)3, RT_GROUP_ICON = (IntPtr)14;

    static List<IntPtr> names = new List<IntPtr>();
    static List<ushort> langs = new List<ushort>();

    static int Main(string[] a)
    {
        string mode = a.Length > 0 ? a[0] : "";
        string exe = a.Length > 1 ? a[1] : "";
        IntPtr h = LoadLibraryEx(exe, IntPtr.Zero, 2);
        if (h == IntPtr.Zero) { Console.WriteLine("cannot open " + exe); return 1; }
        EnumResourceNames(h, RT_GROUP_ICON, delegate(IntPtr m, IntPtr t, IntPtr n, IntPtr p) { names.Add(n); return true; }, IntPtr.Zero);
        foreach (IntPtr n in names)
        {
            EnumResourceLanguages(h, RT_GROUP_ICON, n, delegate(IntPtr m, IntPtr t, IntPtr nn, ushort l, IntPtr p) { langs.Add(l); return true; }, IntPtr.Zero);
            Console.WriteLine("icon group " + ((long)n < 65536 ? ((long)n).ToString() : Marshal.PtrToStringUni(n)) + " lang " + (langs.Count > 0 ? langs[langs.Count - 1].ToString() : "?"));
        }
        FreeLibrary(h);
        if (mode != "apply") return 0;
        byte[] ico = File.ReadAllBytes(a[2]);
        int count = BitConverter.ToUInt16(ico, 4);
        IntPtr name = names.Count > 0 ? names[0] : (IntPtr)101;
        ushort lang = langs.Count > 0 ? langs[0] : (ushort)1033;
        IntPtr u = BeginUpdateResource(exe, false);
        if (u == IntPtr.Zero) { Console.WriteLine("cannot update (is the game running?) err " + Marshal.GetLastWin32Error()); return 2; }
        using (MemoryStream grp = new MemoryStream())
        using (BinaryWriter bw = new BinaryWriter(grp))
        {
            bw.Write((ushort)0); bw.Write((ushort)1); bw.Write((ushort)count);
            for (int i = 0; i < count; i++)
            {
                int e = 6 + 16 * i;
                int size = BitConverter.ToInt32(ico, e + 8), off = BitConverter.ToInt32(ico, e + 12);
                byte[] img = new byte[size]; Array.Copy(ico, off, img, 0, size);
                ushort id = (ushort)(300 + i);
                if (!UpdateResource(u, RT_ICON, (IntPtr)id, lang, img, (uint)size)) { Console.WriteLine("icon image failed " + Marshal.GetLastWin32Error()); EndUpdateResource(u, true); return 3; }
                bw.Write(ico[e]); bw.Write(ico[e + 1]); bw.Write(ico[e + 2]); bw.Write(ico[e + 3]);
                bw.Write(BitConverter.ToUInt16(ico, e + 4)); bw.Write(BitConverter.ToUInt16(ico, e + 6));
                bw.Write(size); bw.Write(id);
            }
            byte[] g = grp.ToArray();
            // every icon group of the program (Explorer may use any of them)
            for (int k = 0; k < Math.Max(1, names.Count); k++)
            {
                IntPtr nm = names.Count > 0 ? names[k] : name;
                ushort lg = k < langs.Count ? langs[k] : lang;
                if (!UpdateResource(u, RT_GROUP_ICON, nm, lg, g, (uint)g.Length)) { Console.WriteLine("group failed " + Marshal.GetLastWin32Error()); EndUpdateResource(u, true); return 4; }
            }
        }
        if (!EndUpdateResource(u, false)) { Console.WriteLine("write failed " + Marshal.GetLastWin32Error()); return 5; }
        Console.WriteLine("icon replaced");
        return 0;
    }
}
