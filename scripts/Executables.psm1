# Keep this runner independent of the GUI: CLI deployment uses it too. Commands
# start suspended, enter a private job, then run; timeout cleanup owns only that job.
if (-not ('Starccm.CommandRunner' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Win32.SafeHandles;
namespace Starccm {
 public sealed class CommandResult { public string Output, Error; public int ExitCode; public bool TimedOut; }
 public static class CommandRunner {
  public static CommandResult Run(ProcessStartInfo info, int timeoutMs) {
   IntPtr job=IntPtr.Zero, outRead=IntPtr.Zero, outWrite=IntPtr.Zero, errRead=IntPtr.Zero, errWrite=IntPtr.Zero, input=IntPtr.Zero, environment=IntPtr.Zero;
   Native.ProcessInfo child=new Native.ProcessInfo();
   StreamReader stdout=null, stderr=null;
   bool assigned=false;
   try {
    job=Native.CreateJobObject(IntPtr.Zero,null);
    if(job==IntPtr.Zero) throw Failure("Cannot create command job");
    var limits=new Native.ExtendedLimits(); limits.Basic.LimitFlags=0x2000;
    if(!Native.SetInformationJobObject(job,9,ref limits,(uint)Marshal.SizeOf(limits))) throw Failure("Cannot configure command cleanup");
    var security=new Native.Security(); security.Length=Marshal.SizeOf(security); security.Inherit=1;
    Pipe(ref security,out outRead,out outWrite); Pipe(ref security,out errRead,out errWrite);
    input=Native.CreateFile("NUL",0x80000000,3,ref security,3,0,IntPtr.Zero);
    if(input==new IntPtr(-1)) throw Failure("Cannot open command input");
    var values=new SortedDictionary<string,string>(StringComparer.OrdinalIgnoreCase);
    foreach(DictionaryEntry pair in info.EnvironmentVariables) values[(string)pair.Key]=(string)pair.Value;
    var block=new StringBuilder(); foreach(var pair in values) block.Append(pair.Key).Append('=').Append(pair.Value).Append('\0'); block.Append('\0');
    environment=Marshal.StringToHGlobalUni(block.ToString());
    var startup=new Native.Startup(); startup.Size=Marshal.SizeOf(startup); startup.Flags=0x100; startup.Input=input; startup.Output=outWrite; startup.Error=errWrite;
    var command=new StringBuilder("\""+info.FileName+"\" "+info.Arguments);
    if(!Native.CreateProcess(info.FileName,command,IntPtr.Zero,IntPtr.Zero,true,0x08000404,environment,info.WorkingDirectory,ref startup,out child)) throw Failure("Cannot start command");
    if(!Native.AssignProcessToJobObject(job,child.Process)) throw Failure("Cannot isolate command process tree");
    assigned=true;
    Close(ref outWrite); Close(ref errWrite); Close(ref input);
    stdout=Reader(ref outRead); stderr=Reader(ref errRead);
    Task<string> outTask=stdout.ReadToEndAsync(), errTask=stderr.ReadToEndAsync();
    if(Native.ResumeThread(child.Thread)==uint.MaxValue) throw Failure("Cannot resume command");
    uint state=Native.WaitForSingleObject(child.Process,(uint)timeoutMs);
    if(state==uint.MaxValue) throw Failure("Cannot wait for command");
    bool timeout=state==258;
    // Terminate descendants before waiting for EOF, including helpers left by a
    // parent that exited normally. This never closes the surrounding GUI job.
    StopJob(ref job);
    if(Native.WaitForSingleObject(child.Process,2000)!=0) throw new TimeoutException("Command process did not stop after cleanup.");
    if(!Task.WaitAll(new Task[]{outTask,errTask},2000)) throw new TimeoutException("Command output did not close after cleanup.");
    uint code; if(!Native.GetExitCodeProcess(child.Process,out code)) throw Failure("Cannot read command exit code");
    return new CommandResult {Output=outTask.Result,Error=errTask.Result,ExitCode=timeout?124:unchecked((int)code),TimedOut=timeout};
   } finally {
    if(!assigned && child.Process!=IntPtr.Zero) Native.TerminateProcess(child.Process,1);
    Close(ref job);
    if(child.Process!=IntPtr.Zero) Native.WaitForSingleObject(child.Process,2000);
    if(stdout!=null) stdout.Dispose(); if(stderr!=null) stderr.Dispose();
    Close(ref child.Thread); Close(ref child.Process); Close(ref outRead); Close(ref outWrite); Close(ref errRead); Close(ref errWrite); Close(ref input);
    if(environment!=IntPtr.Zero) Marshal.FreeHGlobal(environment);
   }
  }
  static Win32Exception Failure(string message) {return new Win32Exception(Marshal.GetLastWin32Error(),message);}
  static void StopJob(ref IntPtr job) {
   if(!Native.TerminateJobObject(job,1)) throw Failure("Cannot stop command descendants");
   var clock=Stopwatch.StartNew();
   while(true) {
    Native.Accounting counts; uint length;
    if(!Native.QueryInformationJobObject(job,1,out counts,(uint)Marshal.SizeOf(typeof(Native.Accounting)),out length)) throw Failure("Cannot read command process count");
    if(counts.ActiveProcesses==0) break;
    if(clock.ElapsedMilliseconds>=2000) throw new TimeoutException("Command descendants did not stop after cleanup.");
    System.Threading.Thread.Sleep(10);
   }
   Close(ref job);
  }
  static void Pipe(ref Native.Security security,out IntPtr read,out IntPtr write) {
   if(!Native.CreatePipe(out read,out write,ref security,0)) throw Failure("Cannot create command output pipe");
   if(!Native.SetHandleInformation(read,1,0)) throw Failure("Cannot protect command output handle");
  }
  static StreamReader Reader(ref IntPtr handle) {
   var owned=new SafeFileHandle(handle,true); handle=IntPtr.Zero;
   try {return new StreamReader(new FileStream(owned,FileAccess.Read),new UTF8Encoding(false),true);} catch {owned.Dispose();throw;}
  }
  static void Close(ref IntPtr handle) {if(handle!=IntPtr.Zero && handle!=new IntPtr(-1)) Native.CloseHandle(handle); handle=IntPtr.Zero;}
  static class Native {
   [StructLayout(LayoutKind.Sequential)] internal struct Security {public int Length;public IntPtr Descriptor;public int Inherit;}
   [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] internal struct Startup {public int Size;public string Reserved,Desktop,Title;public uint X,Y,XSize,YSize,XChars,YChars,Fill,Flags;public ushort Show,Bytes;public IntPtr ReservedPointer,Input,Output,Error;}
   [StructLayout(LayoutKind.Sequential)] internal struct ProcessInfo {public IntPtr Process,Thread;public uint ProcessId,ThreadId;}
   [StructLayout(LayoutKind.Sequential)] internal struct BasicLimits {public long ProcessTime,JobTime;public uint LimitFlags;public UIntPtr MinWork,MaxWork;public uint ActiveProcesses;public UIntPtr Affinity;public uint Priority,Scheduling;}
   [StructLayout(LayoutKind.Sequential)] internal struct IoCounters {public ulong ReadOps,WriteOps,OtherOps,ReadBytes,WriteBytes,OtherBytes;}
   [StructLayout(LayoutKind.Sequential)] internal struct ExtendedLimits {public BasicLimits Basic;public IoCounters Io;public UIntPtr ProcessMemory,JobMemory,PeakProcess,PeakJob;}
   [StructLayout(LayoutKind.Sequential)] internal struct Accounting {public long UserTime,KernelTime,PeriodUserTime,PeriodKernelTime;public uint PageFaults,TotalProcesses,ActiveProcesses,TerminatedProcesses;}
   [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] internal static extern IntPtr CreateJobObject(IntPtr attributes,string name);
   [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool SetInformationJobObject(IntPtr job,int kind,ref ExtendedLimits limits,uint length);
   [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool AssignProcessToJobObject(IntPtr job,IntPtr process);
   [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool TerminateJobObject(IntPtr job,uint code);
   [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool QueryInformationJobObject(IntPtr job,int kind,out Accounting counts,uint size,out uint length);
   [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool CreatePipe(out IntPtr read,out IntPtr write,ref Security security,uint size);
   [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool SetHandleInformation(IntPtr handle,uint mask,uint flags);
   [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] internal static extern IntPtr CreateFile(string path,uint access,uint share,ref Security security,uint creation,uint flags,IntPtr template);
   [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool CreateProcess(string application,StringBuilder command,IntPtr processAttributes,IntPtr threadAttributes,[MarshalAs(UnmanagedType.Bool)]bool inherit,uint flags,IntPtr environment,string directory,ref Startup startup,out ProcessInfo process);
   [DllImport("kernel32.dll",SetLastError=true)] internal static extern uint ResumeThread(IntPtr thread);
   [DllImport("kernel32.dll",SetLastError=true)] internal static extern uint WaitForSingleObject(IntPtr handle,uint milliseconds);
   [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool GetExitCodeProcess(IntPtr process,out uint code);
   [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool TerminateProcess(IntPtr process,uint code);
   [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool CloseHandle(IntPtr handle);
  }
 }
}
'@
}

function Find-Executable {
    param([string]$Explicit, [string[]]$Names, [string[]]$Fallbacks)
    if ($Explicit) {
        if (-not (Test-Path -LiteralPath $Explicit -PathType Leaf)) { throw "Executable not found: $Explicit" }
        return (Resolve-Path -LiteralPath $Explicit).ProviderPath
    }
    foreach ($name in $Names) {
        $cmd = Get-Command $name -CommandType Application,ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { return $cmd.Source }
    }
    foreach ($p in $Fallbacks) { if (Test-Path -LiteralPath $p -PathType Leaf) { return (Resolve-Path -LiteralPath $p).ProviderPath } }
    throw "Executable not found ($($Names -join ', ')). Install it or supply its absolute path."
}
function Invoke-Executable {
    [CmdletBinding()]
    param([string]$Path, [string[]]$Arguments, [ValidateRange(1,3600)][int]$TimeoutSeconds = 60)
    $global:LASTEXITCODE = -1
    if ($Path -and -not [IO.Path]::IsPathRooted($Path) -and $Path -notmatch '[\\/]' -and -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $Path = Find-Executable '' @($Path) @()
    } else { $Path = Find-Executable $Path @() @() }
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.WorkingDirectory = (Get-Location).ProviderPath
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $start.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    $extension = [IO.Path]::GetExtension($Path)
    if ($extension -match '^\.(cmd|bat)$') {
        # Expand each cmd argument once through its private environment variable.
        $start.FileName = Join-Path $env:SystemRoot 'System32/cmd.exe'
        if ($Path -match '["\r\n\x00]') { throw 'Unsupported quote/newline in launcher path.' }
        $start.EnvironmentVariables['STARCCM_LAUNCHER'] = $Path
        $parts = @('"%STARCCM_LAUNCHER%"')
        for ($i = 0; $i -lt $Arguments.Count; $i++) {
            $arg = $Arguments[$i]
            if ($arg -match '["\r\n\x00]') { throw 'Unsupported quote/newline in command argument.' }
            if ($arg.Length -eq 0) { $parts += '""'; continue }
            $key = "STARCCM_LAUNCH_ARG_$i"
            $start.EnvironmentVariables[$key] = [regex]::Replace($arg, '(\\+)$', '$1$1')
            $parts += ('"%' + $key + '%"')
        }
        $start.Arguments = '/d /s /v:off /c "' + ($parts -join ' ') + '"'
    } elseif ($extension -ieq '.ps1') {
        $start.FileName = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ([IO.Path]::GetFileNameWithoutExtension($start.FileName) -notin @('powershell','pwsh')) { $start.FileName = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe' }
        $start.EnvironmentVariables['STARCCM_EXEC_SCRIPT'] = $Path
        $start.EnvironmentVariables['STARCCM_EXEC_ARGS'] = ConvertTo-Json -InputObject @($Arguments) -Compress
        $command = @'
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding
$global:LASTEXITCODE = 0
try {
    $values = [string[]](ConvertFrom-Json -InputObject $env:STARCCM_EXEC_ARGS)
    & $env:STARCCM_EXEC_SCRIPT @values 6>&1 | ForEach-Object { [Console]::Out.WriteLine($_) }
    exit $global:LASTEXITCODE
} catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }
'@
        $start.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -OutputFormat Text -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    } else {
        $start.FileName = $Path
        $parts = foreach ($arg in $Arguments) {
            if ($arg -match '\x00') { throw 'NUL is not supported in command arguments.' }
            '"' + [regex]::Replace([regex]::Replace($arg, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
        }
        $start.Arguments = $parts -join ' '
    }
    $result = [Starccm.CommandRunner]::Run($start, ($TimeoutSeconds * 1000))
    $global:LASTEXITCODE = $result.ExitCode
    if ($result.Error) { [Console]::Error.Write($result.Error) }
    if ($result.TimedOut) { throw "Command timed out after $TimeoutSeconds seconds: $Path" }
    if ($result.Output) { Write-Output $result.Output }
}
Export-ModuleMember -Function Find-Executable, Invoke-Executable
