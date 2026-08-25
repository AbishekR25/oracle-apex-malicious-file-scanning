from fastapi import FastAPI, UploadFile, File, HTTPException, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import subprocess
import tempfile
import os
import jwt
import datetime

app = FastAPI(title="Malicious File Scanning API")

# ------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------

SECRET_KEY = os.getenv("JWT_SECRET_KEY", "<JWT_SECRET_KEY>")

ACCESS_EXP_MINUTES = 30
REFRESH_EXP_DAYS = 1

SCAN_SCRIPT_PATH = os.getenv(
    "SCAN_SCRIPT_PATH",
    "/path/to/check_file.sh"
)

# ------------------------------------------------------------------
# Demo user store
# ------------------------------------------------------------------
# For demonstration purposes only.
# Production applications should use a secure database and
# password hashing instead of storing plaintext passwords.

users_db = {
    "demo_user": {
        "password": "<DEMO_PASSWORD>",
        "refresh_token": None
    }
}

# ------------------------------------------------------------------
# JWT Utilities
# ------------------------------------------------------------------

def create_token(username: str, expires_delta, token_type: str):
    payload = {
        "user": username,
        "type": token_type,
        "exp": datetime.datetime.now(datetime.timezone.utc) + expires_delta
    }

    return jwt.encode(
        payload,
        SECRET_KEY,
        algorithm="HS256"
    )


def verify_token(token: str, expected_type: str):
    try:
        payload = jwt.decode(
            token,
            SECRET_KEY,
            algorithms=["HS256"]
        )

        if payload.get("type") != expected_type:
            return None

        return payload["user"]

    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=401,
            detail="Token expired"
        )

    except jwt.InvalidTokenError:
        raise HTTPException(
            status_code=401,
            detail="Invalid token"
        )


# ------------------------------------------------------------------
# Authentication
# ------------------------------------------------------------------

auth_scheme = HTTPBearer()


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(auth_scheme)
):
    return verify_token(credentials.credentials, "access")


# ------------------------------------------------------------------
# Routes
# ------------------------------------------------------------------

@app.get("/")
def home():
    return {
        "message": "Welcome to the File Scanning API"
    }


@app.post("/login")
async def login(data: dict):

    username = data.get("username")
    password = data.get("password")

    if not username or not password:
        raise HTTPException(
            status_code=401,
            detail="Invalid credentials"
        )

    if username not in users_db:
        raise HTTPException(
            status_code=401,
            detail="Invalid credentials"
        )

    if users_db[username]["password"] != password:
        raise HTTPException(
            status_code=401,
            detail="Invalid credentials"
        )

    access_token = create_token(
        username,
        datetime.timedelta(minutes=ACCESS_EXP_MINUTES),
        "access"
    )

    refresh_token = create_token(
        username,
        datetime.timedelta(days=REFRESH_EXP_DAYS),
        "refresh"
    )

    users_db[username]["refresh_token"] = refresh_token

    return {
        "access_token": access_token,
        "refresh_token": refresh_token
    }


@app.post("/refresh")
async def refresh(data: dict):

    username = data.get("username")
    refresh_token = data.get("refresh_token")

    if (
        username not in users_db
        or users_db[username]["refresh_token"] != refresh_token
    ):
        raise HTTPException(
            status_code=401,
            detail="Invalid refresh token"
        )

    verify_token(refresh_token, "refresh")

    new_access_token = create_token(
        username,
        datetime.timedelta(minutes=ACCESS_EXP_MINUTES),
        "access"
    )

    new_refresh_token = create_token(
        username,
        datetime.timedelta(days=REFRESH_EXP_DAYS),
        "refresh"
    )

    users_db[username]["refresh_token"] = new_refresh_token

    return {
        "access_token": new_access_token,
        "refresh_token": new_refresh_token
    }


@app.post("/scan")
async def scan_file(
    file: UploadFile = File(...),
    user: str = Depends(get_current_user)
):

    file_path = None

    try:
        # Save uploaded file temporarily
        with tempfile.NamedTemporaryFile(delete=False) as temp_file:
            temp_file.write(await file.read())
            file_path = temp_file.name

        # Execute the server-side file scanning script
        result = subprocess.run(
            [SCAN_SCRIPT_PATH, file_path],
            capture_output=True,
            text=True
        )

        return {
            "user": user,
            "result": result.stdout.strip(),
            "status": (
                "success"
                if result.returncode == 0
                else "infected"
            )
        }

    finally:

        # Remove temporary file after scanning
        if file_path and os.path.exists(file_path):
            os.remove(file_path)
