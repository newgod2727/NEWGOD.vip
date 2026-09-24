# GOLDAUTOCLICKER - native build. No WebView2, no install, no admin.
# Real window drawn by WinForms (GDI), runs on the PowerShell the school PC already allows.
$sig = '[DllImport("user32.dll")] public static extern void mouse_event(uint f,uint x,uint y,uint d,int e); [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int k);'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$api = Add-Type -MemberDefinition $sig -Name NgClick -Namespace Ng -PassThru
$gold=[Drawing.Color]::FromArgb(231,177,115); $bg=[Drawing.Color]::FromArgb(20,17,13); $card=[Drawing.Color]::FromArgb(30,26,20); $grey=[Drawing.Color]::FromArgb(140,140,140)
$f=New-Object Windows.Forms.Form
$f.Text='GOLDAUTOCLICKER'; $f.Size=New-Object Drawing.Size(320,262); $f.StartPosition='CenterScreen'
$f.BackColor=$bg; $f.ForeColor=$gold; $f.FormBorderStyle='FixedSingle'; $f.MaximizeBox=$false; $f.TopMost=$true
$title=New-Object Windows.Forms.Label; $title.Text='GOLDAUTOCLICKER'; $title.ForeColor=$gold; $title.Font=New-Object Drawing.Font('Segoe UI',15,[Drawing.FontStyle]::Bold); $title.AutoSize=$true; $title.Location=New-Object Drawing.Point(20,16); $f.Controls.Add($title)
$state=New-Object Windows.Forms.Label; $state.Text='OFF'; $state.ForeColor=$grey; $state.Font=New-Object Drawing.Font('Segoe UI',11,[Drawing.FontStyle]::Bold); $state.AutoSize=$true; $state.Location=New-Object Drawing.Point(24,52); $f.Controls.Add($state)
$cnt=New-Object Windows.Forms.Label; $cnt.Text='0 clicks'; $cnt.ForeColor=$gold; $cnt.AutoSize=$true; $cnt.Location=New-Object Drawing.Point(150,54); $f.Controls.Add($cnt)
$slab=New-Object Windows.Forms.Label; $slab.Text='clicks / second'; $slab.ForeColor=$gold; $slab.AutoSize=$true; $slab.Location=New-Object Drawing.Point(24,86); $f.Controls.Add($slab)
$cps=New-Object Windows.Forms.NumericUpDown; $cps.Minimum=1; $cps.Maximum=200; $cps.Value=10; $cps.Location=New-Object Drawing.Point(150,84); $cps.Width=70; $cps.BackColor=$card; $cps.ForeColor=$gold; $f.Controls.Add($cps)
$btn=New-Object Windows.Forms.Button; $btn.Text='START   (Ctrl+E)'; $btn.Size=New-Object Drawing.Size(260,60); $btn.Location=New-Object Drawing.Point(24,120); $btn.FlatStyle='Flat'; $btn.BackColor=$card; $btn.ForeColor=$gold; $btn.Font=New-Object Drawing.Font('Segoe UI',13,[Drawing.FontStyle]::Bold); $btn.FlatAppearance.BorderColor=$gold; $f.Controls.Add($btn)
$note=New-Object Windows.Forms.Label; $note.Text='Put the mouse where you want, then START or press Ctrl+E.'; $note.ForeColor=$grey; $note.AutoSize=$true; $note.Location=New-Object Drawing.Point(24,192); $f.Controls.Add($note)
$script:on=$false; $script:n=0; $script:next=0; $script:was=$false
$sw=[Diagnostics.Stopwatch]::StartNew()
function Set-State($v){
  $script:on=$v
  if($v){ $state.Text='ON'; $state.ForeColor=[Drawing.Color]::FromArgb(120,230,140); $btn.Text='STOP   (Ctrl+E)'; $script:next=$sw.ElapsedMilliseconds }
  else  { $state.Text='OFF'; $state.ForeColor=$grey; $btn.Text='START   (Ctrl+E)' }
}
$btn.Add_Click({ Set-State (-not $script:on) })
$t=New-Object Windows.Forms.Timer; $t.Interval=5
$t.Add_Tick({
  $down = (($api::GetAsyncKeyState(0x11) -band 0x8000) -ne 0) -and (($api::GetAsyncKeyState(0x45) -band 0x8000) -ne 0)
  if($down -and -not $script:was){ Set-State (-not $script:on) }
  $script:was=$down
  if($script:on){
    $iv=[int](1000/[double]$cps.Value)
    if($sw.ElapsedMilliseconds -ge $script:next){ $api::mouse_event(2,0,0,0,0); $api::mouse_event(4,0,0,0,0); $script:n++; $cnt.Text=("{0} clicks" -f $script:n); $script:next=$sw.ElapsedMilliseconds+$iv }
  }
})
$t.Start()
[Windows.Forms.Application]::Run($f)
