// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package handlers

const verificationPageHTML = `
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{{.Title}}</title>
    <style>
        body { 
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; 
            background-color: #f4f4f5; 
            display: flex; 
            justify-content: center; 
            align-items: center; 
            height: 100vh; 
            margin: 0; 
        }
        .container { 
            background: white; 
            padding: 40px; 
            border-radius: 12px; 
            box-shadow: 0 4px 6px rgba(0,0,0,0.1); 
            max-width: 400px; 
            width: 90%;
            text-align: center; 
        }
        .icon { font-size: 48px; margin-bottom: 16px; }
        .success { color: #10b981; }
        .error { color: #ef4444; }
        h1 { margin: 0 0 16px 0; font-size: 24px; color: #18181b; }
        p { color: #52525b; line-height: 1.5; margin-bottom: 24px; }
        .button { 
            background-color: #18181b; 
            color: white; 
            padding: 12px 24px; 
            border-radius: 8px; 
            text-decoration: none; 
            font-weight: 600; 
            display: inline-block; 
            transition: opacity 0.2s;
        }
        .button:hover { opacity: 0.9; }
    </style>
</head>
<body>
    <div class="container">
        <div class="icon">{{.Icon}}</div>
        <h1>{{.Title}}</h1>
        <p>{{.Message}}</p>
        {{if .RedirectURL}}
        <a href="{{.RedirectURL}}" class="button">Open Sojorn</a>
        {{end}}
    </div>
</body>
</html>
`
