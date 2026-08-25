Malicious File Scanning in Oracle APEX

This project shows how to add malicious file scanning to an Oracle APEX application.

When a user uploads a file in APEX, the file is sent to a Python FastAPI service. The service passes the file to a server-side shell script, which uses Microsoft Defender to scan the file.

How It Works
Oracle APEX
     ↓
PL/SQL Package
     ↓
Python FastAPI
     ↓
Shell Script
     ↓
Microsoft Defender
     ↓
Scan Result
     ↓
Oracle APEX
Main Components
Oracle APEX – User uploads the file.
PL/SQL Package – Sends the uploaded file to the scanning API.
Python FastAPI – Receives the file and handles authentication and scanning requests.
Shell Script – Executes the Microsoft Defender scan.
Microsoft Defender – Checks whether the file contains a detected threat.
Repository Structure
oracle-apex-malicious-file-scanning/
│
├── plsql/
│   ├── malicious_file_upload.pks
│   └── malicious_file_upload.pkb
│
├── python/
│   └── malicious_file_scanning_api.py
│
└── scripts/
    └── check_file.sh
Security

The project uses JWT authentication between the application and the scanning API. Uploaded files are temporarily stored for scanning and removed after the scanning process.

Credentials, internal URLs, server paths, and other project-specific information have been removed from the code published in this repository.

Purpose

This project demonstrates how Oracle APEX can be integrated with a server-side security service to scan uploaded files before they are processed by the application.

