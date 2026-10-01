<#
codex_run.ps1 - codex_run.sh の PowerShell 版 (codex-discuss-poc 共用)

なぜ要るか :
  codex_run.sh は bash と coreutils の timeout に依存する。
  bash が使えない環境ではこの PowerShell 版を使う (bash 環境では .sh を使う)。

不変条件 (.sh から引き継ぐ - ここが最重要):
  OPENAI_API_KEY と CODEX_API_KEY を子プロセスから必ず除去して起動する。
  どちらかが残ると、サブスクリプション認証ではなく API キー認証 (従量課金) に
  意図せず切り替わる。API キーで使う場合はこの除去処理を外す。

PowerShell 固有の注意:
  - このファイルは UTF-8 BOM 付きで保存すること。
    PowerShell 5.1 は BOM 無し .ps1 を cp932 として読み、日本語コメントで構文が壊れる。
  - 複数の codex が入っている場合は CODEX_BIN 環境変数で実行ファイルを明示できる。
    古い版は新しいモデル名を拒否することがある。
    既定の探索順: CODEX_BIN -> npm global -> PATH。
  - PowerShell に stdin リダイレクト '<' は無い。-RedirectStandardInput で渡す。
  - Start-Process -PassThru の直後は ExitCode が null になることがある。
    引数なし WaitForExit を呼んでから読む。

usage:
  .\codex_run.ps1 -Mode read-only -WorkDir <workspace> `
                  -PromptFile prompt.md -Out R1.md [-Log R1.log] [-TimeoutSec 1200]

env:
  CODEX_BIN     codex 実行ファイルの明示指定
  CODEX_MODEL   使用モデル (必須。環境変数で指定)
  CODEX_EFFORT  既定 medium
#>
param(
  [Parameter(Mandatory = $true)][ValidateSet("read-only", "workspace-write")][string]$Mode,
  [Parameter(Mandatory = $true)][string]$WorkDir,
  [Parameter(Mandatory = $true)][string]$PromptFile,
  [Parameter(Mandatory = $true)][string]$Out,
  [string]$Log,
  [int]$TimeoutSec = 1200,
  [string]$CodexPath,
  [string]$Model = $env:CODEX_MODEL,
  [string]$Effort = $(if ($env:CODEX_EFFORT) { $env:CODEX_EFFORT } else { "medium" })
)

$ErrorActionPreference = "Stop"
if (-not $Model) { throw "set CODEX_MODEL" }
if (-not $Log) { $Log = "$Out.log" }

foreach ($p in @($Out, $Log)) {
  $d = Split-Path $p -Parent
  if ($d -and -not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
}
if (-not (Test-Path $PromptFile)) { throw "prompt not found: $PromptFile" }

# --- codex の実体を決める (新しい方を優先) ---
function Resolve-Codex {
  if ($env:CODEX_BIN -and (Test-Path $env:CODEX_BIN)) { return $env:CODEX_BIN }
  try {
    $root = (& npm root -g 2>$null)
    if ($root) {
      $cand = Join-Path (Split-Path ($root.Trim()) -Parent) "codex.cmd"
      if (Test-Path $cand) { return $cand }
    }
  }
  catch {}
  $onPath = (Get-Command codex -ErrorAction SilentlyContinue).Source
  if ($onPath) { return $onPath }
  return $null
}
if (-not $CodexPath) { $CodexPath = Resolve-Codex }
if (-not $CodexPath) { throw "codex not found (set CODEX_BIN)" }

# --- API キー認証への意図しない切り替え防止 (.sh の env -u に相当) ---
$saved = @{}
foreach ($k in @("OPENAI_API_KEY", "CODEX_API_KEY")) {
  $v = [Environment]::GetEnvironmentVariable($k)
  if ($v) { $saved[$k] = $v }
  [Environment]::SetEnvironmentVariable($k, $null)
}

$codexArgs = @(
  "exec", "-",
  "--skip-git-repo-check",
  "--sandbox", $Mode,
  "-C", $WorkDir,
  "-m", $Model,
  "-c", "model_reasoning_effort=$Effort",
  "-o", $Out
)

$rc = $null
try {
  $proc = Start-Process -FilePath $CodexPath -ArgumentList $codexArgs -NoNewWindow -PassThru `
    -RedirectStandardInput $PromptFile `
    -RedirectStandardOutput $Log `
    -RedirectStandardError "$Log.err"

  if ($proc.WaitForExit($TimeoutSec * 1000)) {
    $proc.WaitForExit()
    $rc = $proc.ExitCode
  }
  else {
    try { $proc.Kill() } catch {}
    Write-Output "TIMEOUT after ${TimeoutSec}s"
    $rc = 124
  }
}
finally {
  foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
}

if ($null -eq $rc) { $rc = 1 }

if (Test-Path "$Log.err") {
  $e = Get-Content "$Log.err" -Raw
  if ($e -and $e.Trim()) { Add-Content $Log "`n--- stderr ---`n$e" }
  Remove-Item "$Log.err" -Force
}

# .sh と同じく「rc=0 でも空応答なら失敗扱い」
$bytes = if (Test-Path $Out) { (Get-Item $Out).Length } else { 0 }
if ($rc -eq 0 -and $bytes -eq 0) {
  Write-Output "codex returned rc=0 but produced no output"
  $rc = 1
}

# 注意: codex 自身が rc!=0 でも本文を出していることがある。
# 呼び手は rc だけでなく Out のバイト数も見て判断すること。
Write-Output "rc=$rc  model=$Model  codex=$CodexPath  out=$Out ($bytes bytes)"
exit $rc
