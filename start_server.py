#!/usr/bin/env python3
"""
Start script for FastAPI server
"""
import os
import sys
from pathlib import Path

# Change to the correct directory
script_dir = Path(__file__).parent
os.chdir(script_dir)

print(f"Starting server from: {os.getcwd()}")

# Start uvicorn
if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)