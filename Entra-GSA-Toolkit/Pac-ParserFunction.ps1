#Assumes your PAC file is nothing by bypasses (eg. heavy/exclusive DIRECT command usage outside of proxy command)
#this is to be used to parse the pac file into usable CSV data for import into Entra Private Access Forwarding Rules
#usage arsemy-PacFile -inputfile .\yourfile.pac -outputfile yourfileoutput.csv

Function Parsemy-PacFile {
[CmdletBinding()]
param([string]$inputFile,
      [string]$outputFile
)
# Define the path to the input and output files
# Regular expressions to match IP addresses with masks, IP addresses, FQDNs, and URLs including wildcard subdomains
$ipMaskRegex = 'isInNet\(\s*resolve_ip\s*,\s*"(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})"\s*,\s*"(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})"\s*\)'
$ipRegex = '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b'
$fqdnRegex = '\b(\*\.|[a-zA-Z0-9.-]+\.)[a-zA-Z]{2,}\b'
$urlRegex = 'https?://(\*\.|[a-zA-Z0-9.-]+\.)[a-zA-Z]{2,}(/[a-zA-Z0-9.-]*)*'

# Create an array to hold the results
$results = @()

# Read the file line by line
Get-Content -Path $inputFile | ForEach-Object {
    $line = $_.Trim()

    # Check for lines starting with isInNet
    if ($line -match $ipMaskRegex) {
        $ip = $matches[1]
        $mask = $matches[2]
        $results += [PSCustomObject]@{
            Type  = 'IP with Mask'
            Value = $ip
            Mask  = $mask
        }
    }

    # Check for lines starting with shExpMatch
    elseif ($line -match 'shExpMatch\(\s*resolve_ip\s*,\s*"(.*?)"\s*\)') {
        $hostname = $matches[1]
        if ($hostname -match $ipRegex) {
            $results += [PSCustomObject]@{
                Type  = 'IP'
                Value = $hostname
                Mask  = ''
            }
        } elseif ($hostname -match $fqdnRegex) {
            $results += [PSCustomObject]@{
                Type  = 'FQDN'
                Value = $hostname
                Mask  = ''
            }
        }
    }

    # Check for standalone IP addresses
    elseif ($line -match $ipRegex) {
        $ip = $matches[0]
        $results += [PSCustomObject]@{
            Type  = 'IP'
            Value = $ip
            Mask  = ''
        }
    }

    # Check for FQDNs
    elseif ($line -match $fqdnRegex) {
        $fqdn = $matches[0]
        $results += [PSCustomObject]@{
            Type  = 'FQDN'
            Value = $fqdn
            Mask  = ''
        }
    }

    # Check for URLs
    elseif ($line -match $urlRegex) {
        $url = $matches[0]
        $results += [PSCustomObject]@{
            Type  = 'URL'
            Value = $url
            Mask  = ''
        }
    }
}

# Remove duplicates
$uniqueResults = $results | Sort-Object -Property Value, Mask -Unique

# Export the results to a CSV file
$uniqueResults | Export-Csv -Path $outputFile -NoTypeInformation

Write-Output "CSV file has been created at $outputFile"
}
