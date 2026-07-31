$global:ClaudeAdded = $false
$global:CodexAdded = $false
$global:HermesAdded = $false

function global:claude {
    $argv = @($args)
    if ($argv.Count -ge 3 -and $argv[0] -eq "mcp" -and $argv[1] -eq "get") {
        if ($global:ClaudeAdded) {
            "obsidian"
            $global:LASTEXITCODE = 0
        } else {
            $global:LASTEXITCODE = 1
        }
        return
    }
    if ($argv.Count -ge 6 -and $argv[0] -eq "mcp" -and $argv[1] -eq "add-json") {
        $json = $argv[-1] | ConvertFrom-Json
        if ($json.type -ne "http" -or
            $json.url -ne $env:OBSIDIAN_MCP_URL -or
            $json.headers.Authorization -ne 'Bearer ${SETUP_AI_OBSIDIAN_API_KEY}') {
            throw "invalid Claude MCP configuration"
        }
        $global:ClaudeAdded = $true
        $global:LASTEXITCODE = 0
        return
    }
    if ($argv.Count -ge 2 -and $argv[1] -eq "remove") {
        $global:ClaudeAdded = $false
        $global:LASTEXITCODE = 0
        return
    }
    throw "unexpected Claude arguments: $argv"
}

function global:codex {
    $argv = @($args)
    if ($argv.Count -ge 3 -and $argv[0] -eq "mcp" -and $argv[1] -eq "get") {
        if ($global:CodexAdded) {
            "obsidian"
            $global:LASTEXITCODE = 0
        } else {
            $global:LASTEXITCODE = 1
        }
        return
    }
    if ($argv.Count -ge 7 -and $argv[0] -eq "mcp" -and $argv[1] -eq "add") {
        if ($argv -notcontains "--bearer-token-env-var" -or
            $argv -notcontains "SETUP_AI_OBSIDIAN_API_KEY" -or
            $argv -notcontains $env:OBSIDIAN_MCP_URL) {
            throw "invalid Codex MCP configuration"
        }
        $global:CodexAdded = $true
        $global:LASTEXITCODE = 0
        return
    }
    if ($argv.Count -ge 2 -and $argv[1] -eq "remove") {
        $global:CodexAdded = $false
        $global:LASTEXITCODE = 0
        return
    }
    throw "unexpected Codex arguments: $argv"
}

function global:hermes {
    $argv = @($args)
    if ($argv.Count -ge 2 -and $argv[0] -eq "mcp" -and $argv[1] -eq "list") {
        if ($global:HermesAdded) {
            "  obsidian   HTTP   enabled"
        }
        $global:LASTEXITCODE = 0
        return
    }
    if ($argv.Count -ge 7 -and $argv[0] -eq "mcp" -and $argv[1] -eq "add") {
        if ($env:MCP_OBSIDIAN_API_KEY -ne $env:SETUP_AI_OBSIDIAN_API_KEY -or
            $argv -notcontains "--auth" -or
            $argv -notcontains "header") {
            throw "invalid Hermes MCP configuration"
        }
        $global:HermesAdded = $true
        $global:LASTEXITCODE = 0
        return
    }
    if ($argv.Count -ge 2 -and $argv[1] -eq "remove") {
        $global:HermesAdded = $false
        $global:LASTEXITCODE = 0
        return
    }
    throw "unexpected Hermes arguments: $argv"
}

Write-Host "Windows Obsidian helper harness: starting"
. /workspace/windows/setup-obsidian-mcp.ps1 -Force
