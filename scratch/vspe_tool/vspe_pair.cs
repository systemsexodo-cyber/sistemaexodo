using System;
using System.Runtime.InteropServices;
using System.Threading;

class VsPair {
    [DllImport("VSPE_API.dll", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    static extern bool vspe_activate(string key);
    [DllImport("VSPE_API.dll", CallingConvention = CallingConvention.Cdecl)]
    static extern IntPtr vspe_getActivationError();
    [DllImport("VSPE_API.dll", CallingConvention = CallingConvention.Cdecl)]
    static extern bool vspe_initialize();
    [DllImport("VSPE_API.dll", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    static extern int vspe_createDevice(string name, string initString);
    [DllImport("VSPE_API.dll", CallingConvention = CallingConvention.Cdecl)]
    static extern bool vspe_startEmulation();
    [DllImport("VSPE_API.dll", CallingConvention = CallingConvention.Cdecl)]
    static extern int vspe_getDevicesCount();
    [DllImport("VSPE_API.dll", CallingConvention = CallingConvention.Cdecl)]
    static extern bool vspe_stopEmulation();
    [DllImport("VSPE_API.dll", CallingConvention = CallingConvention.Cdecl)]
    static extern void vspe_release();
    [DllImport("VSPE_API.dll", CallingConvention = CallingConvention.Cdecl)]
    static extern IntPtr vspe_getVersionInformation();

    static string Str(IntPtr p) { return p == IntPtr.Zero ? "" : Marshal.PtrToStringAnsi(p); }

    static int Main() {
        Console.WriteLine("VSPE_API versao: " + Str(vspe_getVersionInformation()));
        if (!vspe_activate("")) { Console.WriteLine("Falha ativacao: " + Str(vspe_getActivationError())); return 1; }
        if (!vspe_initialize()) { Console.WriteLine("Falha inicializacao"); return 1; }
        int count = vspe_getDevicesCount();
        Console.WriteLine("Dispositivos atuais: " + count);
        if (count == 0) {
            int idx = vspe_createDevice("Pair", "5;6;0");
            if (idx == -1) { Console.WriteLine("Falha ao criar Pair COM5<->COM6"); vspe_release(); return 1; }
            Console.WriteLine("Pair COM5<->COM6 criado (index " + idx + ")");
        }
        if (!vspe_startEmulation()) { Console.WriteLine("Falha ao iniciar emulacao"); vspe_release(); return 1; }
        Console.WriteLine("Emulacao iniciada. Mantendo 90s para teste...");
        Thread.Sleep(90000);
        vspe_stopEmulation();
        vspe_release();
        Console.WriteLine("Encerrado.");
        return 0;
    }
}
