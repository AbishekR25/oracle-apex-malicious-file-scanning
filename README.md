## Malicious File Scanning in Oracle APEX

Scan Oracle APEX file uploads for malware before they are processed by the application.

When a user uploads a file in APEX, the file is sent to a Python FastAPI service. The service passes the file to a server-side shell script, which uses Microsoft Defender to scan the file.

## How It Works
A file is uploaded through the Oracle APEX application.

The PL/SQL package sends the file to the Python FastAPI service.

The FastAPI service receives the file and passes it to the shell script.

The shell script runs the Microsoft Defender scan.

The scan checks whether the file contains a threat.

The scan result is sent back to the FastAPI service.

The result is returned to the Oracle APEX application.

## Main Components
Oracle APEX – User uploads the file.

PL/SQL Package – Sends the uploaded file to the scanning API.

Python FastAPI – Receives the file and handles authentication and scanning requests.

Shell Script – Executes the Microsoft Defender scan.

Microsoft Defender – Checks whether the file contains a detected threat

## Purpose

This project demonstrates how Oracle APEX can be integrated with a server-side security service to scan uploaded files before they are processed by the application.

