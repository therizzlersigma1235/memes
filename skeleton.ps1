Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ==========================================
# 1. SETUP & SETTINGS
# ==========================================
# location where the skeleton gif will be stored/downloaded
$gifUrl = 'https://github.com/therizzlersigma1235/memes/raw/refs/heads/main/skeleton.gif'
$gifPath = Join-Path $env:TEMP 'skeleton.gif'

# attempt to download the GIF if it isn't already in %TEMP%
if (-Not (Test-Path $gifPath)) {
    try {
        Invoke-WebRequest -Uri $gifUrl -OutFile $gifPath -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-Host "Failed to download GIF from ${gifUrl}`n$_" -ForegroundColor Red
        Pause
        return
    }
}


# SPEED SETTING: 2.0 = Double speed, 3.0 = Triple speed, 0.5 = Half speed
# (higher values speed up until the 10ms floor; values above what the GIF already uses
# will have no further effect because a 0ms delay isn\'t allowed)
$speedMultiplier = 3.0 

# OVERRIDE TIMER: Change 0 to exact milliseconds if the window closes too early/late (e.g. 5000)
$forceDuration = 3350

if (-Not (Test-Path $gifPath)) {
    Write-Host "Could not find GIF at $gifPath. Make sure it is named exactly 'skeleton.gif' and in the same folder!" -ForegroundColor Red
    Pause
    return
}

# 2. Add C# code: Click-through magic AND a custom image box to STOP the green trace
$csharp = @"
using System;
using System.Windows.Forms;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;

public class Win32 {
    public const int GWL_EXSTYLE = -20;
    public const int WS_EX_LAYERED = 0x80000;
    public const int WS_EX_TRANSPARENT = 0x20;

    [DllImport("user32.dll")]
    public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll")]
    public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
}

public class CrispPictureBox : PictureBox {
    protected override void OnPaint(PaintEventArgs pe) {
        pe.Graphics.InterpolationMode = InterpolationMode.NearestNeighbor;
        pe.Graphics.PixelOffsetMode = PixelOffsetMode.Half;
        base.OnPaint(pe);
    }
}
"@
Add-Type -TypeDefinition $csharp -ReferencedAssemblies "System.Windows.Forms", "System.Drawing" -ErrorAction SilentlyContinue

# 3. Load the GIF and HACK the frame speed in memory
$img = [System.Drawing.Image]::FromFile($gifPath)
$durationMs = 3000 # Default fallback

try {
    $fd = New-Object System.Drawing.Imaging.FrameDimension($img.FrameDimensionsList[0])
    $frames = $img.GetFrameCount($fd)
    $delayProperty = $img.GetPropertyItem(0x5100) # 0x5100 is the GIF Frame Delay data
    $calcDuration = 0
    
    for ($i = 0; $i -lt $frames; $i++) {
        # Get original frame delay (stored in 1/100ths of a second).
        $delay = [System.BitConverter]::ToInt32($delayProperty.Value, $i * 4)
        
        # Apply the speed multiplier (divide the delay).  Be aware that delays
        # are integers, and the minimum allowed value is 1 (10ms), so any
        # multiplier that would calculate a value below 1 will end up at 1.
        # That means once a GIF is already playing at its fastest frame rate
        # there is no way to make it perceptibly faster.
        $newDelay = [int][math]::Round($delay / $speedMultiplier)
        if ($newDelay -lt 1) { $newDelay = 1 }
        
        # Write the new fast delay back into the GIF's memory bytes
        $newBytes = [System.BitConverter]::GetBytes($newDelay)
        [System.Array]::Copy($newBytes, 0, $delayProperty.Value, $i * 4, 4)
        
        # Tally up the new total duration
        $calcDuration += ($newDelay * 10)
    }
    
    # Save the modified speed back into the image object and then reload the
    # stream.  Some versions of System.Drawing cache the original timing until
    # the image has been saved and reopened, so forcing a round-trip ensures
    # the new delays are honoured.
    $img.SetPropertyItem($delayProperty)
    try {
        $mem = New-Object System.IO.MemoryStream
        $img.Save($mem, [System.Drawing.Imaging.ImageFormat]::Gif)
        $mem.Position = 0
        $img.Dispose()
        $img = [System.Drawing.Image]::FromStream($mem)
    } catch {
        # ignore any reload errors; the image will probably still animate.
    }

    if ($calcDuration -gt 0) { 
        # Multiplied by 1.35 to account for Windows rendering lag we discovered earlier
        $durationMs = [math]::Round($calcDuration * 1.35) 
    }
} catch {}

# Apply manual timer override if you set one on line 10
if ($forceDuration -gt 0) { $durationMs = $forceDuration }

# debug output to help verify that the multiplier had an effect
Write-Host "Speed multiplier: $speedMultiplier -> duration $durationMs ms" -ForegroundColor Cyan

# 4. Create the invisible window
$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = 'None'
$form.TopMost = $true
$form.ShowInTaskbar = $false

# FIT TO SCREEN BUT LEAVE TASKBAR VISIBLE
$form.StartPosition = 'Manual'
$form.Bounds = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea

# We use Magenta as the window key
$form.BackColor = [System.Drawing.Color]::Magenta
$form.TransparencyKey = [System.Drawing.Color]::Magenta

# 5. Create the GIF player
$pb = New-Object CrispPictureBox
$pb.Image = $img
$pb.BackColor = [System.Drawing.Color]::Transparent 
$pb.Dock = 'Fill'

# SET TO ZOOM: Fits to screen but keeps pixels much cleaner
$pb.SizeMode = 'Zoom' 
$form.Controls.Add($pb)

# 6. Apply the click-through magic
$form.Add_Load({
    $exStyle = [Win32]::GetWindowLong($form.Handle, [Win32]::GWL_EXSTYLE)
    [Win32]::SetWindowLong($form.Handle, [Win32]::GWL_EXSTYLE, $exStyle -bor [Win32]::WS_EX_LAYERED -bor [Win32]::WS_EX_TRANSPARENT)
})

# 7. Create a timer to close the overlay when the GIF finishes
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $durationMs
$timer.Add_Tick({
    $timer.Stop()
    $form.Close()
})
$timer.Start()

# 8. Run the overlay!
$form.ShowDialog() | Out-Null

# Clean up memory
$img.Dispose()

$form.Dispose()


