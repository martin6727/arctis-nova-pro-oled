# Shows the current media track (e.g. YouTube Music in a browser) on the GameDAC OLED via SteelSeries GameSense.
# Renders a 128x64 bitmap: title, artist, elapsed/total time and a progress bar.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using System.Text;

public static class OledRenderer {
    const int W = 128;
    static readonly Font TitleFont  = new Font("Segoe UI", 10, FontStyle.Bold, GraphicsUnit.Pixel);
    static readonly Font ArtistFont = new Font("Segoe UI", 9, FontStyle.Regular, GraphicsUnit.Pixel);
    static readonly Font TimeFont   = new Font("Segoe UI", 8, FontStyle.Regular, GraphicsUnit.Pixel);

    // On short screens the fox sits small in the top-right corner and text stops short of it;
    // on 64px screens it sits big in the empty gap above the progress bar.
    static int TextW = W;

    // Sitting fox facing left, '#' = lit pixel, 15x13. Tail is drawn separately so it can swish.
    static readonly string[] FoxBody = {
        "..#...#........",
        "..##.##........",
        "..#####........",
        "..#.###........",
        "#######........",
        "...####........",
        "...####........",
        "..######.......",
        "..#######......",
        "..########.....",
        "..########.....",
        "..#########....",
        "..##.##.###....",
    };
    // Bushy tail tapering to a point: raised, and swished low
    static readonly string[][] FoxTails = {
        new[] {
            "...............",
            "...............",
            "...............",
            "..............#",
            ".............##",
            "............###",
            "...........####",
            "..........####.",
            "..........####.",
            "..........###..",
            "..........##...",
            "..........#....",
            "...............",
        },
        new[] {
            "...............",
            "...............",
            "...............",
            "...............",
            "...............",
            "...............",
            "...............",
            "...............",
            "..............#",
            "............###",
            "..........#####",
            "..........####.",
            "...........##..",
        },
    };

    static void Plot(Graphics g, string[] sprite, int x, int y, int s) {
        for (int r = 0; r < sprite.Length; r++)
            for (int c = 0; c < sprite[r].Length; c++)
                if (sprite[r][c] == '#') g.FillRectangle(Brushes.White, x + c * s, y + r * s, s, s);
    }

    // Draws the fox with its top-left at (x, y), each sprite pixel s x s screen pixels.
    static void DrawFox(Graphics g, int x, int y, int s, bool asleep, int tick) {
        Plot(g, FoxBody, x, y, s);
        if (asleep) g.FillRectangle(Brushes.White, x + 3 * s, y + 3 * s, s, s); // closed eye
        // Swish the tail every second while playing
        Plot(g, FoxTails[asleep ? 0 : (tick / 4) % 2], x, y, s);
        if (asleep) {
            // little "z" floating above the head, bobbing
            int zx = x + 8 * s, zy = y + ((tick / 4) % 2) * s;
            g.FillRectangle(Brushes.White, zx, zy, 4 * s, s);
            g.FillRectangle(Brushes.White, zx + 2 * s, zy + s, s, s);
            g.FillRectangle(Brushes.White, zx + s, zy + 2 * s, s, s);
            g.FillRectangle(Brushes.White, zx, zy + 3 * s, 4 * s, s);
        }
    }

    // Draws text at y within TextW; if wider, scrolls it like a marquee based on tick.
    static void DrawLine(Graphics g, string text, Font font, int y, int tick) {
        if (string.IsNullOrEmpty(text)) return;
        int width = (int)Math.Ceiling(g.MeasureString(text, font, 10000, StringFormat.GenericTypographic).Width);
        g.SetClip(new Rectangle(0, y, TextW, font.Height + 2));
        if (width <= TextW) {
            g.DrawString(text, font, Brushes.White, 0, y, StringFormat.GenericTypographic);
        } else {
            const int gap = 30, pause = 8;
            int cycle = width + gap;
            int t = tick % (cycle + pause);
            int x = t < pause ? 0 : -(t - pause);
            g.DrawString(text, font, Brushes.White, x, y, StringFormat.GenericTypographic);
            g.DrawString(text, font, Brushes.White, x + cycle, y, StringFormat.GenericTypographic);
        }
        g.ResetClip();
    }

    static string Fmt(double s) {
        if (s < 0) s = 0;
        int t = (int)s;
        return t >= 3600 ? string.Format("{0}:{1:00}:{2:00}", t / 3600, t / 60 % 60, t % 60)
                         : string.Format("{0}:{1:00}", t / 60, t % 60);
    }

    // Returns the frame as a JSON array of bytes (1 bit per pixel, row-major, MSB first).
    // H is the screen height; GameSense OLEDs are 128 wide and 36-64 tall.
    public static string Render(int H, string title, string artist, double pos, double dur, bool paused, int tick) {
        using (var bmp = new Bitmap(W, H, PixelFormat.Format32bppArgb))
        using (var g = Graphics.FromImage(bmp)) {
            g.Clear(Color.Black);
            g.TextRenderingHint = TextRenderingHint.SingleBitPerPixelGridFit;

            bool bigCat = H >= 64;
            TextW = bigCat ? W : 110;
            DrawLine(g, title, TitleFont, 0, tick);
            DrawLine(g, artist, ArtistFont, 13, tick);
            // Big fox: 30x26, sitting just above the progress bar on the right
            if (bigCat) DrawFox(g, W - 30, H - 6 - 26, 2, paused, tick);
            else DrawFox(g, 113, 1, 1, paused, tick);

            // Short screens only have room for the bar, not the time labels
            bool showTimes = H >= 48;
            int barY = H - 6, timeY = H - 17;
            if (dur > 0) {
                if (showTimes) {
                    string left = (paused ? "II " : "") + Fmt(pos), right = Fmt(dur);
                    g.DrawString(left, TimeFont, Brushes.White, 0, timeY, StringFormat.GenericTypographic);
                    float rw = g.MeasureString(right, TimeFont, 1000, StringFormat.GenericTypographic).Width;
                    // With the big cat in the bottom-right, put the total time beside the elapsed time
                    if (bigCat) {
                        float lw = g.MeasureString(left, TimeFont, 1000, StringFormat.GenericTypographic).Width;
                        g.DrawString("/ " + right, TimeFont, Brushes.White, lw + 3, timeY, StringFormat.GenericTypographic);
                    } else {
                        g.DrawString(right, TimeFont, Brushes.White, W - rw - 1, timeY, StringFormat.GenericTypographic);
                    }
                }

                // Progress bar: outline with filled portion
                g.DrawRectangle(Pens.White, 0, barY, W - 1, 5);
                int fill = (int)Math.Round((W - 4) * Math.Max(0, Math.Min(1, pos / dur)));
                if (fill > 0) g.FillRectangle(Brushes.White, 2, barY + 2, fill, 2);
            } else if (paused && showTimes) {
                g.DrawString("II paused", TimeFont, Brushes.White, 0, timeY, StringFormat.GenericTypographic);
            }

            var data = bmp.LockBits(new Rectangle(0, 0, W, H), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            var px = new int[W * H];
            Marshal.Copy(data.Scan0, px, 0, px.Length);
            bmp.UnlockBits(data);

            var sb = new StringBuilder("[");
            for (int i = 0; i < px.Length; i += 8) {
                int b = 0;
                for (int k = 0; k < 8; k++)
                    if ((px[i + k] & 0xFF) > 127) b |= 0x80 >> k;
                if (i > 0) sb.Append(',');
                sb.Append(b);
            }
            return sb.Append(']').ToString();
        }
    }
}
'@

$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($op, [Type]$type) {
    $t = $asTask.MakeGenericMethod($type).Invoke($null, @($op))
    $t.Wait() | Out-Null
    $t.Result
}

function Post($path, [string]$json) {
    Invoke-RestMethod -Uri "$script:base/$path" -Method Post -ContentType 'application/json' -Body $json -TimeoutSec 3 | Out-Null
}

# Not sure which OLED size the GameDAC reports, so bind and render every known one
$heights = 36, 40, 48, 52, 64
$handlers = $heights | ForEach-Object {
    $blank = '[' + ((1..(16 * $_) | ForEach-Object { 0 }) -join ',') + ']'
    '{"device-type":"screened-128x' + $_ + '","zone":"one","mode":"screen","datas":[{"has-text":false,"length-millis":1500,"image-data":' + $blank + '}]}'
}
# GG's port lives in coreProps.json and can change when GG restarts, so (re)connect on demand
function Connect-GG {
    $props = Get-Content "$env:ProgramData\SteelSeries\SteelSeries Engine 3\coreProps.json" -Raw | ConvertFrom-Json
    $script:base = "http://$($props.address)"
    Post 'game_metadata' '{"game":"YTM_OLED","game_display_name":"YouTube Music OLED","developer":"local"}'
    Post 'bind_game_event' ('{"game":"YTM_OLED","event":"TRACK","min_value":0,"max_value":1,"value_optional":true,"handlers":[' + ($handlers -join ',') + ']}')
}
# At Windows startup GG may not be up yet
while ($true) {
    try { Connect-GG; break } catch { Start-Sleep -Seconds 5 }
}

$mgr = Await ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])
$propsType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties]
Write-Host 'Running. Ctrl+C to stop.'
$last = ''
$tick = 0
$title = ''; $artist = ''
while ($true) {
  try {
    # Prefer a playing session, fall back to a paused one
    $sessions = @($mgr.GetSessions())
    $s = $sessions | Where-Object { $_.GetPlaybackInfo().PlaybackStatus -eq 'Playing' } | Select-Object -First 1
    if (-not $s) { $s = $sessions | Where-Object { $_.GetPlaybackInfo().PlaybackStatus -eq 'Paused' } | Select-Object -First 1 }

    if ($s) {
        # Re-read metadata about once a second; it rarely changes
        if ($tick % 4 -eq 0 -or -not $title) {
            $m = Await ($s.TryGetMediaPropertiesAsync()) $propsType
            $title = $m.Title; $artist = $m.Artist
        }
        $paused = $s.GetPlaybackInfo().PlaybackStatus -ne 'Playing'
        $tl = $s.GetTimelineProperties()
        $dur = ($tl.EndTime - $tl.StartTime).TotalSeconds
        $pos = $tl.Position.TotalSeconds
        # The browser only reports position occasionally, so extrapolate while playing
        if (-not $paused -and $tl.LastUpdatedTime.Year -gt 2000) {
            $pos += ([DateTimeOffset]::Now - $tl.LastUpdatedTime).TotalSeconds
        }
        if ($dur -gt 0 -and $pos -gt $dur) { $pos = $dur }

        if ($title) {
            $frames = $heights | ForEach-Object { '"image-data-128x' + $_ + '":' + [OledRenderer]::Render($_, $title, $artist, $pos, $dur, $paused, $tick) }
            Post 'game_event' ('{"game":"YTM_OLED","event":"TRACK","data":{"value":1,"frame":{' + ($frames -join ',') + '}}}')
            $key = "$title|$artist"
            if ($key -ne $last) { Write-Host ("Now playing: $title - $artist  [{0:mm\:ss}]" -f [TimeSpan]::FromSeconds([Math]::Max(0, $dur))) }
            $last = $key
        }
    } else {
        $title = ''; $last = ''
    }
  } catch {
    # Sessions come and go between songs/tabs; GG may restart. Log and keep going.
    Write-Host "Warning: $($_.Exception.Message)"
    Start-Sleep -Seconds 1
    try { Connect-GG } catch { }
  }
    $tick++
    Start-Sleep -Milliseconds 250
}
