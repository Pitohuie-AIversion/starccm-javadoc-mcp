using System;
using System.Collections.Concurrent;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using Microsoft.Win32.SafeHandles;

public sealed class StarGuiProcess : IDisposable {
    private readonly ConcurrentQueue<string> lines = new ConcurrentQueue<string>();
    private IntPtr job;
    private IntPtr process;
    private StreamReader stdout;
    private StreamReader stderr;
    private Thread outputReader;
    private Thread errorReader;
    private bool disposed;

    private static string Quote(string value) {
        if (value.IndexOfAny(new[] { '"', '\r', '\n', '\0' }) >= 0)
            throw new ArgumentException("A process path contains an unsupported character.");
        return "\"" + Regex.Replace(value, @"(\\+)$", "$1$1") + "\"";
    }

    public StarGuiProcess(string executable, string directory, string worker, string request, string result) {
        IntPtr outRead = IntPtr.Zero, outWrite = IntPtr.Zero;
        IntPtr errRead = IntPtr.Zero, errWrite = IntPtr.Zero, input = IntPtr.Zero;
        Native.ProcessInformation started = new Native.ProcessInformation();
        bool assigned = false;
        try {
            job = Native.CreateJobObject(IntPtr.Zero, null);
            if (job == IntPtr.Zero) throw Failure("Cannot create worker process job");
            var limits = new Native.ExtendedLimits();
            limits.BasicLimitInformation.LimitFlags = 0x2000; // KILL_ON_JOB_CLOSE
            if (!Native.SetInformationJobObject(job, 9, ref limits, (uint)Marshal.SizeOf(limits)))
                throw Failure("Cannot configure worker process cleanup");

            var security = new Native.SecurityAttributes();
            security.Length = Marshal.SizeOf(security);
            security.InheritHandle = 1;
            CreateOutputPipe(ref security, out outRead, out outWrite);
            CreateOutputPipe(ref security, out errRead, out errWrite);
            input = Native.CreateFile("NUL", 0x80000000, 3, ref security, 3, 0, IntPtr.Zero);
            if (input == new IntPtr(-1)) throw Failure("Cannot open worker standard input");

            var startup = new Native.StartupInfo();
            startup.Size = Marshal.SizeOf(startup);
            startup.Flags = 0x100; // STARTF_USESTDHANDLES
            startup.Input = input;
            startup.Output = outWrite;
            startup.Error = errWrite;
            var command = new StringBuilder(Quote(executable) + " -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " + Quote(worker) + " -RequestFile " + Quote(request) + " -ResultFile " + Quote(result));
            // Suspend before the first instruction: the worker cannot spawn children
            // until it belongs to our private job, including in a nested host job.
            if (!Native.CreateProcess(executable, command, IntPtr.Zero, IntPtr.Zero, true,
                    0x08000004, IntPtr.Zero, directory, ref startup, out started))
                throw Failure("Cannot start background worker");
            process = started.Process;
            if (!Native.AssignProcessToJobObject(job, process))
                throw Failure("Cannot isolate the worker process tree; the worker was not started");
            assigned = true;

            // Only the child keeps the pipe write handles. EOF now follows when its
            // process tree exits, rather than waiting for a copy held by this GUI.
            Close(ref outWrite); Close(ref errWrite); Close(ref input);
            stdout = OpenReader(ref outRead);
            stderr = OpenReader(ref errRead);
            outputReader = StartReader(stdout);
            errorReader = StartReader(stderr);
            if (Native.ResumeThread(started.Thread) == uint.MaxValue)
                throw Failure("Cannot resume background worker");
        } catch {
            // If assignment was rejected, this process is still suspended and has
            // no descendants. Terminate only the process we just created.
            if (!assigned && process != IntPtr.Zero) Native.TerminateProcess(process, 1);
            Close(ref job);
            if (process != IntPtr.Zero) Native.WaitForSingleObject(process, 1000);
            Dispose();
            throw;
        } finally {
            Close(ref started.Thread);
            Close(ref outRead); Close(ref outWrite);
            Close(ref errRead); Close(ref errWrite); Close(ref input);
        }
    }

    private static Win32Exception Failure(string message) {
        return new Win32Exception(Marshal.GetLastWin32Error(), message);
    }

    private static void CreateOutputPipe(ref Native.SecurityAttributes security, out IntPtr read, out IntPtr write) {
        if (!Native.CreatePipe(out read, out write, ref security, 0)) throw Failure("Cannot create worker output pipe");
        if (!Native.SetHandleInformation(read, 1, 0)) throw Failure("Cannot protect worker output handle");
    }

    private static StreamReader OpenReader(ref IntPtr handle) {
        var owned = new SafeFileHandle(handle, true);
        handle = IntPtr.Zero;
        try { return new StreamReader(new FileStream(owned, FileAccess.Read), new UTF8Encoding(false), true); }
        catch { owned.Dispose(); throw; }
    }

    private Thread StartReader(StreamReader reader) {
        var thread = new Thread(() => {
            try {
                string line;
                while ((line = reader.ReadLine()) != null) lines.Enqueue(line);
            } catch (IOException) { } catch (ObjectDisposedException) { }
        });
        thread.IsBackground = true;
        thread.Start();
        return thread;
    }

    private void FinishReaders() {
        if (outputReader != null) outputReader.Join(500);
        if (errorReader != null) errorReader.Join(500);
    }

    private void StopJob() {
        if (job == IntPtr.Zero) return;
        try {
            if (!Native.TerminateJobObject(job, 1)) throw Failure("Cannot stop worker descendants");
            var clock = System.Diagnostics.Stopwatch.StartNew();
            while (true) {
                Native.Accounting counts;
                uint length;
                if (!Native.QueryInformationJobObject(job, 1, out counts, (uint)Marshal.SizeOf(typeof(Native.Accounting)), out length))
                    throw Failure("Cannot read worker process count");
                if (counts.ActiveProcesses == 0) break;
                if (clock.ElapsedMilliseconds >= 1500)
                    throw new InvalidOperationException("Worker descendants did not stop within 1.5 seconds.");
                Thread.Sleep(10);
            }
        } finally { Close(ref job); }
    }

    public bool HasExited {
        get {
            if (disposed) throw new ObjectDisposedException("StarGuiProcess");
            uint state = Native.WaitForSingleObject(process, 0);
            if (state == uint.MaxValue) throw Failure("Cannot read background worker state");
            return state == 0;
        }
    }

    public int ExitCode {
        get {
            if (!HasExited) throw new InvalidOperationException("The background worker is still running.");
            // A completed worker must not leave a subprocess holding the streams open.
            StopJob();
            FinishReaders();
            uint code;
            if (!Native.GetExitCodeProcess(process, out code)) throw Failure("Cannot read background worker exit code");
            return unchecked((int)code);
        }
    }

    public string Drain() {
        var text = new StringBuilder();
        string line;
        while (lines.TryDequeue(out line)) text.AppendLine(line);
        return text.ToString();
    }

    public void Stop() {
        if (disposed) return;
        StopJob(); // Wait for the private job to stop all descendants before returning.
        if (Native.WaitForSingleObject(process, 1500) != 0)
            throw new InvalidOperationException("The worker process did not stop within 1.5 seconds.");
        FinishReaders();
    }

    public void Dispose() {
        if (disposed) return;
        disposed = true;
        Close(ref job);
        if (stdout != null) stdout.Dispose();
        if (stderr != null) stderr.Dispose();
        Close(ref process);
    }

    private static void Close(ref IntPtr handle) {
        if (handle != IntPtr.Zero && handle != new IntPtr(-1)) Native.CloseHandle(handle);
        handle = IntPtr.Zero;
    }

    private static class Native {
        [StructLayout(LayoutKind.Sequential)] internal struct SecurityAttributes { public int Length; public IntPtr Descriptor; public int InheritHandle; }
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] internal struct StartupInfo {
            public int Size; public string Reserved; public string Desktop; public string Title;
            public uint X, Y, XSize, YSize, XCountChars, YCountChars, FillAttribute, Flags;
            public ushort ShowWindow, ReservedBytes; public IntPtr ReservedPointer, Input, Output, Error;
        }
        [StructLayout(LayoutKind.Sequential)] internal struct ProcessInformation { public IntPtr Process, Thread; public uint ProcessId, ThreadId; }
        [StructLayout(LayoutKind.Sequential)] internal struct BasicLimits {
            public long ProcessTime, JobTime; public uint LimitFlags;
            public UIntPtr MinimumWorkingSet, MaximumWorkingSet; public uint ActiveProcessLimit;
            public UIntPtr Affinity; public uint PriorityClass, SchedulingClass;
        }
        [StructLayout(LayoutKind.Sequential)] internal struct IoCounters { public ulong ReadOperations, WriteOperations, OtherOperations, ReadBytes, WriteBytes, OtherBytes; }
        [StructLayout(LayoutKind.Sequential)] internal struct ExtendedLimits {
            public BasicLimits BasicLimitInformation; public IoCounters IoInfo;
            public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed;
        }
        [StructLayout(LayoutKind.Sequential)] internal struct Accounting {
            public long UserTime, KernelTime, PeriodUserTime, PeriodKernelTime;
            public uint PageFaults, TotalProcesses, ActiveProcesses, TerminatedProcesses;
        }
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] internal static extern IntPtr CreateJobObject(IntPtr attributes, string name);
        [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool SetInformationJobObject(IntPtr job, int infoClass, ref ExtendedLimits limits, uint length);
        [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
        [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool TerminateJobObject(IntPtr job, uint code);
        [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool QueryInformationJobObject(IntPtr job, int kind, out Accounting counts, uint size, out uint length);
        [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool CreatePipe(out IntPtr read, out IntPtr write, ref SecurityAttributes attributes, uint size);
        [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool SetHandleInformation(IntPtr handle, uint mask, uint flags);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] internal static extern IntPtr CreateFile(string path, uint access, uint share, ref SecurityAttributes security, uint creation, uint flags, IntPtr template);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool CreateProcess(string application, StringBuilder command, IntPtr processAttributes, IntPtr threadAttributes, [MarshalAs(UnmanagedType.Bool)] bool inheritHandles, uint flags, IntPtr environment, string directory, ref StartupInfo startup, out ProcessInformation information);
        [DllImport("kernel32.dll", SetLastError = true)] internal static extern uint ResumeThread(IntPtr thread);
        [DllImport("kernel32.dll", SetLastError = true)] internal static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
        [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool GetExitCodeProcess(IntPtr process, out uint code);
        [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool TerminateProcess(IntPtr process, uint code);
        [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool CloseHandle(IntPtr handle);
    }
}

