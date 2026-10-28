using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Windows.Forms;

internal static class Launcher {
    [STAThread]
    private static void Main() {
        try {
            string root = AppDomain.CurrentDomain.BaseDirectory;
            string script = Path.Combine(root, "gui.ps1");
            if (!File.Exists(script)) throw new FileNotFoundException("Please extract the entire ZIP before opening this application.", script);
            string ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
            string command = "try { & $env:STARCCM_GUI_SCRIPT } catch { Add-Type -AssemblyName System.Windows.Forms; [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message + [Environment]::NewLine + $env:STARCCM_GUI_SCRIPT, 'STAR-CCM+ Codex', 'OK', 'Error'); exit 1 }";
            var info = new ProcessStartInfo(ps, "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand " + Convert.ToBase64String(Encoding.Unicode.GetBytes(command)));
            info.UseShellExecute = false;
            info.CreateNoWindow = true;
            info.WorkingDirectory = root;
            info.EnvironmentVariables["STARCCM_GUI_SCRIPT"] = script;
            Process.Start(info);
        } catch (Exception error) {
            MessageBox.Show(error.Message, "STAR-CCM+ Codex", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
