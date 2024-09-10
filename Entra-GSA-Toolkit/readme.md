# This folder contains various tools to help people migrate from iBoss (or other tools where they can export structured data) into Entra Global Secure Access.

1. Import-Allow/Deny Rules PS1 is for creating Network Filtering Rules for Entra Internet Access
2. Pac-Parser JS and PS1 are tools for converting PAC (Proxy Auto COnfiguration) files that contain destinations for Proxy Bypass into CSVs that are structured for the purposes of using them to import as Entra Internet Access Network Forwarding rules
3. Import-PACCSV is a powershell script that will take hte output of the pac parsers and make the networking forwarding rules

This is designed to SLAM this stuff into Entra quick and dirty. 

TOOD: Error handling, logic to manage FQDNs vs URLs in allow/deny lists, better PAC parsing that isnt just DIRECT commands


Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:


THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
