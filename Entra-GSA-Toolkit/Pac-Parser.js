// place the path to your PAC file on Line 7 in JS notation 

const fs = require('fs');
const path = require('path');

// Read the content of the file
const content = fs.readFileSync('C:/Users/azmanjee/iboss_PAC.pac', 'utf8');

// Regular expression to match IP addresses
const ipRegex = /\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/g;

// Regular expression to match FQDNs
const fqdnRegex = /\b[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\b/g;

// Find all IP addresses
const ipAddresses = content.match(ipRegex) || [];

// Find all FQDNs
const fqdns = content.match(fqdnRegex) || [];

// Remove duplicates
const uniqueIPs = [...new Set(ipAddresses)];
const uniqueFQDNs = [...new Set(fqdns)];

// Determine if the return value is "DIRECT" or another value
const results = [];

uniqueIPs.forEach(ip => {
    const isDirect = content.includes(`isInNet(resolve_ip, "${ip}", "255.255.255.255")`) && content.includes('return "DIRECT";');
    results.push({ type: 'IP', value: ip, return: isDirect ? 'DIRECT' : 'OTHER' });
});

uniqueFQDNs.forEach(fqdn => {
    const isDirect = content.includes(`dnsDomainIs(host, "${fqdn}")`) && content.includes('return "DIRECT";');
    results.push({ type: 'FQDN', value: fqdn, return: isDirect ? 'DIRECT' : 'OTHER' });
});

// Convert results to CSV format
const csvContent = 'Type,Value,Return\n' + results.map(row => `${row.type},${row.value},${row.return}`).join('\n');

// Write the CSV content to a file
fs.writeFileSync('output.csv', csvContent);

console.log('CSV file has been created.');
