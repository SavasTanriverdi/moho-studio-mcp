import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { spawn, execFile } from "node:child_process";
import { getIpcDir, TIMEOUTS } from "./config.mjs";

const DOC_LIFECYCLE_METHODS = new Set(["document.new", "document.open", "document.close", "document.exportGltf"]);

function isDocLifecycleCall(method, params) {
  if (DOC_LIFECYCLE_METHODS.has(method)) {
    return true;
  }
  if (method === "batch.execute" && Array.isArray(params?.operations)) {
    return params.operations.some((op) => DOC_LIFECYCLE_METHODS.has(op?.method));
  }
  return false;
}

export function escapePsSingleQuoted(value) {
  return String(value).replace(/'/g, "''");
}

function buildKeepAlivePs(ipcDir) {
  const escapedDir = escapePsSingleQuoted(ipcDir);
  return `
Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class MohoStudioKeepAlive {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr hWndParent, EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool InvalidateRect(IntPtr hWnd, IntPtr lpRect, bool bErase);
  [DllImport("user32.dll")] public static extern bool RedrawWindow(IntPtr hWnd, IntPtr lprcUpdate, IntPtr hrgnUpdate, uint flags);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

  public static IntPtr FindPrimaryWindow(uint targetPid) {
    IntPtr best = IntPtr.Zero;
    long bestArea = -1;
    EnumWindows((h, l) => {
      uint pid = 0;
      GetWindowThreadProcessId(h, out pid);
      if (pid != targetPid || !IsWindowVisible(h) || IsIconic(h)) return true;
      RECT r;
      if (GetWindowRect(h, out r)) {
        long w = Math.Max(0, r.Right - r.Left);
        long ht = Math.Max(0, r.Bottom - r.Top);
        long area = w * ht;
        if (area > bestArea && w >= 200 && ht >= 150) {
          bestArea = area;
          best = h;
        }
      }
      return true;
    }, IntPtr.Zero);
    return best;
  }

  public static List<IntPtr> GetCanvasChildren(IntPtr parent) {
    var list = new List<IntPtr>();
    EnumChildWindows(parent, (h, l) => {
      if (!IsWindowVisible(h)) return true;
      RECT r;
      if (GetWindowRect(h, out r)) {
        long w = Math.Max(0, r.Right - r.Left);
        long ht = Math.Max(0, r.Bottom - r.Top);
        if (w >= 160 && ht >= 120) {
          list.Add(h);
        }
      }
      return true;
    }, IntPtr.Zero);
    return list;
  }
}
"@
$ipcDir = '${escapedDir}'
$rdwFlags = [uint32](0x0001 -bor 0x0004 -bor 0x0080 -bor 0x0100)
$toggle = 0
while ($true) {
  try {
    # Only pulse Moho while an IPC request file is pending (zero interference during user drawing)
    $hasReq = [System.IO.Directory]::Exists($ipcDir) -and ([System.IO.Directory]::GetFiles($ipcDir, 'req_*.json').Length -gt 0)
    if ($hasReq) {
      $toggle = 1 - $toggle
      $lParam = [IntPtr]((120 -shl 16) -bor (120 + $toggle))
      $procs = Get-Process -Name "Moho" -ErrorAction SilentlyContinue
      foreach ($p in $procs) {
        $hwnd = [MohoStudioKeepAlive]::FindPrimaryWindow([uint32]$p.Id)
        if ($hwnd -eq [IntPtr]::Zero) { $hwnd = $p.MainWindowHandle }
        if ($hwnd -ne [IntPtr]::Zero -and -not [MohoStudioKeepAlive]::IsIconic($hwnd)) {
          [MohoStudioKeepAlive]::RedrawWindow($hwnd, [IntPtr]::Zero, [IntPtr]::Zero, $rdwFlags) | Out-Null
          [MohoStudioKeepAlive]::PostMessage($hwnd, 0x0200, [IntPtr]::Zero, $lParam) | Out-Null
          foreach ($child in [MohoStudioKeepAlive]::GetCanvasChildren($hwnd)) {
            [MohoStudioKeepAlive]::RedrawWindow($child, [IntPtr]::Zero, [IntPtr]::Zero, $rdwFlags) | Out-Null
            [MohoStudioKeepAlive]::PostMessage($child, 0x0200, [IntPtr]::Zero, $lParam) | Out-Null
          }
        }
      }
      Start-Sleep -Milliseconds 70
    } else {
      Start-Sleep -Milliseconds 120
    }
  } catch {
    Start-Sleep -Milliseconds 200
  }
}
`;
}

export function buildCaptureWindowPs(targetPath) {
  const escapedTarget = escapePsSingleQuoted(targetPath);
  return `
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class WinCap2 {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdcBlt, uint nFlags);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

  public static IntPtr FindLargestVisibleWindow(uint targetPid, out bool sawMinimized) {
    IntPtr best = IntPtr.Zero;
    long bestArea = -1;
    bool minFlag = false;
    EnumWindows((h, l) => {
      uint pid = 0;
      GetWindowThreadProcessId(h, out pid);
      if (pid != targetPid || !IsWindowVisible(h)) return true;
      if (IsIconic(h)) { minFlag = true; return true; }
      RECT r;
      if (GetWindowRect(h, out r)) {
        long w = Math.Max(0, r.Right - r.Left);
        long ht = Math.Max(0, r.Bottom - r.Top);
        long area = w * ht;
        if (area > bestArea && w >= 200 && ht >= 150) {
          bestArea = area;
          best = h;
        }
      }
      return true;
    }, IntPtr.Zero);
    sawMinimized = minFlag;
    return best;
  }
}
"@
$procs = Get-Process -Name "Moho" -ErrorAction Stop
$hwnd = [IntPtr]::Zero
$anyMinimized = $false
foreach ($p in $procs) {
  $minOut = $false
  $cand = [WinCap2]::FindLargestVisibleWindow([uint32]$p.Id, [ref]$minOut)
  if ($minOut) { $anyMinimized = $true }
  if ($cand -ne [IntPtr]::Zero) { $hwnd = $cand; break }
}
if ($hwnd -eq [IntPtr]::Zero) {
  if ($anyMinimized) { throw "Moho Pro 14 window is minimized; restore Moho window to capture UI or use document_renderFrame" }
  throw "No visible Moho Pro 14 main window found"
}
$rect = New-Object WinCap2+RECT
[WinCap2]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
$w = [Math]::Max(1, $rect.Right - $rect.Left)
$h = [Math]::Max(1, $rect.Bottom - $rect.Top)
$bmp = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
[WinCap2]::PrintWindow($hwnd, $hdc, 2) | Out-Null
$g.ReleaseHdc($hdc)
$g.Dispose()
$bmp.Save('${escapedTarget}', [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
$sb = New-Object System.Text.StringBuilder 256
[WinCap2]::GetWindowText($hwnd, $sb, 256) | Out-Null
Write-Output "$w,$h,$($sb.ToString())"
`;
}

export class MohoIpcClient {
  constructor(ipcDir = getIpcDir()) {
    this.ipcDir = ipcDir;
    this.seq = 0;
    this.keepAliveProc = null;
    this.keepAliveScriptPath = null;
    this.lastPollerAttemptMs = 0;
  }

  ensureIpcDir() {
    fs.mkdirSync(this.ipcDir, { recursive: true });
  }

  readStatus() {
    const statusPath = path.join(this.ipcDir, "status.json");
    if (!fs.existsSync(statusPath)) {
      return null;
    }
    try {
      return JSON.parse(fs.readFileSync(statusPath, "utf8"));
    } catch {
      return null;
    }
  }

  startKeepAlive() {
    if (process.platform !== "win32" || this.keepAliveProc) {
      return;
    }
    try {
      this.ensureIpcDir();
      this.keepAliveScriptPath = path.join(this.ipcDir, `.keepalive_${process.pid}.ps1`);
      fs.writeFileSync(this.keepAliveScriptPath, buildKeepAlivePs(this.ipcDir), "utf8");
      this.keepAliveProc = spawn(
        "powershell.exe",
        ["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", this.keepAliveScriptPath],
        { stdio: "ignore", windowsHide: true }
      );
      this.keepAliveProc.on("exit", () => {
        this.keepAliveProc = null;
      });
    } catch {
      this.keepAliveProc = null;
    }
  }

  stopKeepAlive() {
    if (this.keepAliveProc) {
      try {
        this.keepAliveProc.kill();
      } catch {}
      this.keepAliveProc = null;
    }
    if (this.keepAliveScriptPath) {
      try {
        fs.unlinkSync(this.keepAliveScriptPath);
      } catch {}
      this.keepAliveScriptPath = null;
    }
  }

  async send(method, params = {}, timeoutMs = TIMEOUTS.defaultMs) {
    this.ensureIpcDir();
    const status = this.readStatus();
    if (!status || !status.running) {
      throw new Error(
        `MohoStudioMCP Server is not active (missing ${path.join(this.ipcDir, "status.json")}). ` +
          "In Moho Pro 14, click Scripts > MohoStudioMCP > Start/Stop MohoStudioMCP Server."
      );
    }

    const needsCommandStack = isDocLifecycleCall(method, params);
    if (!needsCommandStack) {
      this.startKeepAlive();
    }

    this.seq += 1;
    const reqId = `r_${process.pid}_${this.seq}_${crypto.randomBytes(4).toString("hex")}`;
    const reqPath = path.join(this.ipcDir, `req_${reqId}.json`);
    const reqTmp = `${reqPath}.tmp`;
    const respPath = path.join(this.ipcDir, `resp_${reqId}.json`);

    const payload = JSON.stringify({
      jsonrpc: "2.0",
      id: reqId,
      method,
      params,
    });

    fs.writeFileSync(reqTmp, payload, "utf8");
    fs.renameSync(reqTmp, reqPath);

    const startedWait = Date.now();
    const deadline = startedWait + timeoutMs;
    const pollerDelayMs = needsCommandStack ? 50 : 450;
    let pollerTried = false;
    while (Date.now() < deadline) {
      if (fs.existsSync(respPath)) {
        let raw = "";
        try {
          raw = fs.readFileSync(respPath, "utf8");
          fs.unlinkSync(respPath);
        } catch {
          await sleep(15);
          continue;
        }
        const parsed = JSON.parse(raw);
        if (parsed.error) {
          throw new Error(parsed.error.message || "Moho Lua error");
        }
        return parsed.result;
      }
      // If Moho has not responded after pollerDelayMs (50ms for document lifecycle calls,
      // 450ms otherwise), ensure our MohoStudioMCP Poller tool is active and click its
      // "MCP Sync" UI button via background PostMessage (clean HandleMessage command stack).
      if (
        process.platform === "win32" &&
        Date.now() - startedWait >= pollerDelayMs &&
        (!pollerTried || Date.now() - this.lastPollerAttemptMs >= 2200)
      ) {
        pollerTried = true;
        this.lastPollerAttemptMs = Date.now();
        await this.activatePoller().catch(() => {});
      }
      await sleep(TIMEOUTS.pollIntervalMs);
    }

    try {
      if (fs.existsSync(reqPath)) fs.unlinkSync(reqPath);
    } catch {}
    throw new Error(
      `MohoStudioMCP request timed out after ${timeoutMs}ms for '${method}'. ` +
        "Ensure Moho Pro 14 is not minimized, no modal dialog is blocking Moho, and MohoStudioMCP Server is running."
    );
  }

  async captureWindow(outputPath) {
    if (process.platform !== "win32") {
      throw new Error("document_captureWindow is currently implemented for Windows");
    }
    this.ensureIpcDir();
    const targetPath = path.resolve(outputPath || path.join(this.ipcDir, `window_${process.pid}_${Date.now()}.png`));
    fs.mkdirSync(path.dirname(targetPath), { recursive: true });
    const psScript = buildCaptureWindowPs(targetPath);
    const infoLine = await new Promise((resolve, reject) => {
      execFile(
        "powershell.exe",
        ["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", psScript],
        { timeout: 15_000, windowsHide: true },
        (err, stdout, stderr) => {
          if (err) {
            reject(new Error(`Window capture failed: ${(stderr || err.message).trim()}`));
          } else {
            resolve(stdout.trim());
          }
        }
      );
    });
    const parts = infoLine.split(",");
    const w = Number(parts[0]) || 0;
    const h = Number(parts[1]) || 0;
    const title = parts.slice(2).join(",");
    return { outputPath: targetPath, width: w, height: h, windowTitle: title };
  }

  async activatePoller() {
    if (process.platform !== "win32") {
      return { activated: false, reason: "moho_activatePoller is currently implemented for Windows" };
    }
    const psScript = `
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @"
using System;
using System.Text;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public class MohoPollerActivator {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr hWndParent, EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool ScreenToClient(IntPtr hWnd, ref POINT lpPoint);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdcBlt, uint nFlags);
  [DllImport("user32.dll")] public static extern bool RedrawWindow(IntPtr hWnd, IntPtr lprcUpdate, IntPtr hrgnUpdate, uint flags);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

  public static IntPtr FindPrimaryWindow(uint targetPid) {
    IntPtr best = IntPtr.Zero;
    long bestArea = -1;
    EnumWindows((h, l) => {
      uint pid = 0;
      GetWindowThreadProcessId(h, out pid);
      if (pid != targetPid || !IsWindowVisible(h) || IsIconic(h)) return true;
      RECT r;
      if (GetWindowRect(h, out r)) {
        long w = Math.Max(0, r.Right - r.Left);
        long ht = Math.Max(0, r.Bottom - r.Top);
        long area = w * ht;
        if (area > bestArea && w >= 200 && ht >= 150) {
          bestArea = area;
          best = h;
        }
      }
      return true;
    }, IntPtr.Zero);
    return best;
  }

  public static IntPtr FindDeepestChildAt(IntPtr parent, int screenX, int screenY) {
    IntPtr best = parent;
    long bestArea = long.MaxValue;
    RECT pr;
    if (GetWindowRect(parent, out pr)) {
      bestArea = Math.Max(1, (long)(pr.Right - pr.Left) * (pr.Bottom - pr.Top));
    }
    EnumChildWindows(parent, (h, l) => {
      if (!IsWindowVisible(h)) return true;
      RECT r;
      if (GetWindowRect(h, out r)) {
        if (screenX >= r.Left && screenX < r.Right && screenY >= r.Top && screenY < r.Bottom) {
          long area = Math.Max(1, (long)(r.Right - r.Left) * (r.Bottom - r.Top));
          if (area <= bestArea) {
            bestArea = area;
            best = h;
          }
        }
      }
      return true;
    }, IntPtr.Zero);
    return best;
  }

  public static int[] FindStarIconCenter(Bitmap bmp) {
    int w = bmp.Width;
    int h = bmp.Height;
    int scanW = Math.Min(160, w);
    BitmapData bd = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
    try {
      int bytes = Math.Abs(bd.Stride) * h;
      byte[] buf = new byte[bytes];
      Marshal.Copy(bd.Scan0, buf, 0, bytes);

      // 1. Check top-left active tool slot (x=0..64, y=50..118 covers both 1-tab and multi-tab layouts)
      //    to know if Poller is already selected and capture (topCx, topCy) for the adjacent "MCP Sync" button.
      int topCount = 0;
      long topSumX = 0, topSumY = 0;
      int topYMin = Math.Min(50, h);
      int topYMax = Math.Min(118, h);
      int topXMax = Math.Min(64, w);
      for (int y = topYMin; y < topYMax; y++) {
        int rowOff = y * bd.Stride;
        for (int x = 0; x < topXMax; x++) {
          int i = rowOff + x * 4;
          int b = buf[i]; int g = buf[i + 1]; int r = buf[i + 2];
          if (g > 195 && b > 190 && r < 105) {
            topSumX += x; topSumY += y; topCount++;
          }
        }
      }
      int alreadyFlag = (topCount >= 6) ? 1 : 0;
      int topCx = (topCount >= 6) ? (int)(topSumX / topCount) : -1;
      int topCy = (topCount >= 6) ? (int)(topSumY / topCount) : -1;

      // 2. Locate the left Tools palette star button (y=120..h-40)
      int yMin = Math.Min(120, h);
      int yMax = Math.Max(yMin, h - 40);
      long sumX = 0, sumY = 0;
      int count = 0, minX = w, maxX = -1, minY = h, maxY = -1;
      for (int y = yMin; y < yMax; y++) {
        int rowOff = y * bd.Stride;
        for (int x = 0; x < scanW; x++) {
          int i = rowOff + x * 4;
          int b = buf[i];
          int g = buf[i + 1];
          int r = buf[i + 2];
          if (g > 195 && b > 190 && r < 105) {
            sumX += x;
            sumY += y;
            count++;
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
          }
        }
      }
      if (count >= 6 && (maxX - minX) <= 32 && (maxY - minY) <= 28) {
        return new int[] { (int)(sumX / count), (int)(sumY / count), count, alreadyFlag, topCx, topCy };
      }
      if (alreadyFlag == 1) {
        return new int[] { -1, -1, topCount, 1, topCx, topCy };
      }
      return null;
    } finally {
      bmp.UnlockBits(bd);
    }
  }
}
"@
$procs = Get-Process -Name "Moho" -ErrorAction SilentlyContinue
if (-not $procs) {
  Write-Output '{"activated":false,"reason":"Moho process not running"}'
  exit 0
}
$hwnd = [IntPtr]::Zero
foreach ($p in $procs) {
  $cand = [MohoPollerActivator]::FindPrimaryWindow([uint32]$p.Id)
  if ($cand -ne [IntPtr]::Zero) { $hwnd = $cand; break }
}
if ($hwnd -eq [IntPtr]::Zero) {
  Write-Output '{"activated":false,"reason":"Moho window is minimized or not visible"}'
  exit 0
}
$rect = New-Object MohoPollerActivator+RECT
[MohoPollerActivator]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
$w = [Math]::Max(1, $rect.Right - $rect.Left)
$h = [Math]::Max(1, $rect.Bottom - $rect.Top)
$bmp = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
[MohoPollerActivator]::PrintWindow($hwnd, $hdc, 2) | Out-Null
$g.ReleaseHdc($hdc)
$g.Dispose()
$hit = [MohoPollerActivator]::FindStarIconCenter($bmp)
$bmp.Dispose()
if ($null -eq $hit) {
  Write-Output '{"activated":false,"reason":"MohoStudioMCP Poller star icon not found in left toolbar (0..160px, y>=120)"}'
  exit 0
}
$titleSb = New-Object System.Text.StringBuilder 256
[MohoPollerActivator]::GetWindowText($hwnd, $titleSb, 256) | Out-Null
$wx = $hit[0]; $wy = $hit[1]; $cnt = $hit[2]; $alreadyActive = ($hit[3] -eq 1); $topCx = $hit[4]; $topCy = $hit[5]
$targetClass = ""
$pt = New-Object MohoPollerActivator+POINT
$sx = 0; $sy = 0
$action = "none"

function Send-BgClick([IntPtr]$rootHwnd, [int]$scrX, [int]$scrY) {
  $tgt = [MohoPollerActivator]::FindDeepestChildAt($rootHwnd, $scrX, $scrY)
  $p = New-Object MohoPollerActivator+POINT
  $p.X = $scrX; $p.Y = $scrY
  [MohoPollerActivator]::ScreenToClient($tgt, [ref]$p) | Out-Null
  $lp = [IntPtr]((($p.Y -band 0xFFFF) -shl 16) -bor ($p.X -band 0xFFFF))
  [MohoPollerActivator]::PostMessage($tgt, 0x0200, [IntPtr]::Zero, $lp) | Out-Null
  [MohoPollerActivator]::PostMessage($tgt, 0x0201, [IntPtr]1, $lp) | Out-Null
  Start-Sleep -Milliseconds 25
  [MohoPollerActivator]::PostMessage($tgt, 0x0202, [IntPtr]::Zero, $lp) | Out-Null
  $sb = New-Object System.Text.StringBuilder 128
  [MohoPollerActivator]::GetClassName($tgt, $sb, 128) | Out-Null
  return @($sb.ToString(), $p.X, $p.Y)
}

if (-not $alreadyActive -and $wx -ge 0 -and $wy -ge 0) {
  # 1. Click left-toolbar teal star to activate MohoStudioMCP Poller
  $sx = $rect.Left + $wx; $sy = $rect.Top + $wy
  $res = Send-BgClick $hwnd $sx $sy
  $targetClass = $res[0]; $pt.X = $res[1]; $pt.Y = $res[2]
  $action = "clicked_star_icon"
  Start-Sleep -Milliseconds 120
  # 2. Re-capture to find top-left star center and immediately click the adjacent "MCP Sync" button
  $bmp2 = New-Object System.Drawing.Bitmap($w, $h)
  $g2 = [System.Drawing.Graphics]::FromImage($bmp2)
  $hdc2 = $g2.GetHdc()
  [MohoPollerActivator]::PrintWindow($hwnd, $hdc2, 2) | Out-Null
  $g2.ReleaseHdc($hdc2)
  $g2.Dispose()
  $hit2 = [MohoPollerActivator]::FindStarIconCenter($bmp2)
  $bmp2.Dispose()
  if ($null -ne $hit2 -and $hit2[3] -eq 1 -and $hit2[4] -ge 0 -and $hit2[5] -ge 0) {
    $topCx = $hit2[4]; $topCy = $hit2[5]
    $sx = $rect.Left + $topCx + 52; $sy = $rect.Top + $topCy
    $res2 = Send-BgClick $hwnd $sx $sy
    $targetClass = $res2[0]; $pt.X = $res2[1]; $pt.Y = $res2[2]
    $action = "clicked_star_then_mcp_sync"
  }
} elseif ($alreadyActive -and $topCx -ge 0 -and $topCy -ge 0) {
  # Click the "MCP Sync" LM.GUI.Button right beside the top-left active tool icon (fires HandleMessage MSG_POLL)
  $sx = $rect.Left + $topCx + 52; $sy = $rect.Top + $topCy
  $res = Send-BgClick $hwnd $sx $sy
  $targetClass = $res[0]; $pt.X = $res[1]; $pt.Y = $res[2]
  $action = "clicked_mcp_sync_button"
}

$outObj = @{
  activated = $true
  alreadyActive = $alreadyActive
  action = $action
  starPixels = $cnt
  windowPoint = @{ x = $wx; y = $wy }
  topStarPoint = @{ x = $topCx; y = $topCy }
  screenPoint = @{ x = $sx; y = $sy }
  clientPoint = @{ x = $pt.X; y = $pt.Y }
  targetClass = $targetClass
  windowTitle = $titleSb.ToString()
}
Write-Output ($outObj | ConvertTo-Json -Compress)
`;
    const raw = await new Promise((resolve, reject) => {
      execFile(
        "powershell.exe",
        ["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", psScript],
        { timeout: 10_000, windowsHide: true },
        (err, stdout, stderr) => {
          if (err) {
            reject(new Error(`activatePoller failed: ${(stderr || err.message).trim()}`));
          } else {
            resolve(stdout.trim());
          }
        }
      );
    });
    try {
      return JSON.parse(raw);
    } catch {
      return { activated: false, raw };
    }
  }

  async cliRender(params = {}) {
    const projectPath = params.projectPath;
    if (!projectPath || typeof projectPath !== "string") {
      throw new Error("projectPath is required for document_cliRender");
    }
    if (!fs.existsSync(projectPath)) {
      throw new Error(`Project file does not exist: ${projectPath}`);
    }
    const mohoExe = process.env.MOHO_EXE_PATH || "C:\\Program Files\\Moho 14\\Moho.exe";
    if (!fs.existsSync(mohoExe)) {
      throw new Error(`Moho executable not found at ${mohoExe} (override with MOHO_EXE_PATH)`);
    }

    const outputDir = params.outputDir
      ? path.resolve(params.outputDir)
      : path.join(this.ipcDir, `cli_render_${process.pid}_${Date.now()}`);
    fs.mkdirSync(outputDir, { recursive: true });

    const beforeFiles = new Set(fs.readdirSync(outputDir));
    const logPath = path.join(outputDir, `_moho_cli_${process.pid}_${Date.now()}.log`);
    const format = String(params.format || "PNG");
    const args = ["-r", path.resolve(projectPath), "-v", "-f", format, "-log", logPath];

    if (params.outputFile) {
      args.push("-o", path.resolve(params.outputFile));
    } else {
      args.push("-outfolder", outputDir);
    }
    if (params.startFrame !== undefined) args.push("-start", String(Math.floor(Number(params.startFrame))));
    if (params.endFrame !== undefined) args.push("-end", String(Math.floor(Number(params.endFrame))));
    if (params.layerComp) args.push("-layercomp", String(params.layerComp));
    if (params.createFoldersForLayerComps === true) args.push("-createfoldersforlayercomps", "yes");
    if (params.addLayerCompSuffix === true) args.push("-addlayercompsuffix", "yes");
    if (params.halfSize === true) args.push("-halfsize", "yes");
    if (params.halfFps === true) args.push("-halffps", "yes");
    if (params.antiAliasing === false) args.push("-aa", "no");
    if (params.shapeEffects === false) args.push("-shapefx", "no");
    if (params.layerEffects === false) args.push("-layerfx", "no");
    if (params.extraSmooth === false) args.push("-extrasmooth", "no");
    if (params.premultiply === false) args.push("-premultiply", "no");
    if (params.multithread !== undefined) args.push("-multithread", params.multithread ? "yes" : "no");

    const timeoutMs = Math.max(30_000, Number(params.timeoutMs) || TIMEOUTS.renderRangeMs);
    const started = Date.now();
    await new Promise((resolve, reject) => {
      execFile(mohoExe, args, { timeout: timeoutMs, windowsHide: true }, (err, _stdout, stderr) => {
        if (err) {
          reject(new Error(`Moho CLI render failed: ${(stderr || err.message).trim()}`));
        } else {
          resolve();
        }
      });
    });

    const elapsedMs = Date.now() - started;
    let renderLog = "";
    if (fs.existsSync(logPath)) {
      renderLog = fs.readFileSync(logPath, "utf8");
      if (params.keepLog !== true) {
        try { fs.unlinkSync(logPath); } catch {}
      }
    }

    const createdFiles = [];
    if (params.outputFile && fs.existsSync(params.outputFile)) {
      createdFiles.push(path.resolve(params.outputFile));
    } else {
      for (const name of fs.readdirSync(outputDir).sort()) {
        if (!beforeFiles.has(name) && !name.startsWith("_moho_cli_")) {
          createdFiles.push(path.join(outputDir, name));
        }
      }
    }

    const firstPng = createdFiles.find((p) => p.toLowerCase().endsWith(".png")) || null;
    return {
      rendered: createdFiles.length > 0,
      format,
      projectPath: path.resolve(projectPath),
      outputDir,
      fileCount: createdFiles.length,
      files: createdFiles,
      outputPath: firstPng,
      elapsedMs,
      renderLog: renderLog.trim(),
    };
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
